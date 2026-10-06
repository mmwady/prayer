"""Unified account spaces: personal practice, family and verified mosque groups.

Prayer inference remains on-device.  This router accepts only relationships,
consent, scalar practice summaries through the existing attempts endpoint, and
explicit mosque attendance events.
"""

import json
import secrets
import time
import uuid
from datetime import date, datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field

from .api import Schedule, boundary, device, group_values, guardian, limited, store
from .domain import PrayerTimeService, progress
from .store import digest, ensure_personal_profile

router = APIRouter(prefix="/api/v1/accounts", tags=["account spaces"])


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def code(length: int = 10) -> str:
    return "".join(secrets.choice("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") for _ in range(length))


def audit(db, actor: str | None, action: str, subject: str | None, context: str | None):
    db.execute(
        "INSERT INTO account_audit_events VALUES(?,?,?,?,?,?)",
        (str(uuid.uuid4()), actor, action, subject, context, now_iso()),
    )


def family_membership(db, family_id: str, account, roles=None):
    row = db.execute(
        """SELECT fm.*,g.name,g.type,g.timezone,g.schedule,g.created_at
           FROM family_memberships fm JOIN groups g ON g.id=fm.family_id
           WHERE fm.family_id=? AND fm.user_id=? AND g.type='FAMILY'""",
        (family_id, account["id"]),
    ).fetchone()
    if not row or (roles and row["role"] not in roles):
        raise HTTPException(404, "FAMILY_NOT_FOUND")
    return dict(row)


def controlled_profile(db, profile_id: str, account):
    row = db.execute(
        """SELECT DISTINCT c.* FROM children c
           LEFT JOIN guardian_links gl ON gl.child_id=c.id
           WHERE c.id=? AND c.active=1 AND
             (c.account_user_id=? OR gl.user_id=?)""",
        (profile_id, account["id"], account["id"]),
    ).fetchone()
    if not row:
        raise HTTPException(404, "PROFILE_NOT_FOUND")
    return dict(row)


def mosque_staff(db, mosque_id: str, account, roles=("ADMIN", "LEADER")):
    row = db.execute(
        "SELECT * FROM mosque_staff WHERE mosque_id=? AND user_id=?",
        (mosque_id, account["id"]),
    ).fetchone()
    if not row or row["role"] not in roles:
        raise HTTPException(404, "MOSQUE_ROLE_REQUIRED")
    return dict(row)


def platform_admin(db, account):
    row = db.execute(
        "SELECT 1 FROM platform_admins WHERE user_id=?", (account["id"],)
    ).fetchone()
    if not row:
        raise HTTPException(403, "PLATFORM_ADMIN_REQUIRED")
    return True


def led_group(db, group_id: str, account):
    row = db.execute(
        """SELECT mg.*,m.name mosque_name,m.city FROM mosque_groups mg
           JOIN mosques m ON m.id=mg.mosque_id
           JOIN mosque_staff ms ON ms.mosque_id=mg.mosque_id
           WHERE mg.id=? AND mg.active=1 AND ms.user_id=?
             AND ms.role IN ('ADMIN','LEADER')""",
        (group_id, account["id"]),
    ).fetchone()
    if not row:
        raise HTTPException(404, "MOSQUE_GROUP_NOT_FOUND")
    return dict(row)


def group_visible(db, group_id: str, account):
    try:
        return led_group(db, group_id, account), True
    except HTTPException:
        row = db.execute(
            """SELECT DISTINCT mg.*,m.name mosque_name,m.city
               FROM mosque_groups mg JOIN mosques m ON m.id=mg.mosque_id
               JOIN group_memberships gm ON gm.group_id=mg.id AND gm.status='ACTIVE'
               LEFT JOIN guardian_links gl ON gl.child_id=gm.child_id
               LEFT JOIN children c ON c.id=gm.child_id
               WHERE mg.id=? AND (gl.user_id=? OR c.account_user_id=?)""",
            (group_id, account["id"], account["id"]),
        ).fetchone()
        if not row:
            raise HTTPException(404, "MOSQUE_GROUP_NOT_FOUND")
        return dict(row), False


def adult_group_member(db, group_id: str, account):
    row = db.execute(
        """SELECT mg.id group_id,mg.name group_name,mg.age_band,
                  gm.child_id profile_id,gm.alias
           FROM mosque_groups mg JOIN group_memberships gm ON gm.group_id=mg.id
           JOIN children c ON c.id=gm.child_id
           WHERE mg.id=? AND mg.active=1 AND mg.age_band='ADULT'
             AND gm.status='ACTIVE' AND c.profile_kind='SELF'
             AND c.account_user_id=?""",
        (group_id, account["id"]),
    ).fetchone()
    if not row:
        raise HTTPException(403, "ADULT_GROUP_MEMBERSHIP_REQUIRED")
    return dict(row)


class Body(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class PreferencesBody(Body):
    learning_stage: str = Field(pattern="^(GENERAL|NEW_MUSLIM)$")
    accessibility_mode: str = Field(pattern="^(STANDARD|SIMPLE|LARGE_TEXT)$")


@router.get("/overview")
def overview(account=Depends(guardian), database=Depends(store)):
    with database.transaction() as db:
        profile_id = ensure_personal_profile(db, account["id"], account["name"], now_iso())
        profile = dict(db.execute("SELECT * FROM children WHERE id=?", (profile_id,)).fetchone())
        families = [
            dict(row)
            for row in db.execute(
                """SELECT g.id,g.name,g.timezone,fm.role,
                          (SELECT count(*) FROM children c
                           WHERE c.group_id=g.id AND c.profile_kind='DEPENDENT' AND c.active=1)
                          dependent_count
                   FROM family_memberships fm JOIN groups g ON g.id=fm.family_id
                   WHERE fm.user_id=? AND g.type='FAMILY' ORDER BY g.created_at""",
                (account["id"],),
            )
        ]
        staff = [
            dict(row)
            for row in db.execute(
                """SELECT m.id mosque_id,m.name mosque_name,m.city,ms.role
                   FROM mosque_staff ms JOIN mosques m ON m.id=ms.mosque_id
                   WHERE ms.user_id=? ORDER BY m.name""",
                (account["id"],),
            )
        ]
        joined = [
            dict(row)
            for row in db.execute(
                """SELECT DISTINCT mg.id group_id,mg.name group_name,m.name mosque_name,
                          gm.alias,gm.child_id profile_id,gm.status,c.profile_kind,
                          CASE WHEN c.profile_kind='SELF' THEN 'SELF' ELSE 'CHILD' END join_kind
                   FROM group_memberships gm JOIN mosque_groups mg ON mg.id=gm.group_id
                   JOIN mosques m ON m.id=mg.mosque_id
                   LEFT JOIN guardian_links gl ON gl.child_id=gm.child_id
                   LEFT JOIN children c ON c.id=gm.child_id
                   WHERE gm.status IN ('ACTIVE','PENDING')
                     AND (gl.user_id=? OR c.account_user_id=?)
                   ORDER BY m.name,mg.name""",
                (account["id"], account["id"]),
            )
        ]
        return {
            "account": account,
            "practice_profile": {
                "id": profile["id"],
                "name": profile["name"],
                "kind": profile["profile_kind"],
            },
            "families": families,
            "mosque_roles": staff,
            "joined_groups": joined,
            "is_platform_admin": bool(
                db.execute(
                    "SELECT 1 FROM platform_admins WHERE user_id=?", (account["id"],)
                ).fetchone()
            ),
            "leader_requests": [
                dict(row)
                for row in db.execute(
                    """SELECT id,mosque_id,mosque_name,city,requested_role,status,note,
                              created_at,reviewed_at
                       FROM mosque_leader_requests WHERE user_id=? ORDER BY created_at DESC""",
                    (account["id"],),
                )
            ],
        }


@router.put("/preferences")
def preferences(body: PreferencesBody, account=Depends(guardian), database=Depends(store)):
    with database.transaction() as db:
        db.execute(
            "UPDATE guardians SET learning_stage=?,accessibility_mode=? WHERE id=?",
            (body.learning_stage, body.accessibility_mode, account["id"]),
        )
        audit(db, account["id"], "ACCOUNT_PREFERENCES_UPDATED", account["id"], None)
    return {"updated": True}


class FamilyBody(Body):
    name: str = Field(min_length=1, max_length=100)
    timezone: str = "Asia/Riyadh"
    schedule: Schedule | None = None


@router.get("/families")
def families(account=Depends(guardian), database=Depends(store)):
    with database.transaction() as db:
        return [
            dict(row) | {"schedule": json.loads(row["schedule"])}
            for row in db.execute(
                """SELECT g.*,fm.role FROM family_memberships fm
                   JOIN groups g ON g.id=fm.family_id
                   WHERE fm.user_id=? AND g.type='FAMILY' ORDER BY g.created_at""",
                (account["id"],),
            )
        ]


@router.post("/families")
def create_family(body: FamilyBody, account=Depends(guardian), database=Depends(store)):
    family_id = str(uuid.uuid4())
    created_at = now_iso()
    with database.transaction() as db:
        name, tz, schedule = group_values(body)
        db.execute(
            """INSERT INTO groups(id,owner_user_id,name,type,timezone,schedule,created_at)
               VALUES(?,?,?,?,?,?,?)""",
            (family_id, account["id"], name, "FAMILY", tz, schedule, created_at),
        )
        db.execute(
            "INSERT INTO family_memberships VALUES(?,?,?,?)",
            (family_id, account["id"], "OWNER", created_at),
        )
        audit(db, account["id"], "FAMILY_CREATED", family_id, family_id)
    return {"id": family_id}


class DependentBody(Body):
    name: str = Field(min_length=1, max_length=80)
    age_band: str = Field(pattern="^(CHILD_5_9|CHILD_10_13|TEEN_14_17)$")
    alias: str | None = Field(default=None, min_length=2, max_length=40)


AGES = {"CHILD_5_9": 7, "CHILD_10_13": 11, "TEEN_14_17": 15}


@router.post("/families/{family_id}/dependents")
def add_dependent(
    family_id: str,
    body: DependentBody,
    account=Depends(guardian),
    database=Depends(store),
):
    profile_id = str(uuid.uuid4())
    created_at = now_iso()
    with database.transaction() as db:
        family_membership(db, family_id, account, ("OWNER", "GUARDIAN"))
        db.execute(
            """INSERT INTO children
               (id,group_id,name,age,avatar,active,created_at,profile_kind,
                account_user_id,age_band,alias)
               VALUES(?,?,?,?,?,?,?,?,?,?,?)""",
            (
                profile_id,
                family_id,
                body.name,
                AGES[body.age_band],
                None,
                1,
                created_at,
                "DEPENDENT",
                None,
                body.age_band,
                body.alias,
            ),
        )
        guardians = db.execute(
            """SELECT user_id,role FROM family_memberships
               WHERE family_id=? AND role IN ('OWNER','GUARDIAN')""",
            (family_id,),
        ).fetchall()
        for member in guardians:
            db.execute(
                "INSERT OR IGNORE INTO guardian_links VALUES(?,?,?,?)",
                (
                    member["user_id"],
                    profile_id,
                    "OWNER" if member["role"] == "OWNER" else "GUARDIAN",
                    created_at,
                ),
            )
        audit(db, account["id"], "DEPENDENT_CREATED", profile_id, family_id)
    return {"id": profile_id}


@router.get("/families/{family_id}")
def family_detail(family_id: str, account=Depends(guardian), database=Depends(store)):
    with database.transaction() as db:
        family = family_membership(db, family_id, account)
        members = [
            dict(row)
            for row in db.execute(
                """SELECT g.id,g.name,fm.role FROM family_memberships fm
                   JOIN guardians g ON g.id=fm.user_id
                   WHERE fm.family_id=? ORDER BY fm.created_at""",
                (family_id,),
            )
        ]
        dependents = [
            dict(row)
            for row in db.execute(
                """SELECT id,name,age_band,alias,active,created_at FROM children
                   WHERE group_id=? AND profile_kind='DEPENDENT' ORDER BY created_at""",
                (family_id,),
            )
        ]
        return {
            "family": family | {"schedule": json.loads(family["schedule"])},
            "members": members,
            "dependents": dependents,
        }


class FamilyMemberRoleBody(Body):
    role: str = Field(pattern="^(GUARDIAN|ADULT|SUPPORTER)$")


@router.put("/families/{family_id}/members/{user_id}")
def update_family_member(
    family_id: str,
    user_id: str,
    body: FamilyMemberRoleBody,
    account=Depends(guardian),
    database=Depends(store),
):
    with database.transaction() as db:
        family_membership(db, family_id, account, ("OWNER",))
        current = db.execute(
            "SELECT role FROM family_memberships WHERE family_id=? AND user_id=?",
            (family_id, user_id),
        ).fetchone()
        if not current or current["role"] == "OWNER":
            raise HTTPException(400, "OWNER_ROLE_CANNOT_BE_CHANGED")
        db.execute(
            "UPDATE family_memberships SET role=? WHERE family_id=? AND user_id=?",
            (body.role, family_id, user_id),
        )
        if body.role == "GUARDIAN":
            db.execute(
                """INSERT OR IGNORE INTO guardian_links(user_id,child_id,authority,created_at)
                   SELECT ?,id,'GUARDIAN',? FROM children
                   WHERE group_id=? AND profile_kind='DEPENDENT'""",
                (user_id, now_iso(), family_id),
            )
        else:
            db.execute(
                "DELETE FROM guardian_links WHERE user_id=? AND child_id IN (SELECT id FROM children WHERE group_id=?)",
                (user_id, family_id),
            )
        audit(db, account["id"], "FAMILY_MEMBER_ROLE_UPDATED", user_id, family_id)
    return {"updated": True, "role": body.role}


@router.delete("/families/{family_id}/members/{user_id}")
def remove_family_member(
    family_id: str,
    user_id: str,
    account=Depends(guardian),
    database=Depends(store),
):
    with database.transaction() as db:
        family_membership(db, family_id, account, ("OWNER",))
        current = db.execute(
            "SELECT role FROM family_memberships WHERE family_id=? AND user_id=?",
            (family_id, user_id),
        ).fetchone()
        if not current or current["role"] == "OWNER":
            raise HTTPException(400, "OWNER_CANNOT_BE_REMOVED")
        db.execute(
            "DELETE FROM guardian_links WHERE user_id=? AND child_id IN (SELECT id FROM children WHERE group_id=?)",
            (user_id, family_id),
        )
        db.execute(
            "DELETE FROM family_memberships WHERE family_id=? AND user_id=?",
            (family_id, user_id),
        )
        audit(db, account["id"], "FAMILY_MEMBER_REMOVED", user_id, family_id)
    return {"removed": True}


class FamilyInviteBody(Body):
    role: str = Field(pattern="^(GUARDIAN|ADULT|SUPPORTER)$")


@router.post("/families/{family_id}/invites")
def family_invite(
    family_id: str,
    body: FamilyInviteBody,
    request: Request,
    account=Depends(guardian),
    database=Depends(store),
):
    raw, manual = secrets.token_urlsafe(32), code()
    expires = time.time() + 7 * 86400
    with database.transaction() as db:
        limited(request, db, "family-invite", 30)
        family_membership(db, family_id, account, ("OWNER",))
        db.execute(
            "INSERT INTO family_invites VALUES(?,?,?,?,?,?,?,?,?,0)",
            (
                str(uuid.uuid4()),
                family_id,
                body.role,
                digest(raw),
                digest(manual),
                expires,
                account["id"],
                None,
                None,
            ),
        )
    return {
        "qr_payload": "iqtadi-family:" + raw,
        "code": manual,
        "expires_at": datetime.fromtimestamp(expires, timezone.utc).isoformat(),
    }


class TokenBody(Body):
    token: str = Field(min_length=8, max_length=240)


@router.post("/family-invitations/redeem")
def redeem_family_invite(body: TokenBody, account=Depends(guardian), database=Depends(store)):
    value = body.token.removeprefix("iqtadi-family:")
    normalized = value.upper().replace(" ", "").replace("-", "")
    with database.transaction() as db:
        invite = db.execute(
            """SELECT * FROM family_invites WHERE
               (token_hash=? OR code_hash=?) AND expires_at>? AND used_at IS NULL AND revoked=0""",
            (digest(value), digest(normalized), time.time()),
        ).fetchone()
        if not invite:
            raise HTTPException(400, "INVITATION_INVALID_OR_EXPIRED")
        created_at = now_iso()
        db.execute(
            "INSERT OR REPLACE INTO family_memberships VALUES(?,?,?,?)",
            (invite["family_id"], account["id"], invite["role"], created_at),
        )
        if invite["role"] == "GUARDIAN":
            for child in db.execute(
                """SELECT id FROM children WHERE group_id=? AND profile_kind='DEPENDENT'""",
                (invite["family_id"],),
            ).fetchall():
                db.execute(
                    "INSERT OR IGNORE INTO guardian_links VALUES(?,?,?,?)",
                    (account["id"], child["id"], "GUARDIAN", created_at),
                )
        db.execute(
            "UPDATE family_invites SET used_by=?,used_at=? WHERE id=?",
            (account["id"], time.time(), invite["id"]),
        )
        audit(db, account["id"], "FAMILY_INVITE_REDEEMED", account["id"], invite["family_id"])
    return {"family_id": invite["family_id"], "role": invite["role"]}


def family_profiles(db, family_id: str):
    rows = db.execute(
        """SELECT c.* FROM children c
           WHERE c.group_id=? AND c.profile_kind='DEPENDENT' AND c.active=1
           UNION
           SELECT c.* FROM family_memberships fm
           JOIN children c ON c.account_user_id=fm.user_id AND c.profile_kind='SELF'
           WHERE fm.family_id=? AND c.active=1""",
        (family_id, family_id),
    ).fetchall()
    return [dict(row) for row in rows]


@router.get("/families/{family_id}/progress")
def family_progress(family_id: str, account=Depends(guardian), database=Depends(store)):
    with database.transaction() as db:
        family = family_membership(db, family_id, account)
        timing = PrayerTimeService(family["timezone"], json.loads(family["schedule"]))
        today = datetime.now(timing.tz).date()
        profiles = []
        for profile in family_profiles(db, family_id):
            attempts = [
                dict(row)
                for row in db.execute("SELECT * FROM attempts WHERE child_id=?", (profile["id"],))
            ]
            item = profile | progress(attempts, timing, today)
            if family["role"] == "SUPPORTER":
                item["name"] = profile["alias"] or "عضو الأسرة"
            profiles.append(item)
        board = sorted(
            profiles,
            key=lambda p: (
                -p["weekly_points"],
                -(p["weekly_movement_score"] if p["weekly_movement_score"] is not None else -1),
                p["name"],
                p["id"],
            ),
        )
        return {
            "family": {"id": family_id, "name": family["name"], "role": family["role"]},
            "profiles": profiles,
            "leaderboard": board,
        }


class LeaderRequestBody(Body):
    mosque_id: str | None = None
    mosque_name: str = Field(min_length=2, max_length=120)
    city: str = Field(min_length=2, max_length=80)
    requested_role: str = Field(default="LEADER", pattern="^(ADMIN|LEADER)$")
    note: str | None = Field(default=None, max_length=500)


@router.post("/mosque-leader-requests")
def request_mosque_leadership(
    body: LeaderRequestBody,
    account=Depends(guardian),
    database=Depends(store),
):
    request_id = str(uuid.uuid4())
    with database.transaction() as db:
        if body.mosque_id and not db.execute(
            "SELECT 1 FROM mosques WHERE id=? AND verified=1", (body.mosque_id,)
        ).fetchone():
            raise HTTPException(404, "MOSQUE_NOT_FOUND")
        if db.execute(
            "SELECT 1 FROM mosque_leader_requests WHERE user_id=? AND status='PENDING'",
            (account["id"],),
        ).fetchone():
            raise HTTPException(409, "LEADER_REQUEST_ALREADY_PENDING")
        db.execute(
            "INSERT INTO mosque_leader_requests VALUES(?,?,?,?,?,?,?,?,?,?,?)",
            (
                request_id,
                account["id"],
                body.mosque_id,
                body.mosque_name,
                body.city,
                body.requested_role,
                "PENDING",
                body.note,
                now_iso(),
                None,
                None,
            ),
        )
        audit(db, account["id"], "MOSQUE_LEADER_REQUESTED", request_id, body.mosque_id)
    return {"id": request_id, "status": "PENDING"}


@router.get("/admin/mosque-leader-requests")
def admin_leader_requests(account=Depends(guardian), database=Depends(store)):
    with database.transaction() as db:
        platform_admin(db, account)
        return [
            dict(row)
            for row in db.execute(
                """SELECT r.*,g.name applicant_name,g.email applicant_email
                   FROM mosque_leader_requests r JOIN guardians g ON g.id=r.user_id
                   ORDER BY CASE r.status WHEN 'PENDING' THEN 0 ELSE 1 END,r.created_at"""
            )
        ]


class LeaderDecisionBody(Body):
    approve: bool


@router.post("/admin/mosque-leader-requests/{request_id}/decision")
def decide_mosque_leadership(
    request_id: str,
    body: LeaderDecisionBody,
    account=Depends(guardian),
    database=Depends(store),
):
    with database.transaction() as db:
        platform_admin(db, account)
        request_row = db.execute(
            "SELECT * FROM mosque_leader_requests WHERE id=? AND status='PENDING'",
            (request_id,),
        ).fetchone()
        if not request_row:
            raise HTTPException(404, "PENDING_REQUEST_NOT_FOUND")
        status = "APPROVED" if body.approve else "REJECTED"
        mosque_id = request_row["mosque_id"]
        if body.approve:
            if not mosque_id:
                mosque_id = str(uuid.uuid4())
                db.execute(
                    "INSERT INTO mosques VALUES(?,?,?,?,?)",
                    (mosque_id, request_row["mosque_name"], request_row["city"], 1, now_iso()),
                )
            db.execute(
                "INSERT OR REPLACE INTO mosque_staff VALUES(?,?,?,?,?)",
                (
                    mosque_id,
                    request_row["user_id"],
                    request_row["requested_role"],
                    account["id"],
                    now_iso(),
                ),
            )
        db.execute(
            """UPDATE mosque_leader_requests SET status=?,mosque_id=?,reviewed_by=?,reviewed_at=?
               WHERE id=?""",
            (status, mosque_id, account["id"], now_iso(), request_id),
        )
        audit(db, account["id"], "MOSQUE_LEADER_REQUEST_" + status, request_id, mosque_id)
    return {"status": status, "mosque_id": mosque_id}


@router.get("/mosques")
def list_mosques(account=Depends(guardian), database=Depends(store)):
    with database.transaction() as db:
        return [
            dict(row)
            for row in db.execute(
                """SELECT m.*,ms.role FROM mosques m
                   LEFT JOIN mosque_staff ms ON ms.mosque_id=m.id AND ms.user_id=?
                   WHERE m.verified=1 ORDER BY m.city,m.name""",
                (account["id"],),
            )
        ]


class MosqueGroupBody(Body):
    name: str = Field(min_length=1, max_length=100)
    age_band: str = Field(default="ADULT", pattern="^(CHILD_5_9|CHILD_10_13|TEEN_14_17|ADULT)$")
    timezone: str = "Asia/Riyadh"
    schedule: Schedule | None = None


@router.post("/mosques/{mosque_id}/groups")
def create_mosque_group(
    mosque_id: str,
    body: MosqueGroupBody,
    account=Depends(guardian),
    database=Depends(store),
):
    group_id = str(uuid.uuid4())
    with database.transaction() as db:
        mosque_staff(db, mosque_id, account)
        schedule = json.dumps(
            body.schedule.model_dump(mode="json", by_alias=True) if body.schedule else {}
        )
        db.execute(
            "INSERT INTO mosque_groups VALUES(?,?,?,?,?,?,?,?,?)",
            (
                group_id,
                mosque_id,
                body.name,
                body.age_band,
                body.timezone,
                schedule,
                account["id"],
                1,
                now_iso(),
            ),
        )
        audit(db, account["id"], "MOSQUE_GROUP_CREATED", group_id, mosque_id)
    return {"id": group_id}


@router.get("/mosque-groups")
def list_mosque_groups(account=Depends(guardian), database=Depends(store)):
    with database.transaction() as db:
        led = [
            dict(row) | {"access": "LEADER"}
            for row in db.execute(
                """SELECT DISTINCT mg.id,mg.name,mg.age_band,m.id mosque_id,
                          m.name mosque_name,m.city
                   FROM mosque_groups mg JOIN mosques m ON m.id=mg.mosque_id
                   JOIN mosque_staff ms ON ms.mosque_id=m.id
                   WHERE ms.user_id=? AND mg.active=1 ORDER BY m.name,mg.name""",
                (account["id"],),
            )
        ]
        joined = [
            dict(row) | {"access": "PERSONAL"}
            for row in db.execute(
                """SELECT DISTINCT mg.id,mg.name,mg.age_band,m.id mosque_id,
                          m.name mosque_name,m.city
                   FROM group_memberships gm JOIN mosque_groups mg ON mg.id=gm.group_id
                   JOIN mosques m ON m.id=mg.mosque_id
                   LEFT JOIN guardian_links gl ON gl.child_id=gm.child_id
                   LEFT JOIN children c ON c.id=gm.child_id
                   WHERE gm.status='ACTIVE' AND (gl.user_id=? OR c.account_user_id=?)
                   ORDER BY m.name,mg.name""",
                (account["id"], account["id"]),
            )
        ]
        by_id = {row["id"]: row for row in joined}
        by_id.update({row["id"]: row for row in led})
        return list(by_id.values())


@router.post("/mosque-groups/{group_id}/invite")
def mosque_group_invite(
    group_id: str,
    request: Request,
    account=Depends(guardian),
    database=Depends(store),
):
    raw, manual = secrets.token_urlsafe(32), code()
    expires = time.time() + 7 * 86400
    with database.transaction() as db:
        limited(request, db, "mosque-group-invite", 30)
        led_group(db, group_id, account)
        db.execute("UPDATE group_invites SET revoked=1 WHERE group_id=?", (group_id,))
        db.execute(
            "INSERT INTO group_invites VALUES(?,?,?,?,?,?,0,?)",
            (
                str(uuid.uuid4()),
                group_id,
                digest(raw),
                digest(manual),
                expires,
                account["id"],
                now_iso(),
            ),
        )
    return {
        "qr_payload": "iqtadi-group:" + raw,
        "code": manual,
        "expires_at": datetime.fromtimestamp(expires, timezone.utc).isoformat(),
    }


class GroupJoinBody(TokenBody):
    profile_id: str
    alias: str = Field(min_length=2, max_length=40)
    share_practice: bool = True
    share_attendance: bool = True
    leaderboard: bool = True


@router.post("/mosque-groups/join")
def join_mosque_group(body: GroupJoinBody, account=Depends(guardian), database=Depends(store)):
    value = body.token.removeprefix("iqtadi-group:")
    normalized = value.upper().replace(" ", "").replace("-", "")
    with database.transaction() as db:
        profile = controlled_profile(db, body.profile_id, account)
        invite = db.execute(
            """SELECT gi.*,mg.active,mg.age_band FROM group_invites gi
               JOIN mosque_groups mg ON mg.id=gi.group_id
               WHERE (gi.token_hash=? OR gi.code_hash=?) AND gi.expires_at>?
                 AND gi.revoked=0 AND mg.active=1""",
            (digest(value), digest(normalized), time.time()),
        ).fetchone()
        if not invite:
            raise HTTPException(400, "INVITATION_INVALID_OR_EXPIRED")
        if profile["profile_kind"] == "SELF" and invite["age_band"] != "ADULT":
            raise HTTPException(400, "ADULT_CANNOT_JOIN_CHILD_GROUP")
        if profile["profile_kind"] == "DEPENDENT" and (
            invite["age_band"] == "ADULT" or profile["age_band"] != invite["age_band"]
        ):
            raise HTTPException(400, "CHILD_AGE_GROUP_MISMATCH")
        collision = db.execute(
            """SELECT 1 FROM group_memberships WHERE group_id=? AND alias=?
               AND status='ACTIVE' AND child_id<>?""",
            (invite["group_id"], body.alias, profile["id"]),
        ).fetchone()
        if collision:
            raise HTTPException(409, "ALIAS_ALREADY_USED")
        joined_at = now_iso()
        # Adults join as themselves. A dependent's guardian gives consent first,
        # then an authorised mosque leader explicitly accepts the child.
        membership_status = "ACTIVE" if profile["profile_kind"] == "SELF" else "PENDING"
        db.execute(
            """UPDATE guardian_consents SET revoked_at=?
               WHERE child_id=? AND group_id=? AND revoked_at IS NULL""",
            (joined_at, profile["id"], invite["group_id"]),
        )
        db.execute(
            """INSERT INTO guardian_consents VALUES(?,?,?,?,?,?,?,?,NULL)""",
            (
                str(uuid.uuid4()),
                account["id"],
                profile["id"],
                invite["group_id"],
                body.share_practice,
                body.share_attendance,
                body.leaderboard,
                joined_at,
            ),
        )
        db.execute(
            """INSERT INTO group_memberships VALUES(?,?,?,?,?,NULL)
               ON CONFLICT(group_id,child_id) DO UPDATE SET
                 alias=excluded.alias,status=excluded.status,joined_at=excluded.joined_at,left_at=NULL""",
            (invite["group_id"], profile["id"], body.alias, membership_status, joined_at),
        )
        audit(db, account["id"], "GUARDIAN_GROUP_CONSENT", profile["id"], invite["group_id"])
    return {
        "group_id": invite["group_id"],
        "profile_id": profile["id"],
        "joined": membership_status == "ACTIVE",
        "status": membership_status,
    }


@router.post("/mosque-groups/{group_id}/members/{profile_id}/approve")
def approve_group_member(
    group_id: str,
    profile_id: str,
    account=Depends(guardian),
    database=Depends(store),
):
    with database.transaction() as db:
        led_group(db, group_id, account)
        membership = db.execute(
            """SELECT gm.*,c.profile_kind FROM group_memberships gm
               JOIN children c ON c.id=gm.child_id
               WHERE gm.group_id=? AND gm.child_id=? AND gm.status='PENDING'""",
            (group_id, profile_id),
        ).fetchone()
        if not membership:
            raise HTTPException(404, "PENDING_MEMBERSHIP_NOT_FOUND")
        if membership["profile_kind"] != "DEPENDENT":
            raise HTTPException(400, "APPROVAL_ONLY_REQUIRED_FOR_DEPENDENTS")
        db.execute(
            "UPDATE group_memberships SET status='ACTIVE',left_at=NULL WHERE group_id=? AND child_id=?",
            (group_id, profile_id),
        )
        audit(db, account["id"], "LEADER_APPROVED_CHILD", profile_id, group_id)
    return {"approved": True}


@router.delete("/mosque-groups/{group_id}/members/{profile_id}")
def remove_group_member(
    group_id: str,
    profile_id: str,
    account=Depends(guardian),
    database=Depends(store),
):
    with database.transaction() as db:
        leader = False
        try:
            led_group(db, group_id, account)
            leader = True
        except HTTPException:
            controlled_profile(db, profile_id, account)
        left = now_iso()
        db.execute(
            """UPDATE group_memberships SET status='REMOVED',left_at=?
               WHERE group_id=? AND child_id=?""",
            (left, group_id, profile_id),
        )
        db.execute(
            """UPDATE guardian_consents SET revoked_at=?
               WHERE group_id=? AND child_id=? AND revoked_at IS NULL""",
            (left, group_id, profile_id),
        )
        audit(
            db,
            account["id"],
            "LEADER_REMOVED_MEMBER" if leader else "GUARDIAN_REVOKED_CONSENT",
            profile_id,
            group_id,
        )
    return {"removed": True}


def group_metrics(db, group: dict):
    timing = PrayerTimeService(group["timezone"], json.loads(group["schedule"]))
    today = datetime.now(timing.tz).date()
    sessions = [
        dict(row)
        for row in db.execute(
            """SELECT * FROM attendance_sessions WHERE group_id=? AND prayer_day>=?
               ORDER BY prayer_day,created_at""",
            (group["id"], (today - timedelta(days=6)).isoformat()),
        )
    ]
    members = []
    rows = db.execute(
        """SELECT gm.*,gc.share_practice,gc.share_attendance,gc.leaderboard
           FROM group_memberships gm JOIN guardian_consents gc
             ON gc.group_id=gm.group_id AND gc.child_id=gm.child_id AND gc.revoked_at IS NULL
           WHERE gm.group_id=? AND gm.status='ACTIVE' ORDER BY gm.joined_at""",
        (group["id"],),
    ).fetchall()
    for row in rows:
        item = {
            "profile_id": row["child_id"],
            "alias": row["alias"],
            "leaderboard": bool(row["leaderboard"]),
        }
        if row["share_practice"]:
            attempts = [
                dict(r)
                for r in db.execute("SELECT * FROM attempts WHERE child_id=?", (row["child_id"],))
            ]
            practice = progress(attempts, timing, today)
            item["practice"] = {
                "weekly_points": practice["weekly_points"],
                "weekly_valid_prayers": practice["weekly_valid_prayers"],
                "streak": practice["streak"],
            }
        if row["share_attendance"]:
            eligible = [s for s in sessions if s["created_at"] >= row["joined_at"]]
            attended = db.execute(
                """SELECT count(*) FROM attendance_events ae JOIN attendance_sessions s
                   ON s.id=ae.session_id WHERE ae.child_id=?
                   AND s.group_id=? AND s.prayer_day>=?""",
                (row["child_id"], group["id"], (today - timedelta(days=6)).isoformat()),
            ).fetchone()[0]
            item["attendance"] = {
                "attended": attended,
                "eligible": len(eligible),
                "rate": round(attended / len(eligible), 4) if eligible else 0.0,
            }
        members.append(item)
    ranked = [m for m in members if m["leaderboard"]]
    return (
        members,
        sorted(
            [m for m in ranked if "practice" in m],
            key=lambda m: (-m["practice"]["weekly_points"], m["alias"]),
        ),
        sorted(
            [m for m in ranked if "attendance" in m],
            key=lambda m: (-m["attendance"]["rate"], -m["attendance"]["attended"], m["alias"]),
        ),
        sessions,
    )


@router.get("/mosque-groups/{group_id}/dashboard")
def mosque_group_dashboard(group_id: str, account=Depends(guardian), database=Depends(store)):
    with database.transaction() as db:
        group, is_leader = group_visible(db, group_id, account)
        members, practice_board, attendance_board, sessions = group_metrics(db, group)
        pending = []
        if is_leader:
            pending = [
                dict(row)
                for row in db.execute(
                    """SELECT gm.child_id profile_id,gm.alias,gm.joined_at
                       FROM group_memberships gm JOIN children c ON c.id=gm.child_id
                       WHERE gm.group_id=? AND gm.status='PENDING'
                         AND c.profile_kind='DEPENDENT' ORDER BY gm.joined_at""",
                    (group_id,),
                )
            ]
        return {
            "group": {
                k: group[k] for k in ("id", "name", "age_band", "mosque_id", "mosque_name", "city")
            },
            "access": "LEADER" if is_leader else "FAMILY",
            "members": members,
            "pending_members": pending,
            "practice_leaderboard": practice_board,
            "attendance_leaderboard": attendance_board,
            "attendance_sessions": [
                {k: s[k] for k in ("id", "prayer", "prayer_day", "expires_at", "closed_at")}
                for s in sessions
            ],
            "privacy": "الأسماء الحقيقية وبيانات الاتصال والوسائط لا تظهر للمجموعة.",
        }


class GroupMessageBody(Body):
    body: str = Field(min_length=1, max_length=280)
    parent_id: str | None = None


@router.get("/mosque-groups/{group_id}/messages")
def group_messages(group_id: str, account=Depends(guardian), database=Depends(store)):
    with database.transaction() as db:
        adult_group_member(db, group_id, account)
        return [
            dict(row)
            for row in db.execute(
                """SELECT id,author_profile_id,author_alias,body,parent_id,created_at
                   FROM mosque_group_messages
                   WHERE group_id=? AND deleted_at IS NULL
                   ORDER BY created_at DESC LIMIT 100""",
                (group_id,),
            )
        ][::-1]


@router.post("/mosque-groups/{group_id}/messages")
def create_group_message(
    group_id: str,
    body: GroupMessageBody,
    request: Request,
    account=Depends(guardian),
    database=Depends(store),
):
    message_id = str(uuid.uuid4())
    with database.transaction() as db:
        limited(request, db, "adult-group-message", 30)
        member = adult_group_member(db, group_id, account)
        if body.parent_id and not db.execute(
            """SELECT 1 FROM mosque_group_messages
               WHERE id=? AND group_id=? AND deleted_at IS NULL""",
            (body.parent_id, group_id),
        ).fetchone():
            raise HTTPException(404, "PARENT_MESSAGE_NOT_FOUND")
        db.execute(
            "INSERT INTO mosque_group_messages VALUES(?,?,?,?,?,?,?,NULL)",
            (
                message_id,
                group_id,
                member["profile_id"],
                member["alias"],
                body.body,
                body.parent_id,
                now_iso(),
            ),
        )
        audit(db, account["id"], "ADULT_GROUP_MESSAGE_CREATED", message_id, group_id)
    return {"id": message_id, "created": True}


class AttendanceSessionBody(Body):
    prayer: str = Field(pattern="^(fajr|dhuhr|asr|maghrib|isha)$")
    prayer_day: date
    valid_minutes: int = Field(default=30, ge=5, le=90)


@router.post("/mosque-groups/{group_id}/attendance-sessions")
def create_attendance_session(
    group_id: str,
    body: AttendanceSessionBody,
    request: Request,
    account=Depends(guardian),
    database=Depends(store),
):
    raw, manual = secrets.token_urlsafe(24), code(8)
    expires = time.time() + body.valid_minutes * 60
    with database.transaction() as db:
        limited(request, db, "attendance-session", 50)
        led_group(db, group_id, account)
        db.execute(
            """UPDATE attendance_sessions SET closed_at=?
               WHERE group_id=? AND prayer=? AND prayer_day=? AND closed_at IS NULL""",
            (now_iso(), group_id, body.prayer, body.prayer_day.isoformat()),
        )
        session_id = str(uuid.uuid4())
        db.execute(
            "INSERT INTO attendance_sessions VALUES(?,?,?,?,?,?,?,?,?,NULL)",
            (
                session_id,
                group_id,
                body.prayer,
                body.prayer_day.isoformat(),
                digest(raw),
                digest(manual),
                expires,
                account["id"],
                now_iso(),
            ),
        )
        audit(db, account["id"], "ATTENDANCE_SESSION_CREATED", session_id, group_id)
    return {
        "id": session_id,
        "qr_payload": "iqtadi-attend:" + raw,
        "code": manual,
        "expires_at": datetime.fromtimestamp(expires, timezone.utc).isoformat(),
    }


@router.post("/attendance/check-in", dependencies=[Depends(boundary)])
def attendance_check_in(body: TokenBody, profile=Depends(device), database=Depends(store)):
    value = body.token.removeprefix("iqtadi-attend:")
    normalized = value.upper().replace(" ", "").replace("-", "")
    with database.transaction() as db:
        session = db.execute(
            """SELECT * FROM attendance_sessions WHERE
               (token_hash=? OR code_hash=?) AND expires_at>? AND closed_at IS NULL""",
            (digest(value), digest(normalized), time.time()),
        ).fetchone()
        if not session:
            raise HTTPException(400, "ATTENDANCE_CODE_INVALID_OR_EXPIRED")
        allowed = db.execute(
            """SELECT 1 FROM group_memberships gm JOIN guardian_consents gc
               ON gc.group_id=gm.group_id AND gc.child_id=gm.child_id AND gc.revoked_at IS NULL
               WHERE gm.group_id=? AND gm.child_id=? AND gm.status='ACTIVE'
                 AND gc.share_attendance=1""",
            (session["group_id"], profile["child_id"]),
        ).fetchone()
        if not allowed:
            raise HTTPException(403, "ATTENDANCE_CONSENT_REQUIRED")
        event_id = str(uuid.uuid4())
        db.execute(
            """INSERT OR IGNORE INTO attendance_events VALUES(?,?,?,?,?,?)""",
            (
                event_id,
                session["id"],
                profile["child_id"],
                "QR",
                "profile:" + profile["child_id"],
                now_iso(),
            ),
        )
        duplicate = db.execute("SELECT changes()").fetchone()[0] == 0
    return {"checked_in": True, "duplicate": duplicate}


class AttendanceMarkBody(Body):
    profile_id: str


@router.post("/attendance-sessions/{session_id}/mark")
def leader_attendance_mark(
    session_id: str,
    body: AttendanceMarkBody,
    account=Depends(guardian),
    database=Depends(store),
):
    with database.transaction() as db:
        session = db.execute(
            "SELECT * FROM attendance_sessions WHERE id=?", (session_id,)
        ).fetchone()
        if not session:
            raise HTTPException(404, "ATTENDANCE_SESSION_NOT_FOUND")
        led_group(db, session["group_id"], account)
        allowed = db.execute(
            """SELECT 1 FROM group_memberships gm JOIN guardian_consents gc
               ON gc.group_id=gm.group_id AND gc.child_id=gm.child_id AND gc.revoked_at IS NULL
               WHERE gm.group_id=? AND gm.child_id=? AND gm.status='ACTIVE'
                 AND gc.share_attendance=1""",
            (session["group_id"], body.profile_id),
        ).fetchone()
        if not allowed:
            raise HTTPException(404, "GROUP_MEMBER_NOT_FOUND")
        db.execute(
            "INSERT OR IGNORE INTO attendance_events VALUES(?,?,?,?,?,?)",
            (
                str(uuid.uuid4()),
                session_id,
                body.profile_id,
                "LEADER",
                account["id"],
                now_iso(),
            ),
        )
        audit(db, account["id"], "LEADER_ATTENDANCE_MARK", body.profile_id, session_id)
    return {"checked_in": True}


@router.get("/mosques/{mosque_id}/leaderboard")
def mosque_leaderboard(mosque_id: str, account=Depends(guardian), database=Depends(store)):
    with database.transaction() as db:
        # Only verified staff or guardians/members of a mosque group can view it.
        visible = db.execute(
            """SELECT 1 FROM mosque_staff WHERE mosque_id=? AND user_id=?
               UNION SELECT 1 FROM mosque_groups mg
               JOIN group_memberships gm ON gm.group_id=mg.id AND gm.status='ACTIVE'
               LEFT JOIN guardian_links gl ON gl.child_id=gm.child_id
               LEFT JOIN children c ON c.id=gm.child_id
               WHERE mg.mosque_id=? AND (gl.user_id=? OR c.account_user_id=?) LIMIT 1""",
            (mosque_id, account["id"], mosque_id, account["id"], account["id"]),
        ).fetchone()
        if not visible:
            raise HTTPException(404, "MOSQUE_NOT_FOUND")
        today = date.today()
        groups = []
        for group_row in db.execute(
            "SELECT * FROM mosque_groups WHERE mosque_id=? AND active=1", (mosque_id,)
        ).fetchall():
            group = dict(group_row)
            members, _, _, sessions = group_metrics(db, group)
            attended = sum(m.get("attendance", {}).get("attended", 0) for m in members)
            eligible = sum(m.get("attendance", {}).get("eligible", 0) for m in members)
            groups.append(
                {
                    "group_id": group["id"],
                    "group_name": group["name"],
                    "member_count": len(members),
                    "sessions": len(sessions),
                    "attendance_rate": round(attended / eligible, 4) if eligible else 0.0,
                }
            )
        groups.sort(key=lambda row: (-row["attendance_rate"], row["group_name"]))
        return {
            "from": (today - timedelta(days=6)).isoformat(),
            "until": today.isoformat(),
            "groups": groups,
            "identity_policy": "GROUP_TOTALS_ONLY",
        }
