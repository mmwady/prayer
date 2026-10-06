"""Committed email intent, leased retries and authenticated Resend receipts.

No network operation runs while holding the account write transaction. Raw link
tokens exist only in pending private payloads; successful/obsolete jobs scrub them.
"""

import asyncio
import base64
import binascii
import hashlib
import hmac
import json
import logging
import sqlite3
import time
import uuid
from datetime import datetime
from urllib.parse import urlencode

from fastapi import HTTPException

from ..config import get_settings
from .store import digest

logger = logging.getLogger(__name__)
LEASE_SECONDS = 120


def enqueue_email(db, user_id, address, kind, raw):
    settings = get_settings()
    key = str(uuid.uuid4())
    payload = {
        "address": address,
        "kind": kind,
        "raw": raw,
        "mode": settings.account_mail_mode,
        "sender": settings.account_mail_from,
        "link": settings.account_public_url.rstrip("/")
        + "/api/v1/accounts/auth/action#"
        + urlencode({"token": raw, "kind": kind}),
    }
    now = time.time()
    db.execute(
        """INSERT INTO account_email_outbox
           (id,user_id,token_hash,kind,mode,payload,next_attempt_at,created_at)
           VALUES(?,?,?,?,?,?,?,?)""",
        (
            key,
            user_id,
            digest(raw),
            kind,
            settings.account_mail_mode,
            json.dumps(payload),
            now,
            now,
        ),
    )
    return key


def _apply_receipts(db, provider_id):
    event = db.execute(
        """SELECT status FROM account_email_events WHERE provider_id=?
           ORDER BY occurred_at DESC,
           CASE status WHEN 'BOUNCED' THEN 3 WHEN 'FAILED' THEN 2 ELSE 1 END DESC LIMIT 1""",
        (provider_id,),
    ).fetchone()
    if event:
        db.execute(
            "UPDATE account_email_outbox SET delivery_status=? WHERE provider_id=?",
            (event["status"], provider_id),
        )


def dispatch_email(database, job_id=None):
    """Send at most one committed job. Leases exclude concurrent workers/API calls."""
    now = time.time()
    lease = str(uuid.uuid4())
    job = None
    with database.transaction() as db:
        db.execute(
            """UPDATE account_email_outbox SET state='EXPIRED',payload=NULL,
               lease_id=NULL,lease_until=NULL WHERE state IN ('PENDING','SENDING')
               AND token_hash IN (SELECT token_hash FROM email_tokens
                                  WHERE expires_at<=? OR used_at IS NOT NULL)""",
            (now,),
        )
        row = db.execute(
            """SELECT * FROM account_email_outbox
               WHERE (state='PENDING' OR (state='SENDING' AND lease_until<=?))
               AND next_attempt_at<=? AND (? IS NULL OR id=?)
               ORDER BY created_at LIMIT 1""",
            (now, now, job_id, job_id),
        ).fetchone()
        if row is not None:
            job = dict(row)
            db.execute(
                """UPDATE account_email_outbox SET state='SENDING',attempts=attempts+1,
                   lease_id=?,lease_until=? WHERE id=?""",
                (lease, now + LEASE_SECONDS, job["id"]),
            )
    if job is None:
        return email_submission(database, job_id) if job_id else None
    # Account and token are already durable, and the write lock has been released.
    from .auth import send_email

    payload = json.loads(job["payload"])
    try:
        receipt = send_email(payload["address"], payload["kind"], payload["raw"], envelope=payload)
    except HTTPException as error:
        # Only a safe application error code is stored; never provider payloads/keys.
        delay = min(300, 30 * 2 ** min(job["attempts"], 4))
        with database.transaction() as db:
            db.execute(
                """UPDATE account_email_outbox SET state='PENDING',error_code=?,
                   next_attempt_at=?,lease_id=NULL,lease_until=NULL
                   WHERE id=? AND lease_id=? AND state='SENDING'""",
                (str(error.detail), time.time() + delay, job["id"], lease),
            )
    else:
        provider_id = receipt.get("provider_id") if receipt else None
        with database.transaction() as db:
            db.execute(
                """UPDATE account_email_outbox SET state='ACCEPTED',accepted_at=?,
                   error_code=NULL,provider_id=?,payload=NULL,lease_id=NULL,lease_until=NULL
                   WHERE id=? AND lease_id=? AND state='SENDING'""",
                (time.time(), provider_id, job["id"], lease),
            )
            if provider_id:
                _apply_receipts(db, provider_id)
    return email_submission(database, job["id"])


def email_submission(database, job_id):
    with database.transaction() as db:
        job = db.execute(
            "SELECT mode,state,error_code FROM account_email_outbox WHERE id=?", (job_id,)
        ).fetchone()
    if not job or job["state"] != "ACCEPTED":
        return {
            "delivery": "queued",
            "submission": "queued",
            **({"delivery_error": job["error_code"]} if job and job["error_code"] else {}),
        }
    mode = "development_outbox" if job["mode"] == "development" else job["mode"]
    return {
        "delivery": mode,
        "submission": "stored" if mode == "development_outbox" else "accepted",
    }


class EmailWorker:
    def __init__(self, database):
        self.database = database
        self.stopping = asyncio.Event()
        self.task = None

    async def start(self):
        self.task = asyncio.create_task(self.run())

    async def close(self):
        self.stopping.set()
        if self.task:
            await self.task

    async def run(self):
        while not self.stopping.is_set():
            try:
                await asyncio.to_thread(dispatch_email, self.database)
            except sqlite3.OperationalError:
                # Leave intent/lease durable for the next attempt after lock recovery.
                logger.warning("Account mail database unavailable; retrying")
            try:
                await asyncio.wait_for(self.stopping.wait(), timeout=2)
            except TimeoutError:
                pass


def verify_resend_signature(body, headers):
    """Svix v1: verify raw bytes, timestamp and signature before parsing anything."""
    secret = get_settings().account_resend_webhook_secret
    if not secret:
        raise HTTPException(503, "EMAIL_WEBHOOK_NOT_CONFIGURED")
    event_id = headers.get("svix-id", "")
    timestamp = headers.get("svix-timestamp", "")
    signatures = headers.get("svix-signature", "")
    try:
        if not event_id or len(event_id) > 200 or abs(time.time() - int(timestamp)) > 300:
            raise ValueError("Invalid webhook timestamp/identifier")
        key = base64.b64decode(secret.removeprefix("whsec_"), validate=True)
        if not key:
            raise ValueError("Empty secret")
        expected = base64.b64encode(
            hmac.new(
                key,
                f"{event_id}.{timestamp}.".encode() + body,
                hashlib.sha256,
            ).digest()
        ).decode()
        if not any(
            hmac.compare_digest(signature.encode(), ("v1," + expected).encode())
            for signature in signatures.split()
        ):
            raise ValueError("Invalid signature")
    except (ValueError, binascii.Error):
        raise HTTPException(400, "EMAIL_WEBHOOK_INVALID") from None
    return event_id


def record_resend_event(database, body, headers):
    event_id = verify_resend_signature(body, headers)
    try:
        event = json.loads(body)
        provider_id = event["data"]["email_id"]
        occurred = datetime.fromisoformat(event["created_at"].replace("Z", "+00:00"))
        if (
            not isinstance(provider_id, str)
            or not 1 <= len(provider_id) <= 200
            or not occurred.tzinfo
        ):
            raise ValueError("Invalid event")
        status = {
            "email.delivered": "DELIVERED",
            "email.bounced": "BOUNCED",
            "email.failed": "FAILED",
            "email.suppressed": "SUPPRESSED",
            "email.complained": "COMPLAINED",
            "email.delivery_delayed": "DELAYED",
        }.get(event["type"])
    except (ValueError, KeyError, TypeError, AttributeError):
        raise HTTPException(400, "EMAIL_WEBHOOK_INVALID") from None
    if status:
        with database.transaction() as db:
            # Receipts may precede the HTTP acknowledgement; retain and reconcile later.
            db.execute(
                "INSERT OR IGNORE INTO account_email_events VALUES(?,?,?,?)",
                (event_id, provider_id, status, occurred.timestamp()),
            )
            _apply_receipts(db, provider_id)
    return {"received": True}
