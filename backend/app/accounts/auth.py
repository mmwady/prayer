"""Backend-only Argon2 authentication and SMTP email actions."""

import secrets
import smtplib
import ssl
import time
import uuid
from datetime import datetime, timezone
from email.message import EmailMessage
from pathlib import Path
from urllib.parse import urlencode
from fastapi import HTTPException
from pydantic import BaseModel, ConfigDict, EmailStr, Field
from pwdlib import PasswordHash
from ..config import get_settings
from .store import digest

passwords = PasswordHash.recommended()
DUMMY_HASH = passwords.hash(secrets.token_urlsafe(32))


class AuthBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    email: EmailStr
    password: str = Field(min_length=10, max_length=128)


class SignupBody(AuthBody):
    name: str = Field(min_length=1, max_length=100)
    role: str = Field(pattern="^(PARENT|TEACHER)$")


class EmailBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    email: EmailStr


class ActionBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    token: str = Field(min_length=20, max_length=200)


class ResetBody(ActionBody):
    password: str = Field(min_length=10, max_length=128)


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
    message["Subject"] = "Iqtadi - Verify email" if kind == "verify" else "Iqtadi - Reset password"
    message.set_content("افتح الرابط لإتمام الطلب. صالح لمدة 30 دقيقة، مرة واحدة فقط.\n" + link)
    if s.account_mail_mode == "development":
        folder = Path(s.account_mail_outbox)
        folder.mkdir(parents=True, exist_ok=True)
        (folder / (str(uuid.uuid4()) + ".eml")).write_bytes(message.as_bytes())
        return
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
    send_email(address, kind, raw)


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
    if db.execute("SELECT id FROM guardians WHERE email=?", (email,)).fetchone():
        return
    key = str(uuid.uuid4())
    db.execute(
        "INSERT INTO guardians VALUES(?,?,?,?,?,?,?)",
        (
            key,
            body.name.strip(),
            email,
            body.role,
            datetime.now(timezone.utc).isoformat(),
            passwords.hash(body.password),
            0,
        ),
    )
    email_action(db, key, email, "verify")


def authenticate(db, body):
    row = db.execute(
        "SELECT * FROM guardians WHERE email=?", (str(body.email).casefold(),)
    ).fetchone()
    if not passwords.verify(body.password, row["password_hash"] if row else DUMMY_HASH) or not row:
        raise HTTPException(401, "INVALID_LOGIN_CREDENTIALS")
    if not row["email_verified"]:
        raise HTTPException(403, "EMAIL_VERIFICATION_REQUIRED")
    return {k: row[k] for k in ("id", "name", "email", "role")}
