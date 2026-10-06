"""Backend-only Argon2 authentication and transactional email actions."""

import html
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


def send_email(address, kind, raw):
    s = get_settings()
    link = (
        s.account_public_url.rstrip("/")
        + "/api/v1/accounts/auth/action#"
        + urlencode({"token": raw, "kind": kind})
    )
    message = EmailMessage()
    message["From"] = s.account_mail_from
    message["To"] = address
    subject = "Iqtadi - Verify email" if kind == "verify" else "Iqtadi - Reset password"
    text = "افتح الرابط لإتمام الطلب. صالح لمدة 30 دقيقة، مرة واحدة فقط.\n" + link
    message["Subject"] = subject
    message.set_content(text)
    if s.account_mail_mode == "development":
        folder = Path(s.account_mail_outbox)
        folder.mkdir(parents=True, exist_ok=True)
        (folder / (str(uuid.uuid4()) + ".eml")).write_bytes(message.as_bytes())
        return "development_outbox"
    if s.account_mail_mode == "resend":
        if not s.account_resend_api_key or not s.account_mail_from:
            raise HTTPException(503, "EMAIL_SERVICE_NOT_CONFIGURED")
        try:
            response = httpx.post(
                "https://api.resend.com/emails",
                headers={
                    "Authorization": f"Bearer {s.account_resend_api_key}",
                    "Idempotency-Key": f"iqtadi-{kind}-{digest(raw)}",
                },
                json={
                    "from": s.account_mail_from,
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
        except ValueError:
            provider_id = None
        if not provider_id:
            raise HTTPException(503, "EMAIL_SERVICE_UNAVAILABLE")
        return "resend"
    if not s.account_smtp_host:
        raise HTTPException(503, "EMAIL_SERVICE_NOT_CONFIGURED")
    try:
        with smtplib.SMTP(s.account_smtp_host, s.account_smtp_port, timeout=10) as smtp:
            smtp.starttls(context=ssl.create_default_context())
            if s.account_smtp_user:
                smtp.login(s.account_smtp_user, s.account_smtp_password)
            smtp.send_message(message)
    except (OSError, smtplib.SMTPException):
        raise HTTPException(503, "EMAIL_SERVICE_UNAVAILABLE") from None
    return "smtp"


def email_action(db, user_id, address, kind):
    raw = secrets.token_urlsafe(32)
    db.execute(
        "UPDATE email_tokens SET used_at=? WHERE user_id=? AND kind=? AND used_at IS NULL",
        (time.time(), user_id, kind),
    )
    db.execute(
        "INSERT INTO email_tokens VALUES(?,?,?,?,NULL)",
        (digest(raw), user_id, kind, time.time() + 1800),
    )
    return send_email(address, kind, raw) or mail_delivery_kind()


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
