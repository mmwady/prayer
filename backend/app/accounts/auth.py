"""Backend-only Argon2 authentication and transactional email actions."""

import html
import json
import secrets
import smtplib
import ssl
import time
import uuid
from datetime import datetime, timezone
from email.message import EmailMessage
from pathlib import Path
from urllib.parse import urlencode

import httpx
from fastapi import HTTPException
from pwdlib import PasswordHash
from pydantic import BaseModel, ConfigDict, EmailStr, Field

from ..config import get_settings
from .store import digest, ensure_personal_profile
from .mail import enqueue_email

passwords = PasswordHash.recommended()
DUMMY_HASH = passwords.hash(secrets.token_urlsafe(32))


class AuthBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)


class SignupBody(AuthBody):
    name: str = Field(min_length=1, max_length=100)
    # Accepted only for backwards compatibility with pre-v2 clients.  Roles are
    # now scoped memberships, never a permanent account type selected at signup.
    role: str | None = Field(default=None, pattern="^(PARENT|TEACHER)$")
    learning_stage: str = Field(default="GENERAL", pattern="^(GENERAL|NEW_MUSLIM)$")
    accessibility_mode: str = Field(default="STANDARD", pattern="^(STANDARD|SIMPLE|LARGE_TEXT)$")


class EmailBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    email: EmailStr


class ActionBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    token: str = Field(min_length=20, max_length=200)


class ResetBody(ActionBody):
    password: str = Field(min_length=8, max_length=128)


def mail_delivery_kind():
    mode = get_settings().account_mail_mode
    return "development_outbox" if mode == "development" else mode


def send_email(address, kind, raw, *, envelope=None):
    s = get_settings()
    mode = envelope["mode"] if envelope else s.account_mail_mode
    sender = envelope["sender"] if envelope else s.account_mail_from
    link = envelope["link"] if envelope else (
        s.account_public_url.rstrip("/")
        + "/api/v1/accounts/auth/action#"
        + urlencode({"token": raw, "kind": kind})
    )
    message = EmailMessage()
    message["From"] = sender
    message["To"] = address
    subject = "Iqtadi - Verify email" if kind == "verify" else "Iqtadi - Reset password"
    text = "افتح الرابط لإتمام الطلب. صالح لمدة 30 دقيقة، مرة واحدة فقط.\n" + link
    message["Subject"] = subject
    message["Message-ID"] = f"<iqtadi-{kind}-{digest(raw)}@iqtadi.local>"
    message.set_content(text)
    if mode == "development":
        folder = Path(s.account_mail_outbox)
        folder.mkdir(parents=True, exist_ok=True)
        (folder / (digest(raw) + ".eml")).write_bytes(message.as_bytes())
        return {"mode": "development_outbox", "provider_id": None}
    if mode == "resend":
        if not s.account_resend_api_key or not sender:
            raise HTTPException(503, "EMAIL_SERVICE_NOT_CONFIGURED")
        try:
            response = httpx.post(
                "https://api.resend.com/emails",
                headers={
                    "Authorization": f"Bearer {s.account_resend_api_key}",
                    "Idempotency-Key": f"iqtadi-{kind}-{digest(raw)}",
                },
                json={
                    "from": sender,
                    "to": [address],
                    "subject": subject,
                    "text": text,
                    "html": (
                        '<div dir="rtl" lang="ar">'
                        "<p>افتح الرابط لإتمام الطلب. صالح لمدة 30 دقيقة، مرة واحدة فقط.</p>"
                        f'<p><a href="{html.escape(link, quote=True)}">إتمام الطلب</a></p>'
                        "</div>"
                    ),
                },
                timeout=10,
            )
        except httpx.HTTPError:
            raise HTTPException(503, "EMAIL_SERVICE_UNAVAILABLE") from None
        if not 200 <= response.status_code < 300:
            provider_message = ""
            try:
                provider_message = str(response.json().get("message", "")).casefold()
            except (ValueError, AttributeError):
                pass
            detail = {
                401: "EMAIL_API_KEY_INVALID",
                403: "EMAIL_SENDER_NOT_VERIFIED",
                422: "EMAIL_PROVIDER_REJECTED",
                429: "EMAIL_RATE_LIMITED",
            }.get(response.status_code, "EMAIL_SERVICE_UNAVAILABLE")
            if response.status_code == 403 and "only send testing emails" in provider_message:
                detail = "EMAIL_TEST_RECIPIENT_RESTRICTED"
            raise HTTPException(503, detail)
        try:
            provider_id = response.json().get("id")
        except (ValueError, AttributeError):
            provider_id = None
        if not isinstance(provider_id, str) or not 1 <= len(provider_id) <= 200:
            raise HTTPException(503, "EMAIL_SERVICE_UNAVAILABLE")
        return {"mode": "resend", "provider_id": provider_id}
    if not s.account_smtp_host:
        raise HTTPException(503, "EMAIL_SERVICE_NOT_CONFIGURED")
    try:
        implicit_ssl = s.account_smtp_security == "ssl" or (
            s.account_smtp_security == "auto" and s.account_smtp_port == 465
        )
        context = ssl.create_default_context()
        connection = (
            smtplib.SMTP_SSL(s.account_smtp_host, s.account_smtp_port,
                             timeout=10, context=context)
            if implicit_ssl else smtplib.SMTP(s.account_smtp_host, s.account_smtp_port, timeout=10)
        )
        with connection as smtp:
            if not implicit_ssl:
                smtp.starttls(context=context)
            if s.account_smtp_user:
                smtp.login(s.account_smtp_user, s.account_smtp_password)
            smtp.send_message(message)
    except (OSError, smtplib.SMTPException):
        raise HTTPException(503, "EMAIL_SERVICE_UNAVAILABLE") from None
    return {"mode": "smtp", "provider_id": None}


def email_action(db, user_id, address, kind):
    # A failed/ambiguous send is retried with the same token and Resend key.
    pending = db.execute(
        """SELECT o.id,o.payload,o.error_code,o.state FROM account_email_outbox o JOIN email_tokens t
           ON t.token_hash=o.token_hash WHERE o.user_id=? AND o.kind=?
           AND o.state IN ('PENDING','SENDING') AND t.used_at IS NULL
           AND t.expires_at>? ORDER BY o.created_at DESC LIMIT 1""",
        (user_id, kind, time.time() + 60),
    ).fetchone()
    replace_rejected = False
    if pending and pending["state"] == "PENDING" and pending["error_code"] in {
        "EMAIL_SERVICE_NOT_CONFIGURED", "EMAIL_SENDER_NOT_VERIFIED",
        "EMAIL_PROVIDER_REJECTED", "EMAIL_TEST_RECIPIENT_RESTRICTED", "EMAIL_API_KEY_INVALID",
    }:
        # Explicitly rejected requests may be replaced after sender/URL/mode fixes.
        # Ambiguous timeouts always retain their original body and idempotency key.
        payload = json.loads(pending["payload"])
        settings = get_settings()
        link = settings.account_public_url.rstrip("/") + "/api/v1/accounts/auth/action#" + urlencode({
            "token": payload["raw"], "kind": kind,
        })
        replace_rejected = (payload["sender"], payload["link"], payload["mode"]) != (
            settings.account_mail_from, link, settings.account_mail_mode,
        )
    if pending and not replace_rejected:
        db.execute("UPDATE account_email_outbox SET next_attempt_at=? WHERE id=?",
                   (time.time(), pending["id"]))
        return pending["id"]
    raw = secrets.token_urlsafe(32)
    db.execute(
        """UPDATE account_email_outbox SET state='SUPERSEDED',payload=NULL
           WHERE user_id=? AND kind=? AND state IN ('PENDING','SENDING')""",
        (user_id, kind),
    )
    db.execute(
        "UPDATE email_tokens SET used_at=? WHERE user_id=? AND kind=? AND used_at IS NULL",
        (time.time(), user_id, kind),
    )
    db.execute(
        "INSERT INTO email_tokens VALUES(?,?,?,?,NULL)",
        (digest(raw), user_id, kind, time.time() + 1800),
    )
    return enqueue_email(db, user_id, address, kind, raw)


def consume(db, raw, kind):
    row = db.execute(
        "SELECT * FROM email_tokens WHERE token_hash=? AND kind=? AND expires_at>? AND used_at IS NULL",
        (digest(raw), kind, time.time()),
    ).fetchone()
    if not row:
        raise HTTPException(400, "EMAIL_LINK_INVALID_OR_EXPIRED")
    db.execute("UPDATE email_tokens SET used_at=? WHERE token_hash=?", (time.time(), digest(raw)))
    return row["user_id"]


def register(db, body):
    email = str(body.email).casefold()
    existing = db.execute(
        "SELECT id,email_verified FROM guardians WHERE email=?", (email,)
    ).fetchone()
    if existing:
        if not existing["email_verified"]:
            return email_action(db, existing["id"], email, "verify")
        raise HTTPException(409, "ACCOUNT_ALREADY_EXISTS")
    key = str(uuid.uuid4())
    created_at = datetime.now(timezone.utc).isoformat()
    db.execute(
        """INSERT INTO guardians
           (id,name,email,role,created_at,password_hash,email_verified,
            learning_stage,accessibility_mode)
           VALUES(?,?,?,?,?,?,?,?,?)""",
        (
            key,
            body.name.strip(),
            email,
            "PARENT",  # legacy storage value; authorization never reads it in v2
            created_at,
            passwords.hash(body.password),
            0,
            body.learning_stage,
            body.accessibility_mode,
        ),
    )
    ensure_personal_profile(db, key, body.name.strip(), created_at)
    return email_action(db, key, email, "verify")


def authenticate(db, body):
    row = db.execute(
        "SELECT * FROM guardians WHERE email=?", (str(body.email).casefold(),)
    ).fetchone()
    if not passwords.verify(body.password, row["password_hash"] if row else DUMMY_HASH) or not row:
        raise HTTPException(401, "INVALID_LOGIN_CREDENTIALS")
    if not row["email_verified"]:
        raise HTTPException(403, "EMAIL_VERIFICATION_REQUIRED")
    return identity(row)


def identity(row):
    """Public account identity; authorization roles live in membership tables."""

    return {
        "id": row["id"],
        "name": row["name"],
        "email": row["email"],
        "role": "MEMBER",
        "learning_stage": row["learning_stage"],
        "accessibility_mode": row["accessibility_mode"],
    }
