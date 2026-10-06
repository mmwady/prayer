"""Owner/device API. Strict minimal result bodies; no inference input endpoint."""

import json
import secrets
import time
import uuid
from datetime import date, datetime, timedelta, timezone
from urllib.parse import quote
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, ConfigDict, Field, model_validator

from ..config import get_settings
from .auth import (
    ActionBody,
    AuthBody,
    EmailBody,
    ResetBody,
    SignupBody,
    authenticate,
    consume,
    email_action,
    identity,
    passwords,
    register,
)
from .domain import RAKATS, PrayerTimeService, progress
from ..analysis.domain import stations
from .store import AccountStore, digest, ensure_personal_profile

router = APIRouter(prefix="/api/v1/accounts", tags=["optional accounts"])
COOKIE_PATH = "/api/v1/accounts"
DEVICE_SESSION_SECONDS = 180 * 86400


def store():
    return AccountStore(get_settings().account_db)


def boundary(request: Request):
    origin = request.headers.get("origin")
    if origin and origin not in [
        *get_settings().account_allowed_origins,
        get_settings().account_public_url.rstrip("/"),
    ]:
        raise HTTPException(403, "ORIGIN_NOT_ALLOWED")
    if request.headers.get("x-iqtadi-account") != "1":
        raise HTTPException(403, "ACCOUNT_HEADER_REQUIRED")


def limited(request, db, scope, maximum):
    key = scope + ":" + digest(request.client.host if request.client else "unknown")
    now = time.time()
    row = db.execute("SELECT * FROM rate_limits WHERE key=?", (key,)).fetchone()
    if not row or row["resets_at"] <= now:
        db.execute("INSERT OR REPLACE INTO rate_limits VALUES(?,?,?)", (key, 1, now + 300))
    elif row["count"] >= maximum:
        raise HTTPException(429, "TRY_AGAIN_LATER")
    else:
        db.execute("UPDATE rate_limits SET count=count+1 WHERE key=?", (key,))


def token(request, kind):
    boundary(request)
    auth = request.headers.get("authorization", "")
    return auth[7:] if auth.startswith("Bearer ") else request.cookies.get("iqtadi_" + kind, "")


def guardian(request: Request, database=Depends(store)):
    with database.transaction() as db:
        row = db.execute(
            "SELECT g.* FROM guardian_sessions s JOIN guardians g ON g.id=s.user_id WHERE s.token_hash=? AND s.expires_at>?",
            (digest(token(request, "guardian")), time.time()),
        ).fetchone()
        if not row:
            raise HTTPException(401, "SIGN_IN_REQUIRED")
        return identity(row)


def device(request: Request, response: Response, database=Depends(store)):
    raw_token = token(request, "device")
    now = time.time()
    with database.transaction() as db:
        row = db.execute(
            "SELECT d.*,c.name,c.active,c.profile_kind FROM devices d JOIN children c ON c.id=d.child_id WHERE d.token_hash=? AND d.revoked_at IS NULL AND d.expires_at>? AND c.active=1",
            (digest(raw_token), now),
        ).fetchone()
        if not row:
            raise HTTPException(401, "DEVICE_DISCONNECTED")
        expires = now + DEVICE_SESSION_SECONDS
        db.execute(
            "UPDATE devices SET last_seen_at=?,expires_at=? WHERE id=?",
            (now, expires, row["id"]),
        )
        if request.headers.get("x-iqtadi-platform") == "web" and request.method != "DELETE":
            response.set_cookie(
                "iqtadi_device",
                raw_token,
                max_age=DEVICE_SESSION_SECONDS,
                httponly=True,
                secure=get_settings().account_secure_cookies,
                samesite="strict",
                path=COOKIE_PATH,
            )
        return dict(row) | {"expires_at": expires}


def owned_group(db, group_id, owner):
    row = db.execute(
        "SELECT * FROM groups WHERE id=? AND owner_user_id=?", (group_id, owner["id"])
    ).fetchone()
    if not row:
        raise HTTPException(404, "GROUP_NOT_FOUND")
    return dict(row)


def owned_child(db, child_id, owner):
    row = db.execute(
        """SELECT DISTINCT c.* FROM children c
           LEFT JOIN guardian_links gl ON gl.child_id=c.id
           LEFT JOIN groups g ON g.id=c.group_id
           WHERE c.id=? AND (
             c.account_user_id=? OR gl.user_id=? OR
             (g.owner_user_id=? AND g.type='FAMILY'))""",
        (child_id, owner["id"], owner["id"], owner["id"]),
    ).fetchone()
    if not row:
        raise HTTPException(404, "CHILD_NOT_FOUND")
    return dict(row)


def session_response(request, response, kind, raw, seconds, data):
    web = request.headers.get("x-iqtadi-platform") == "web"
    if web:
        response.set_cookie(
            "iqtadi_" + kind,
            raw,
            max_age=seconds,
            httponly=True,
            secure=get_settings().account_secure_cookies,
            samesite="strict",
            path=COOKIE_PATH,
        )
    response.headers["Cache-Control"] = "no-store"
    return {**data, **({} if web else {"session_token": raw})}


@router.get("/config", dependencies=[Depends(boundary)])
def config():
    s = get_settings()
    email_configured = (
        bool(s.account_resend_api_key and s.account_mail_from)
        if s.account_mail_mode == "resend"
        else bool(s.account_smtp_host)
        if s.account_mail_mode == "smtp"
        else False
    )
    return {
        "email_configured": email_configured,
        "email_mode": s.account_mail_mode,
    }


@router.post("/session", dependencies=[Depends(boundary)])
def login(body: AuthBody, request: Request, response: Response, database=Depends(store)):
    raw = secrets.token_urlsafe(32)
    practice_raw = secrets.token_urlsafe(32)
    device_id = str(uuid.uuid4())
    with database.transaction() as db:
        limited(request, db, "login", 20)
    with database.transaction() as db:
        identity = authenticate(db, body)
        profile_id = ensure_personal_profile(
            db, identity["id"], identity["name"], datetime.now(timezone.utc).isoformat()
        )
        db.execute(
            "INSERT INTO guardian_sessions VALUES(?,?,?)",
            (digest(raw), identity["id"], time.time() + 30 * 86400),
        )
        db.execute(
            "INSERT INTO devices VALUES(?,?,?,?,?,?,?,NULL)",
            (
                device_id,
                profile_id,
                digest(practice_raw),
                request.headers.get("x-iqtadi-platform", "other"),
                time.time(),
                time.time(),
                time.time() + 180 * 86400,
            ),
        )
    web = request.headers.get("x-iqtadi-platform") == "web"
    if web:
        response.set_cookie(
            "iqtadi_device",
            practice_raw,
            max_age=180 * 86400,
            httponly=True,
            secure=get_settings().account_secure_cookies,
            samesite="strict",
            path=COOKIE_PATH,
        )
    data = session_response(
        request,
        response,
        "guardian",
        raw,
        30 * 86400,
        {
            "guardian": identity,
            "practice_profile": {
                "child_id": profile_id,
                "name": identity["name"],
                "device_id": device_id,
                "profile_kind": "SELF",
            },
        },
    )
    if not web:
        data["practice_session_token"] = practice_raw
    return data


@router.post("/auth/signup", dependencies=[Depends(boundary)])
def signup(body: SignupBody, request: Request, database=Depends(store)):
    with database.transaction() as db:
        limited(request, db, "email", 10)
    with database.transaction() as db:
        delivery = register(db, body)
    return {
        "message": "CHECK_EMAIL",
        "delivery": delivery,
    }


@router.post("/auth/resend", dependencies=[Depends(boundary)])
def resend(body: EmailBody, request: Request, database=Depends(store)):
    return request_email(body, request, database, "verify")


@router.post("/auth/recover", dependencies=[Depends(boundary)])
def recover(body: EmailBody, request: Request, database=Depends(store)):
    return request_email(body, request, database, "reset")


def request_email(body, request, database, kind):
    delivery = (
        "development_outbox"
        if get_settings().account_mail_mode == "development"
        else get_settings().account_mail_mode
    )
    with database.transaction() as db:
        limited(request, db, "email", 10)
    with database.transaction() as db:
        row = db.execute(
            "SELECT * FROM guardians WHERE email=?", (str(body.email).casefold(),)
        ).fetchone()
        if row and (kind == "reset" or not row["email_verified"]):
            delivery = email_action(db, row["id"], row["email"], kind)
    return {
        "message": "CHECK_EMAIL_IF_REGISTERED",
        "delivery": delivery,
    }


@router.post("/auth/verify", dependencies=[Depends(boundary)])
def verify(body: ActionBody, database=Depends(store)):
    with database.transaction() as db:
        key = consume(db, body.token, "verify")
        db.execute("UPDATE guardians SET email_verified=1 WHERE id=?", (key,))
    return {"verified": True}


@router.post("/auth/reset", dependencies=[Depends(boundary)])
def reset(body: ResetBody, database=Depends(store)):
    with database.transaction() as db:
        key = consume(db, body.token, "reset")
        db.execute(
            "UPDATE guardians SET password_hash=? WHERE id=?", (passwords.hash(body.password), key)
        )
        db.execute("DELETE FROM guardian_sessions WHERE user_id=?", (key,))
    return {"reset": True}


@router.get("/auth/action", response_class=HTMLResponse)
def email_page():
    return HTMLResponse(
        """<!doctype html><html lang="ar" dir="rtl"><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1"><title>اقتدِ — حسابك</title>
    <style>body{font-family:system-ui;background:#f6f0e5;color:#073e30;max-width:460px;margin:8vh auto;padding:24px}input,button{font:inherit;padding:12px;margin:12px 0;width:100%;box-sizing:border-box}button{background:#126b4d;color:white;border:0;border-radius:12px}</style>
    <h1>اقتدِ</h1><p id="title"></p><input id="password" type="password" minlength="8" maxlength="128" placeholder="كلمة المرور الجديدة (8 أحرف على الأقل)">
    <button id="go">تأكيد</button><p id="status" role="status"></p>
    <script>
    const p=new URLSearchParams(location.hash.slice(1)),kind=p.get('kind'),token=p.get('token');
    history.replaceState(null,'',location.pathname);
    const verify=kind==='verify',reset=kind==='reset',button=document.getElementById('go'),status=document.getElementById('status');
    document.getElementById('title').textContent=verify?'تفعيل البريد الإلكتروني':reset?'استعادة كلمة المرور':'رابط غير صالح';
    document.getElementById('password').hidden=!reset;
    if(!token||(!verify&&!reset)){button.disabled=true;status.textContent='الرابط غير مكتمل. اطلب رابطًا جديدًا من صفحة الحساب.';}
    button.onclick=async()=>{button.disabled=true;status.textContent='جارٍ التحقق…';try{const body={token};if(reset)body.password=document.getElementById('password').value;
    const r=await fetch('/api/v1/accounts/auth/'+kind,{method:'POST',headers:{'Content-Type':'application/json','X-Iqtadi-Account':'1'},body:JSON.stringify(body)});
    let result={};try{result=await r.json();}catch(_){}
    if(r.ok){button.hidden=true;status.textContent=verify?'تم تفعيل البريد بنجاح. عد إلى التطبيق وسجّل الدخول.':'تم تغيير كلمة المرور. عد إلى التطبيق وسجّل الدخول.';return;}
    status.textContent=result.detail==='EMAIL_LINK_INVALID_OR_EXPIRED'?'هذا الرابط منتهي أو سبق استخدامه. اطلب رابطًا جديدًا من صفحة الحساب.':reset?'تعذر تغيير كلمة المرور؛ استخدم 8 أحرف على الأقل وتحقق من صلاحية الرابط.':'تعذر تفعيل البريد بسبب خطأ في الطلب. اطلب رابطًا جديدًا.';
    }catch(e){status.textContent='تعذر الاتصال بالخادم. تحقق من الشبكة وحاول مجددًا.';}finally{if(!button.hidden)button.disabled=false;}};
    </script></html>""",
        headers={
            "Cache-Control": "no-store",
            "Referrer-Policy": "no-referrer",
            "X-Frame-Options": "DENY",
            "Content-Security-Policy": "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'",
        },
    )


@router.get("/me")
def me(owner=Depends(guardian)):
    return owner


@router.delete("/session")
def logout(request: Request, response: Response, owner=Depends(guardian), database=Depends(store)):
    with database.transaction() as db:
        db.execute(
            "DELETE FROM guardian_sessions WHERE token_hash=?",
            (digest(token(request, "guardian")),),
        )
    response.delete_cookie("iqtadi_guardian", path=COOKIE_PATH)
    response.delete_cookie("iqtadi_device", path=COOKIE_PATH)
    return {"disconnected": True}


class Body(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class Schedule(Body):
    from_date: date = Field(alias="from")
    until: date
    fajr: str = Field(pattern=r"^\d{2}:\d{2}$")
    sunrise: str = Field(pattern=r"^\d{2}:\d{2}$")
    dhuhr: str = Field(pattern=r"^\d{2}:\d{2}$")
    asr: str = Field(pattern=r"^\d{2}:\d{2}$")
    maghrib: str = Field(pattern=r"^\d{2}:\d{2}$")
    isha: str = Field(pattern=r"^\d{2}:\d{2}$")

    @model_validator(mode="after")
    def check(self):
        from datetime import time as clock_time

        clocks = [
            clock_time.fromisoformat(getattr(self, key))
            for key in ("fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha")
        ]
        if clocks != sorted(set(clocks)) or not 0 <= (self.until - self.from_date).days <= 31:
            raise ValueError("Ordered times and maximum 32-day range required")
        return self


class GroupBody(Body):
    name: str = Field(min_length=1, max_length=100)
    timezone: str = "Africa/Cairo"
    schedule: Schedule | None = None

    @model_validator(mode="after")
    def check(self):
        try:
            ZoneInfo(self.timezone)
        except (ZoneInfoNotFoundError, ValueError):
            raise ValueError("Unknown timezone") from None
        return self


def group_values(body):
    return (
        body.name,
        body.timezone,
        json.dumps(body.schedule.model_dump(mode="json", by_alias=True) if body.schedule else {}),
    )


@router.post("/groups")
def add_group(body: GroupBody, owner=Depends(guardian), database=Depends(store)):
    key = str(uuid.uuid4())
    with database.transaction() as db:
        name, tz, schedule = group_values(body)
        db.execute(
            "INSERT INTO groups VALUES(?,?,?,?,?,?,?)",
            (
                key,
                owner["id"],
                name,
                "FAMILY",
                tz,
                schedule,
                datetime.now(timezone.utc).isoformat(),
            ),
        )
        db.execute(
            "INSERT OR IGNORE INTO family_memberships VALUES(?,?,?,?)",
            (key, owner["id"], "OWNER", datetime.now(timezone.utc).isoformat()),
        )
    return {"id": key}


@router.get("/groups")
def groups(owner=Depends(guardian), database=Depends(store)):
    with database.transaction() as db:
        return [
            dict(r) | {"schedule": json.loads(r["schedule"])}
            for r in db.execute(
                """SELECT * FROM groups WHERE owner_user_id=? AND type<>'PERSONAL'
                   ORDER BY created_at""",
                (owner["id"],),
            )
        ]


@router.put("/groups/{group_id}")
def edit_group(group_id: str, body: GroupBody, owner=Depends(guardian), database=Depends(store)):
    with database.transaction() as db:
        owned_group(db, group_id, owner)
        db.execute(
            "UPDATE groups SET name=?,timezone=?,schedule=? WHERE id=?",
            (*group_values(body), group_id),
        )
        timing = PrayerTimeService(
            body.timezone,
            body.schedule.model_dump(mode="json", by_alias=True) if body.schedule else {},
        )
        for row in db.execute(
            "SELECT a.* FROM attempts a JOIN children c ON c.id=a.child_id WHERE c.group_id=?",
            (group_id,),
        ).fetchall():
            db.execute(
                "UPDATE attempts SET on_time=? WHERE id=?",
                (
                    timing.on_time(datetime.fromisoformat(row["performed_at"]), row["prayer"]),
                    row["id"],
                ),
            )
    return {"updated": True}


class ChildBody(Body):
    name: str = Field(min_length=1, max_length=80)
    age: int = Field(ge=3, le=25)
    avatar: str | None = Field(default=None, max_length=8)
    active: bool = True


@router.post("/groups/{group_id}/children")
def add_child(group_id: str, body: ChildBody, owner=Depends(guardian), database=Depends(store)):
    key = str(uuid.uuid4())
    with database.transaction() as db:
        owned_group(db, group_id, owner)
        created_at = datetime.now(timezone.utc).isoformat()
        db.execute(
            """INSERT INTO children
               (id,group_id,name,age,avatar,active,created_at,profile_kind,
                account_user_id,age_band,alias)
               VALUES(?,?,?,?,?,?,?,?,?,?,?)""",
            (
                key,
                group_id,
                body.name,
                body.age,
                body.avatar,
                body.active,
                created_at,
                "DEPENDENT",
                None,
                "CHILD",
                None,
            ),
        )
        db.execute(
            "INSERT OR IGNORE INTO guardian_links VALUES(?,?,?,?)",
            (owner["id"], key, "OWNER", created_at),
        )
    return {"id": key}


@router.put("/children/{child_id}")
def edit_child(child_id: str, body: ChildBody, owner=Depends(guardian), database=Depends(store)):
    with database.transaction() as db:
        owned_child(db, child_id, owner)
        db.execute(
            "UPDATE children SET name=?,age=?,avatar=?,active=? WHERE id=?",
            (body.name, body.age, body.avatar, body.active, child_id),
        )
        if not body.active:
            db.execute("UPDATE devices SET revoked_at=? WHERE child_id=?", (time.time(), child_id))
            db.execute("UPDATE pairing_tokens SET revoked=1 WHERE child_id=?", (child_id,))
    return {"updated": True}


@router.post("/children/{child_id}/pairing")
def pairing(child_id: str, request: Request, owner=Depends(guardian), database=Depends(store)):
    raw = secrets.token_urlsafe(32)
    code = "".join(secrets.choice("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") for _ in range(10))
    expires = time.time() + 300
    with database.transaction() as db:
        limited(request, db, "pairing-create", 30)
        child = owned_child(db, child_id, owner)
        if not child["active"]:
            raise HTTPException(409, "CHILD_INACTIVE")
        db.execute(
            "UPDATE pairing_tokens SET revoked=1 WHERE child_id=? AND used_at IS NULL", (child_id,)
        )
        db.execute(
            "INSERT INTO pairing_tokens VALUES(?,?,?,?,?,?,?,0)",
            (str(uuid.uuid4()), child_id, digest(raw), digest(code), expires, None, owner["id"]),
        )
    return {
        "qr_payload": "iqtadi-pair:" + raw,
        "qr_url": get_settings().account_public_url.rstrip("/")
        + COOKIE_PATH
        + "/pairing/open#pair="
        + quote(raw, safe=""),
        "code": code,
        "expires_at": datetime.fromtimestamp(expires, timezone.utc).isoformat(),
    }


class RedeemBody(Body):
    token: str = Field(min_length=8, max_length=200)
    platform: str = Field(pattern="^(android|web|ios|other)$")


@router.get("/pairing/open", response_class=HTMLResponse)
def open_pairing_link():
    """Bypass an older offline shell before handing the fragment to Flutter."""

    return HTMLResponse(
        """<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Iqtadi</title></head><body><script>
(async()=>{
  const target='/' + location.hash;
  if ('serviceWorker' in navigator) {
    const registrations=await navigator.serviceWorker.getRegistrations();
    await Promise.all(registrations.map(registration=>registration.unregister()));
  }
  location.replace(target);
})().catch(()=>location.replace('/' + location.hash));
</script></body></html>""",
        headers={"Cache-Control": "no-store", "Referrer-Policy": "no-referrer"},
    )


@router.post("/pairing/redeem", dependencies=[Depends(boundary)])
def redeem(body: RedeemBody, request: Request, response: Response, database=Depends(store)):
    raw, key = secrets.token_urlsafe(32), str(uuid.uuid4())
    value = body.token.removeprefix("iqtadi-pair:")
    now = time.time()
    with database.transaction() as db:
        limited(request, db, "redeem", 10)
    with database.transaction() as db:
        pair = db.execute(
            "SELECT p.*,c.name,c.active FROM pairing_tokens p JOIN children c ON c.id=p.child_id WHERE p.token_hash=? OR p.code_hash=?",
            (digest(value), digest(value.upper().replace(" ", "").replace("-", ""))),
        ).fetchone()
        if (
            not pair
            or pair["used_at"]
            or pair["revoked"]
            or pair["expires_at"] <= now
            or not pair["active"]
        ):
            raise HTTPException(400, "PAIRING_INVALID_OR_EXPIRED")
        db.execute("UPDATE pairing_tokens SET used_at=? WHERE id=?", (now, pair["id"]))
        db.execute(
            "INSERT INTO devices VALUES(?,?,?,?,?,?,?,NULL)",
            (
                key,
                pair["child_id"],
                digest(raw),
                body.platform,
                now,
                now,
                now + DEVICE_SESSION_SECONDS,
            ),
        )
    return session_response(
        request,
        response,
        "device",
        raw,
        DEVICE_SESSION_SECONDS,
        {
            "device_id": key,
            "child_id": pair["child_id"],
            "name": pair["name"],
            "profile_kind": "DEPENDENT",
        },
    )


@router.get("/device")
def device_me(child=Depends(device)):
    return {
        k: child[k]
        for k in ("id", "child_id", "name", "profile_kind", "expires_at")
    }


@router.get("/device/progress")
def device_progress(child=Depends(device), database=Depends(store)):
    """The paired learner may read only their own scalar practice summary."""

    with database.transaction() as db:
        profile = db.execute(
            "SELECT c.*,g.name group_name,g.timezone,g.schedule FROM children c JOIN groups g ON g.id=c.group_id WHERE c.id=?",
            (child["child_id"],),
        ).fetchone()
        if not profile:
            raise HTTPException(404, "PROFILE_NOT_FOUND")
        timing = PrayerTimeService(profile["timezone"], json.loads(profile["schedule"]))
        today = datetime.now(timing.tz).date()
        attempts = [
            dict(row)
            for row in db.execute(
                "SELECT * FROM attempts WHERE child_id=?", (child["child_id"],)
            )
        ]
        summary = progress(attempts, timing, today)
        rankings = []
        memberships = db.execute(
            """SELECT mg.id group_id,mg.name group_name,m.name mosque_name,
                      gm.alias,gc.leaderboard,gc.share_practice,gc.share_attendance,
                      mg.timezone,mg.schedule
               FROM group_memberships gm JOIN mosque_groups mg ON mg.id=gm.group_id
               JOIN mosques m ON m.id=mg.mosque_id
               JOIN guardian_consents gc ON gc.group_id=gm.group_id
                 AND gc.child_id=gm.child_id AND gc.revoked_at IS NULL
               WHERE gm.child_id=? AND gm.status='ACTIVE'""",
            (child["child_id"],),
        ).fetchall()
        for membership in memberships:
            item = {
                "group_id": membership["group_id"],
                "group_name": membership["group_name"],
                "mosque_name": membership["mosque_name"],
                "alias": membership["alias"],
                "leaderboard_enabled": bool(membership["leaderboard"]),
            }
            if membership["leaderboard"] and membership["share_practice"]:
                group_timing = PrayerTimeService(
                    membership["timezone"], json.loads(membership["schedule"])
                )
                members = db.execute(
                    """SELECT gm.child_id,gm.alias FROM group_memberships gm
                       JOIN guardian_consents gc ON gc.group_id=gm.group_id
                         AND gc.child_id=gm.child_id AND gc.revoked_at IS NULL
                       WHERE gm.group_id=? AND gm.status='ACTIVE'
                         AND gc.leaderboard=1 AND gc.share_practice=1""",
                    (membership["group_id"],),
                ).fetchall()
                board = []
                for member in members:
                    member_attempts = [
                        dict(row)
                        for row in db.execute(
                            "SELECT * FROM attempts WHERE child_id=?", (member["child_id"],)
                        )
                    ]
                    member_summary = progress(member_attempts, group_timing, today)
                    board.append(
                        (member["child_id"], member_summary["weekly_points"])
                    )
                board.sort(key=lambda row: (-row[1], row[0]))
                position = next(
                    (index + 1 for index, row in enumerate(board) if row[0] == child["child_id"]),
                    None,
                )
                item.update(
                    {
                        "practice_position": position,
                        "participants": len(board),
                        "weekly_points": summary["weekly_points"],
                    }
                )
            rankings.append(item)
        return {
            "child_id": child["child_id"],
            "name": profile["name"],
            **{
                key: summary[key]
                for key in (
                    "movement_results", "movements_detected", "movements_expected",
                    "movement_score", "weekly_movements_detected",
                    "weekly_movements_expected", "weekly_movement_score", "week",
                )
            },
            "date": summary["date"],
            "points": summary["points"],
            "valid_prayers": summary["valid_prayers"],
            "weekly_points": summary["weekly_points"],
            "weekly_valid_prayers": summary["weekly_valid_prayers"],
            "streak": summary["streak"],
            "states": summary["states"],
            "group_rankings": rankings,
        }


@router.delete("/device")
def disconnect(response: Response, child=Depends(device), database=Depends(store)):
    with database.transaction() as db:
        db.execute("UPDATE devices SET revoked_at=? WHERE id=?", (time.time(), child["id"]))
    response.delete_cookie("iqtadi_device", path=COOKIE_PATH)
    return {"disconnected": True}


@router.get("/children/{child_id}/devices")
def devices(child_id: str, owner=Depends(guardian), database=Depends(store)):
    with database.transaction() as db:
        owned_child(db, child_id, owner)
        return [
            dict(r)
            for r in db.execute(
                "SELECT id,platform,created_at,last_seen_at,revoked_at,expires_at FROM devices WHERE child_id=?",
                (child_id,),
            )
        ]


@router.delete("/children/{child_id}/devices/{device_id}")
def revoke(child_id: str, device_id: str, owner=Depends(guardian), database=Depends(store)):
    with database.transaction() as db:
        owned_child(db, child_id, owner)
        db.execute(
            "UPDATE devices SET revoked_at=? WHERE id=? AND child_id=?",
            (time.time(), device_id, child_id),
        )
    return {"revoked": True}


class AttemptBody(Body):
    client_attempt_id: str = Field(min_length=1, max_length=100, pattern=r"^[A-Za-z0-9_-]+$")
    prayer: str = Field(pattern="^(fajr|dhuhr|asr|maghrib|isha)$")
    performed_at: datetime
    valid: bool
    sequence_valid: bool
    uncertain: bool
    confidence: float | None = Field(default=None, ge=0, le=1, allow_inf_nan=False)
    rakats_expected: int = Field(ge=2, le=4)
    rakats_completed: int = Field(ge=0, le=4)
    analysis_version: str = Field(min_length=1, max_length=100)
    movements_detected: int | None = Field(default=None, ge=0, strict=True)
    movements_expected: int | None = Field(default=None, gt=0, strict=True)
    movement_score: float | None = Field(default=None, ge=0, le=100, allow_inf_nan=False)

    @model_validator(mode="after")
    def check(self):
        if self.performed_at.tzinfo is None or self.performed_at > datetime.now(
            timezone.utc
        ) + timedelta(minutes=5):
            raise ValueError("Timezone-aware non-future performed_at required")
        if (
            self.rakats_expected != RAKATS[self.prayer]
            or self.rakats_completed > self.rakats_expected
        ):
            raise ValueError("Invalid rakah counts")
        if self.valid and (
            self.uncertain
            or not self.sequence_valid
            or self.rakats_completed != self.rakats_expected
        ):
            raise ValueError("Inconsistent final result")
        values = (self.movements_detected, self.movements_expected, self.movement_score)
        if any(v is not None for v in values):
            if any(v is None for v in values):
                raise ValueError("All movement score fields are required together")
            expected = sum(len(row) for row in stations(self.prayer))
            if self.movements_expected != expected or self.movements_detected > expected:
                raise ValueError("Invalid movement counts")
            if self.valid and self.movements_detected != expected:
                raise ValueError("Observed completion requires all expected movements")
            score = round(100 * self.movements_detected / expected, 2)
            if abs(self.movement_score - score) > 0.000001:
                raise ValueError("Movement score must match detected / expected counts")
            self.movement_score = score
        return self


@router.post("/attempts")
def attempt(body: AttemptBody, child=Depends(device), database=Depends(store)):
    with database.transaction() as db:
        # Revocation and insertion share the same serialized transaction.
        if not db.execute(
            "SELECT d.id FROM devices d JOIN children c ON c.id=d.child_id WHERE d.id=? AND d.revoked_at IS NULL AND d.expires_at>? AND c.active=1",
            (child["id"], time.time()),
        ).fetchone():
            raise HTTPException(401, "DEVICE_DISCONNECTED")
        old = db.execute(
            "SELECT * FROM attempts WHERE child_id=? AND client_attempt_id=?",
            (child["child_id"], body.client_attempt_id),
        ).fetchone()
        if old:
            return {"id": old["id"], "duplicate": True}
        group = db.execute(
            "SELECT g.* FROM groups g JOIN children c ON c.group_id=g.id WHERE c.id=?",
            (child["child_id"],),
        ).fetchone()
        timing = PrayerTimeService(group["timezone"], json.loads(group["schedule"]))
        key = str(uuid.uuid4())
        db.execute(
            "INSERT INTO attempts (id,child_id,client_attempt_id,prayer,performed_at,valid,sequence_valid,uncertain,on_time,confidence,rakats_expected,rakats_completed,analysis_version,created_at,movements_detected,movements_expected,movement_score) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (
                key,
                child["child_id"],
                body.client_attempt_id,
                body.prayer,
                body.performed_at.astimezone(timezone.utc).isoformat(),
                body.valid,
                body.sequence_valid,
                body.uncertain,
                timing.on_time(body.performed_at, body.prayer),
                body.confidence,
                body.rakats_expected,
                body.rakats_completed,
                body.analysis_version,
                datetime.now(timezone.utc).isoformat(),
                body.movements_detected,
                body.movements_expected,
                body.movement_score,
            ),
        )
    return {"id": key, "duplicate": False}


@router.get("/groups/{group_id}/progress")
def dashboard(
    group_id: str, day: date | None = None, owner=Depends(guardian), database=Depends(store)
):
    with database.transaction() as db:
        group = owned_group(db, group_id, owner)
        timing = PrayerTimeService(group["timezone"], json.loads(group["schedule"]))
        today = day or datetime.now(timing.tz).date()
        children = []
        for row in db.execute(
            "SELECT * FROM children WHERE group_id=? AND active=1 ORDER BY created_at", (group_id,)
        ).fetchall():
            attempts = [
                dict(r) for r in db.execute("SELECT * FROM attempts WHERE child_id=?", (row["id"],))
            ]
            children.append(dict(row) | progress(attempts, timing, today))
        board = sorted(
            children,
            key=lambda c: (
                -c["weekly_points"],
                -(c["weekly_movement_score"] if c["weekly_movement_score"] is not None else -1),
                -c["weekly_on_time_prayers"],
                c["name"],
                c["id"],
            ),
        )
        return {
            "date": today.isoformat(),
            "group": group | {"schedule": json.loads(group["schedule"])},
            "children": children,
            "leaderboard": board,
            "notice": "متابعة ترتيب الحركات المرصودة؛ التحليل محلي والنتائج النهائية فقط تصل للخادم.",
        }
