"""Create an isolated, verified, rich account-spaces demonstration database.

The filename must end in ``.demo.sqlite3`` and must not be the configured live
database.  Credentials are intentionally deterministic for local demonstrations
only; the script refuses to seed a non-empty database.

    python -m tools.seed_account_demo --db data/iqtadi.rich.demo.sqlite3
"""

import argparse
import json
import time
import uuid
from datetime import datetime, timedelta, timezone
from datetime import time as clock_time
from zoneinfo import ZoneInfo

from app.accounts.auth import passwords
from app.accounts.store import AccountStore, digest, ensure_personal_profile
from app.config import get_settings

DEFAULT_PASSWORD = "IqtadiDemo!2026"
SCHEDULE = {
    "fajr": "04:45",
    "sunrise": "06:05",
    "dhuhr": "11:50",
    "asr": "15:15",
    "maghrib": "17:55",
    "isha": "19:25",
}
PRAYERS = [("fajr", 2), ("dhuhr", 4), ("asr", 4), ("maghrib", 3), ("isha", 4)]


def uid() -> str:
    return str(uuid.uuid4())


def add_account(db, email, name, password, stage="GENERAL", accessibility="STANDARD"):
    user_id = uid()
    created = datetime.now(timezone.utc).isoformat()
    db.execute(
        """INSERT INTO guardians
           (id,name,email,role,created_at,password_hash,email_verified,
            learning_stage,accessibility_mode)
           VALUES(?,?,?,?,?,?,?,?,?)""",
        (
            user_id,
            name,
            email,
            "PARENT",
            created,
            passwords.hash(password),
            1,
            stage,
            accessibility,
        ),
    )
    profile_id = ensure_personal_profile(db, user_id, name, created)
    return user_id, profile_id


def add_attempts(db, profile_id, local_now, daily_counts, label):
    created = datetime.now(timezone.utc).isoformat()
    for offset, count in enumerate(daily_counts):
        day = local_now.date() - timedelta(days=offset)
        for prayer, rakats in PRAYERS[:count]:
            hour, minute = map(int, SCHEDULE[prayer].split(":"))
            performed = datetime.combine(day, clock_time(hour, minute), local_now.tzinfo)
            db.execute(
                """INSERT INTO attempts
                   (id,child_id,client_attempt_id,prayer,performed_at,valid,
                    sequence_valid,uncertain,on_time,confidence,rakats_expected,
                    rakats_completed,analysis_version,created_at)
                   VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                (
                    uid(),
                    profile_id,
                    f"demo-{label}-{offset}-{prayer}",
                    prayer,
                    performed.astimezone(timezone.utc).isoformat(),
                    1,
                    1,
                    0,
                    1,
                    0.94,
                    rakats,
                    rakats,
                    "demo-camera-local-v1",
                    created,
                ),
            )


def add_dependent(db, family_id, name, age, age_band, alias, created):
    profile_id = uid()
    db.execute(
        """INSERT INTO children
           (id,group_id,name,age,avatar,active,created_at,profile_kind,
            account_user_id,age_band,alias)
           VALUES(?,?,?,?,?,?,?,?,?,?,?)""",
        (
            profile_id,
            family_id,
            name,
            age,
            None,
            1,
            created,
            "DEPENDENT",
            None,
            age_band,
            alias,
        ),
    )
    return profile_id


def add_consent(db, guardian_id, group_id, profile_id, alias, joined):
    db.execute(
        "INSERT INTO group_memberships VALUES(?,?,?,?,?,NULL)",
        (group_id, profile_id, alias, "ACTIVE", joined),
    )
    db.execute(
        "INSERT INTO guardian_consents VALUES(?,?,?,?,?,?,?,?,NULL)",
        (uid(), guardian_id, profile_id, group_id, 1, 1, 1, joined),
    )


def add_attendance_history(db, group_id, profiles, local_now, prayers_per_day, leader_id):
    """profiles is ``[(profile_id, number_of_events_to_keep), ...]``."""

    sessions = []
    for offset in range(7):
        day = local_now.date() - timedelta(days=offset)
        for prayer in prayers_per_day:
            created_local = datetime.combine(day, clock_time(5, 0), local_now.tzinfo)
            session_id = uid()
            db.execute(
                "INSERT INTO attendance_sessions VALUES(?,?,?,?,?,?,?,?,?,?)",
                (
                    session_id,
                    group_id,
                    prayer,
                    day.isoformat(),
                    digest(uid()),
                    digest(uid()),
                    created_local.timestamp() + 1800,
                    leader_id,
                    created_local.astimezone(timezone.utc).isoformat(),
                    created_local.astimezone(timezone.utc).isoformat(),
                ),
            )
            sessions.append((session_id, created_local))
    for profile_id, total in profiles:
        for index, (session_id, created_local) in enumerate(sessions[:total]):
            db.execute(
                "INSERT INTO attendance_events VALUES(?,?,?,?,?,?)",
                (
                    uid(),
                    session_id,
                    profile_id,
                    "QR" if index % 3 else "LEADER",
                    "profile:" + profile_id if index % 3 else leader_id,
                    (created_local + timedelta(minutes=8)).astimezone(timezone.utc).isoformat(),
                ),
            )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", required=True)
    parser.add_argument("--password", default=DEFAULT_PASSWORD)
    args = parser.parse_args()
    if not args.db.endswith(".demo.sqlite3") or args.db == get_settings().account_db:
        parser.error("Use a separate filename ending .demo.sqlite3, not the live account database")
    if len(args.password) < 8:
        parser.error("Demo password must contain at least 8 characters")

    store = AccountStore(args.db)
    local_now = datetime.now(ZoneInfo("Asia/Riyadh"))
    now = datetime.now(timezone.utc)
    created = (now - timedelta(days=40)).isoformat()
    schedule = {
        "from": (local_now.date() - timedelta(days=15)).isoformat(),
        "until": (local_now.date() + timedelta(days=15)).isoformat(),
        **SCHEDULE,
    }

    with store.transaction() as db:
        if db.execute("SELECT 1 FROM guardians").fetchone():
            parser.error("Seed requires an empty isolated database")

        owner, owner_profile = add_account(
            db, "demo@example.com", "محمد العتيبي", args.password
        )
        guardian, guardian_profile = add_account(
            db, "guardian@example.com", "مريم العتيبي", args.password
        )
        new_muslim, new_muslim_profile = add_account(
            db,
            "newmuslim@example.com",
            "عبدالله السالم",
            args.password,
            stage="NEW_MUSLIM",
        )
        elder, elder_profile = add_account(
            db,
            "elder@example.com",
            "إبراهيم العتيبي",
            args.password,
            accessibility="LARGE_TEXT",
        )
        sheikh, _ = add_account(db, "sheikh@example.com", "الشيخ خالد الحربي", args.password)
        platform_admin, _ = add_account(
            db, "admin@example.com", "مدير منصة اقتدِ", args.password
        )
        db.execute(
            "INSERT INTO platform_admins VALUES(?,?)", (platform_admin, created)
        )

        family_id = "demo-family"
        db.execute(
            """INSERT INTO groups(id,owner_user_id,name,type,timezone,schedule,created_at)
               VALUES(?,?,?,?,?,?,?)""",
            (
                family_id,
                owner,
                "أسرة العتيبي",
                "FAMILY",
                "Asia/Riyadh",
                json.dumps(schedule),
                created,
            ),
        )
        for user_id, role in [
            (owner, "OWNER"),
            (guardian, "GUARDIAN"),
            (new_muslim, "ADULT"),
            (elder, "SUPPORTER"),
        ]:
            db.execute(
                "INSERT INTO family_memberships VALUES(?,?,?,?)",
                (family_id, user_id, role, created),
            )

        second_family_id = "demo-second-family"
        db.execute(
            """INSERT INTO groups(id,owner_user_id,name,type,timezone,schedule,created_at)
               VALUES(?,?,?,?,?,?,?)""",
            (
                second_family_id,
                owner,
                "أسرة آل سالم",
                "FAMILY",
                "Asia/Riyadh",
                json.dumps(schedule),
                created,
            ),
        )
        db.execute(
            "INSERT INTO family_memberships VALUES(?,?,?,?)",
            (second_family_id, owner, "OWNER", created),
        )
        db.execute(
            "INSERT INTO family_memberships VALUES(?,?,?,?)",
            (second_family_id, elder, "SUPPORTER", created),
        )

        omar = add_dependent(db, family_id, "عمر محمد", 11, "CHILD_10_13", "النجم الأخضر", created)
        ali = add_dependent(db, family_id, "علي محمد", 8, "CHILD_5_9", "الصقر", created)
        mariam = add_dependent(db, family_id, "مريم محمد", 15, "TEEN_14_17", "الهمة", created)
        for user_id, authority in [(owner, "OWNER"), (guardian, "GUARDIAN")]:
            for profile_id in (omar, ali, mariam):
                db.execute(
                    "INSERT INTO guardian_links VALUES(?,?,?,?)",
                    (user_id, profile_id, authority, created),
                )

        mosque_id = "demo-mosque"
        db.execute(
            "INSERT INTO mosques VALUES(?,?,?,?,?)",
            (mosque_id, "مسجد النور", "سكاكا", 1, created),
        )
        db.execute(
            "INSERT INTO mosque_staff VALUES(?,?,?,?,?)",
            (mosque_id, sheikh, "ADMIN", sheikh, created),
        )
        db.execute(
            "INSERT INTO mosque_staff VALUES(?,?,?,?,?)",
            (mosque_id, owner, "LEADER", sheikh, created),
        )

        youth_group = "demo-youth-group"
        adult_group = "demo-adult-group"
        for group_id, name, band in [
            (youth_group, "براعم الفجر", "CHILD_10_13"),
            (adult_group, "رفقاء المسجد", "ADULT"),
        ]:
            db.execute(
                "INSERT INTO mosque_groups VALUES(?,?,?,?,?,?,?,?,?)",
                (
                    group_id,
                    mosque_id,
                    name,
                    band,
                    "Asia/Riyadh",
                    json.dumps(schedule),
                    owner,
                    1,
                    created,
                ),
            )

        joined = (now - timedelta(days=20)).isoformat()
        add_consent(db, owner, youth_group, omar, "النجم الأخضر", joined)
        add_consent(db, owner, youth_group, ali, "الصقر", joined)
        add_consent(db, owner, youth_group, mariam, "الهمة", joined)
        add_consent(db, new_muslim, adult_group, new_muslim_profile, "طالب الهدى", joined)
        add_consent(db, guardian, adult_group, guardian_profile, "أم عمر", joined)

        # A reusable parent-scanned group invitation and today's onsite check-in.
        join_code = "DEMOJOIN24"
        db.execute(
            "INSERT INTO group_invites VALUES(?,?,?,?,?,?,0,?)",
            (
                uid(),
                youth_group,
                digest("demo-group-invite-token"),
                digest(join_code),
                time.time() + 30 * 86400,
                owner,
                now_iso := now.isoformat(),
            ),
        )
        attendance_code = "FAJRDEMO"
        db.execute(
            "INSERT INTO attendance_sessions VALUES(?,?,?,?,?,?,?,?,?,NULL)",
            (
                "demo-live-attendance",
                youth_group,
                "fajr",
                local_now.date().isoformat(),
                digest("demo-attendance-token"),
                digest(attendance_code),
                time.time() + 24 * 3600,
                owner,
                now_iso,
            ),
        )

        add_attempts(db, owner_profile, local_now, [5, 5, 5, 4, 5, 5, 3], "owner")
        add_attempts(db, guardian_profile, local_now, [5, 4, 5, 5, 4, 5, 5], "guardian")
        add_attempts(db, new_muslim_profile, local_now, [3, 3, 2, 3, 2, 2, 1], "new-muslim")
        add_attempts(db, elder_profile, local_now, [4, 4, 3, 4, 4, 3, 4], "elder")
        add_attempts(db, omar, local_now, [5, 4, 5, 5, 4, 5, 4], "omar")
        add_attempts(db, ali, local_now, [4, 3, 4, 5, 3, 4, 3], "ali")
        add_attempts(db, mariam, local_now, [3, 4, 3, 4, 3, 3, 4], "mariam")

        add_attendance_history(
            db,
            youth_group,
            [(omar, 18), (ali, 14), (mariam, 11)],
            local_now,
            ("fajr", "dhuhr", "isha"),
            owner,
        )
        add_attendance_history(
            db,
            adult_group,
            [(guardian_profile, 12), (new_muslim_profile, 10)],
            local_now,
            ("fajr", "isha"),
            owner,
        )

    print("Rich isolated demo database created:", args.db)
    print("Primary multi-role account: demo@example.com")
    print("Platform admin account: admin@example.com")
    print("Password:", args.password)
    print("Additional accounts: guardian@example.com, newmuslim@example.com,")
    print("  elder@example.com, sheikh@example.com (same password)")
    print("Youth group invitation code:", join_code)
    print("Today's mosque attendance code:", attendance_code)


if __name__ == "__main__":
    main()
