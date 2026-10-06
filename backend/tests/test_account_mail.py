"""Real DB/HTTP contracts; controlled transports never send external mail."""

import base64
import hashlib
import hmac
import json
import smtplib
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone

import httpx
import pytest
from fastapi import HTTPException

from app.accounts import auth, mail
from app.accounts.store import AccountStore
from app.config import get_settings
from tests.test_accounts import BASE, PASSWORD
from tests.test_accounts import env as env


def signup(client):
    return client.post(
        BASE + "/auth/signup",
        json={
            "name": "Parent",
            "email": "mail@example.com",
            "password": PASSWORD,
        },
    )


def pending_job(env, monkeypatch):
    client, _, database = env
    monkeypatch.setattr(
        auth,
        "send_email",
        lambda *args, **kwargs: (_ for _ in ()).throw(
            HTTPException(503, "EMAIL_SERVICE_UNAVAILABLE")
        ),
    )
    response = signup(client)
    assert response.status_code == 200
    assert response.json()["delivery"] == "queued"
    with database.transaction() as db:
        job = dict(db.execute("SELECT * FROM account_email_outbox").fetchone())
    return job, json.loads(job["payload"])


def due(database, job_id):
    with database.transaction() as db:
        db.execute("UPDATE account_email_outbox SET next_attempt_at=0 WHERE id=?", (job_id,))


def test_account_and_token_commit_before_provider_and_scrub_after_accept(env, monkeypatch):
    client, _, database = env
    captured = []

    def deliver(address, kind, raw, **kwargs):
        # A second write transaction succeeds while the provider is running.
        with database.transaction() as db:
            user = db.execute("SELECT * FROM guardians").fetchone()
            assert user["email_verified"] == 0
            assert db.execute("SELECT count(*) FROM email_tokens").fetchone()[0] == 1
            db.execute("UPDATE guardians SET name=name")
        captured.append(raw)
        return {"mode": "smtp", "provider_id": None}

    monkeypatch.setattr(auth, "send_email", deliver)
    response = signup(client)
    assert response.status_code == 200 and response.json()["submission"] == "accepted"
    with database.transaction() as db:
        job = db.execute("SELECT * FROM account_email_outbox").fetchone()
        assert job["payload"] is None and job["state"] == "ACCEPTED"
        assert job["delivery_status"] == "UNKNOWN"
    assert client.post(BASE + "/auth/verify", json={"token": captured[0]}).status_code == 200


def test_failed_transaction_creates_no_email_intent_or_send(env, monkeypatch):
    _, messages, database = env
    with pytest.raises(RuntimeError), database.transaction() as db:
        auth.register(
            db, auth.SignupBody(name="Parent", email="mail@example.com", password=PASSWORD)
        )
        raise RuntimeError("Commit aborted")
    assert mail.dispatch_email(database) is None
    assert messages == []
    with database.transaction() as db:
        assert db.execute("SELECT count(*) FROM guardians").fetchone()[0] == 0
        assert db.execute("SELECT count(*) FROM account_email_outbox").fetchone()[0] == 0


def test_pending_signup_reuses_token_and_recovers_after_restart(env, monkeypatch):
    client, _, database = env
    job, payload = pending_job(env, monkeypatch)
    assert signup(client).json()["delivery"] == "queued"
    with database.transaction() as db:
        assert db.execute("SELECT count(*) FROM guardians").fetchone()[0] == 1
        assert db.execute("SELECT count(*) FROM email_tokens").fetchone()[0] == 1
        assert (
            db.execute("SELECT payload FROM account_email_outbox").fetchone()[0] == job["payload"]
        )
    captured = []
    monkeypatch.setattr(
        auth, "send_email", lambda address, kind, raw, **kwargs: captured.append(raw)
    )
    restarted = AccountStore(database.path)
    due(restarted, job["id"])
    assert mail.dispatch_email(restarted)["submission"] == "accepted"
    assert captured == [payload["raw"]]
    assert client.post(BASE + "/auth/verify", json={"token": payload["raw"]}).status_code == 200


def test_timeout_after_resend_accept_retries_identical_envelope_and_key(env, monkeypatch):
    client, _, database = env
    monkeypatch.setenv("ACCOUNT_MAIL_MODE", "resend")
    monkeypatch.setenv("ACCOUNT_RESEND_API_KEY", "test-key")
    get_settings.cache_clear()
    monkeypatch.setattr(auth, "send_email", REAL_SEND_EMAIL)
    calls = []

    def provider(url, **kwargs):
        calls.append(kwargs)
        if len(calls) == 1:
            raise httpx.ReadTimeout("Acknowledgement lost")
        return httpx.Response(200, json={"id": "provider-123"})

    monkeypatch.setattr(auth.httpx, "post", provider)
    assert signup(client).json()["delivery"] == "queued"
    with database.transaction() as db:
        job = db.execute("SELECT * FROM account_email_outbox").fetchone()
        assert job["payload"] and job["error_code"] == "EMAIL_SERVICE_UNAVAILABLE"
        job_id = job["id"]
    monkeypatch.setenv("ACCOUNT_PUBLIC_URL", "https://changed.example")
    monkeypatch.setenv("ACCOUNT_MAIL_FROM", "changed@example.com")
    get_settings.cache_clear()
    due(database, job_id)
    assert mail.dispatch_email(database)["submission"] == "accepted"
    assert calls[0]["json"] == calls[1]["json"]
    assert calls[0]["headers"]["Idempotency-Key"] == calls[1]["headers"]["Idempotency-Key"]


REAL_SEND_EMAIL = auth.send_email


def test_sender_configuration_fix_can_replace_definitively_rejected_job(env, monkeypatch):
    client, _, database = env
    monkeypatch.setattr(
        auth,
        "send_email",
        lambda *args, **kwargs: (_ for _ in ()).throw(
            HTTPException(503, "EMAIL_SENDER_NOT_VERIFIED")
        ),
    )
    assert signup(client).json()["delivery"] == "queued"
    monkeypatch.setenv("ACCOUNT_MAIL_FROM", "verified@example.com")
    get_settings.cache_clear()
    captured = []
    monkeypatch.setattr(
        auth, "send_email", lambda *args, **kwargs: captured.append(kwargs["envelope"])
    )
    assert signup(client).json()["submission"] == "accepted"
    assert captured[0]["sender"] == "verified@example.com"
    with database.transaction() as db:
        rows = db.execute(
            "SELECT state,payload FROM account_email_outbox ORDER BY created_at"
        ).fetchall()
        assert [row["state"] for row in rows] == ["SUPERSEDED", "ACCEPTED"]
        assert all(row["payload"] is None for row in rows)


def test_provider_accept_then_db_ack_failure_keeps_retryable_valid_link(env, monkeypatch):
    import sqlite3
    from contextlib import contextmanager

    client, _, database = env
    job, payload = pending_job(env, monkeypatch)
    normal_transaction = database.transaction

    @contextmanager
    def broken_ack():
        raise sqlite3.OperationalError("Ack commit failed")
        yield  # pragma: no cover

    def accepted(*args, **kwargs):
        monkeypatch.setattr(database, "transaction", broken_ack)
        return {"mode": "resend", "provider_id": "provider-ack-123"}

    monkeypatch.setattr(auth, "send_email", accepted)
    due(database, job["id"])
    with pytest.raises(sqlite3.OperationalError):
        mail.dispatch_email(database, job["id"])
    monkeypatch.setattr(database, "transaction", normal_transaction)
    with database.transaction() as db:
        row = db.execute("SELECT state,payload FROM account_email_outbox").fetchone()
        assert row["state"] == "SENDING" and json.loads(row["payload"])["raw"] == payload["raw"]
        db.execute("UPDATE account_email_outbox SET lease_until=0")
    monkeypatch.setattr(
        auth,
        "send_email",
        lambda *args, **kwargs: {"mode": "resend", "provider_id": "provider-ack-123"},
    )
    assert mail.dispatch_email(database)["submission"] == "accepted"
    assert client.post(BASE + "/auth/verify", json={"token": payload["raw"]}).status_code == 200


def test_pending_link_replacement_scrubs_superseded_job(env, monkeypatch):
    _, _, database = env
    job, payload = pending_job(env, monkeypatch)
    with database.transaction() as db:
        db.execute(
            "UPDATE email_tokens SET expires_at=? WHERE token_hash=?",
            (time.time() + 20, job["token_hash"]),
        )
        replacement = auth.email_action(db, job["user_id"], "mail@example.com", "verify")
        assert replacement != job["id"]
        old = db.execute("SELECT * FROM account_email_outbox WHERE id=?", (job["id"],)).fetchone()
        assert old["state"] == "SUPERSEDED" and old["payload"] is None
        with pytest.raises(HTTPException):
            auth.consume(db, payload["raw"], "verify")


def test_leases_exclude_simultaneous_dispatch_and_recover_crash(env, monkeypatch):
    _, _, database = env
    job, _ = pending_job(env, monkeypatch)
    due(database, job["id"])
    entered, release = threading.Event(), threading.Event()
    calls = []

    def deliver(*args, **kwargs):
        calls.append(args)
        entered.set()
        assert release.wait(10)

    monkeypatch.setattr(auth, "send_email", deliver)
    with ThreadPoolExecutor(max_workers=1) as executor:
        first = executor.submit(mail.dispatch_email, database, job["id"])
        try:
            assert entered.wait(10)
            assert mail.dispatch_email(database, job["id"])["delivery"] == "queued"
            assert len(calls) == 1
        finally:
            release.set()
        assert first.result(timeout=10)["submission"] == "accepted"
    # Another job simulates process death before the acknowledgement was stored.
    with database.transaction() as db:
        new_id = auth.email_action(db, job["user_id"], "mail@example.com", "verify")
        db.execute(
            "UPDATE account_email_outbox SET state='SENDING',lease_until=0 WHERE id=?", (new_id,)
        )
    assert mail.dispatch_email(database, new_id)["submission"] == "accepted"
    assert len(calls) == 2


def test_expired_and_superseded_jobs_cannot_send(env, monkeypatch):
    _, _, database = env
    job, _ = pending_job(env, monkeypatch)
    with database.transaction() as db:
        db.execute("UPDATE email_tokens SET expires_at=0")
    captured = []
    monkeypatch.setattr(auth, "send_email", lambda *args, **kwargs: captured.append(args))
    assert mail.dispatch_email(database) is None
    assert captured == []
    with database.transaction() as db:
        row = db.execute("SELECT * FROM account_email_outbox").fetchone()
        assert row["state"] == "EXPIRED" and row["payload"] is None
        assert db.execute("PRAGMA foreign_key_check").fetchall() == []
        assert db.execute("SELECT max(version) FROM account_schema").fetchone()[0] == 4


@pytest.mark.parametrize(
    "port,security,ssl_expected",
    [(587, "auto", False), (465, "auto", True), (587, "ssl", True), (465, "starttls", False)],
)
def test_smtp_tls_modes_and_failures(monkeypatch, port, security, ssl_expected):
    calls = []

    class SMTP:
        def __init__(self, *args, **kwargs):
            calls.append(("connect", kwargs.get("context") is not None))

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def starttls(self, **kwargs):
            calls.append(("starttls", kwargs["context"].check_hostname))

        def login(self, *args):
            calls.append(("login", True))

        def send_message(self, message):
            assert "#token=" in message.get_content()
            calls.append(("send", True))

    monkeypatch.setenv("ACCOUNT_MAIL_MODE", "smtp")
    monkeypatch.setenv("ACCOUNT_SMTP_HOST", "mail.example.com")
    monkeypatch.setenv("ACCOUNT_SMTP_PORT", str(port))
    monkeypatch.setenv("ACCOUNT_SMTP_SECURITY", security)
    monkeypatch.setenv("ACCOUNT_SMTP_USER", "user")
    get_settings.cache_clear()
    monkeypatch.setattr(auth.smtplib, "SMTP", SMTP)
    monkeypatch.setattr(auth.smtplib, "SMTP_SSL", SMTP)
    try:
        assert REAL_SEND_EMAIL("mail@example.com", "verify", "token-value")["mode"] == "smtp"
        assert calls[0] == ("connect", ssl_expected)
        assert ("starttls", True) in calls if not ssl_expected else ("starttls", True) not in calls
        monkeypatch.setattr(
            SMTP,
            "send_message",
            lambda *args: (_ for _ in ()).throw(
                smtplib.SMTPRecipientsRefused({"mail@example.com": (550, b"rejected")})
            ),
        )
        with pytest.raises(HTTPException, match="EMAIL_SERVICE_UNAVAILABLE"):
            REAL_SEND_EMAIL("mail@example.com", "verify", "token-value")
    finally:
        get_settings.cache_clear()


def signed_event(event_id, status, occurred, provider_id="provider-123"):
    body = json.dumps(
        {"type": "email." + status, "created_at": occurred, "data": {"email_id": provider_id}}
    ).encode()
    timestamp = str(int(time.time()))
    key = b"isolated-webhook-test-secret"
    signature = base64.b64encode(
        hmac.new(key, f"{event_id}.{timestamp}.".encode() + body, hashlib.sha256).digest()
    ).decode()
    return body, {
        "svix-id": event_id,
        "svix-timestamp": timestamp,
        "svix-signature": "v1," + signature,
    }


def test_signature_matches_published_svix_reference_vector(monkeypatch):
    # https://docs.svix.com/receiving/verifying-payloads/how-manual
    monkeypatch.setenv("ACCOUNT_RESEND_WEBHOOK_SECRET", "whsec_plJ3nmyCDGBKInavdOK15jsl")
    get_settings.cache_clear()
    monkeypatch.setattr(mail.time, "time", lambda: 1731705121)
    try:
        assert (
            mail.verify_resend_signature(
                b'{"event_type":"ping","data":{"success":true}}',
                {
                    "svix-id": "msg_loFOjxBNrRLzqYUf",
                    "svix-timestamp": "1731705121",
                    "svix-signature": "v1,rAvfW3dJ/X/qxhsaXPOyyCGmRKsaKWcsNccKXlIktD0=",
                },
            )
            == "msg_loFOjxBNrRLzqYUf"
        )
    finally:
        get_settings.cache_clear()


def test_signed_delivery_receipts_before_ack_replay_and_out_of_order(env, monkeypatch):
    client, _, database = env
    job, _ = pending_job(env, monkeypatch)
    monkeypatch.setenv(
        "ACCOUNT_RESEND_WEBHOOK_SECRET",
        "whsec_" + base64.b64encode(b"isolated-webhook-test-secret").decode(),
    )
    get_settings.cache_clear()
    now = datetime.now(timezone.utc)
    body, headers = signed_event("event-delivered", "delivered", now.isoformat())
    assert client.post(BASE + "/auth/mail-events", content=body, headers=headers).status_code == 200
    assert client.post(BASE + "/auth/mail-events", content=body, headers=headers).status_code == 200
    assert (
        client.post(BASE + "/auth/mail-events", content=body + b" ", headers=headers).status_code
        == 400
    )
    assert (
        client.post(
            BASE + "/auth/mail-events", content=body, headers={**headers, "svix-timestamp": "0"}
        ).status_code
        == 400
    )
    monkeypatch.setattr(
        auth,
        "send_email",
        lambda *args, **kwargs: {"mode": "resend", "provider_id": "provider-123"},
    )
    due(database, job["id"])
    mail.dispatch_email(database)
    body, headers = signed_event(
        "event-old-delay", "delivery_delayed", (now - timedelta(seconds=5)).isoformat()
    )
    assert client.post(BASE + "/auth/mail-events", content=body, headers=headers).status_code == 200
    with database.transaction() as db:
        assert (
            db.execute("SELECT delivery_status FROM account_email_outbox").fetchone()[0]
            == "DELIVERED"
        )
        assert db.execute("SELECT email_verified FROM guardians").fetchone()[0] == 0
        assert db.execute("SELECT count(*) FROM account_email_events").fetchone()[0] == 2
    body, headers = signed_event(
        "event-bounce", "bounced", (now + timedelta(seconds=1)).isoformat()
    )
    client.post(BASE + "/auth/mail-events", content=body, headers=headers)
    with database.transaction() as db:
        assert (
            db.execute("SELECT delivery_status FROM account_email_outbox").fetchone()[0]
            == "BOUNCED"
        )


@pytest.mark.asyncio
async def test_background_worker_drains_committed_intent(env, monkeypatch):
    import asyncio

    _, _, database = env
    job, _ = pending_job(env, monkeypatch)
    captured = threading.Event()
    monkeypatch.setattr(auth, "send_email", lambda *args, **kwargs: captured.set())
    due(database, job["id"])
    worker = mail.EmailWorker(AccountStore(database.path))
    await worker.start()
    try:
        assert await asyncio.to_thread(captured.wait, 10)
    finally:
        await worker.close()
    assert mail.email_submission(database, job["id"])["submission"] == "accepted"
