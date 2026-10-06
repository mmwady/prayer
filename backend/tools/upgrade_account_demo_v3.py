"""Add v3 administration and second-family samples without replacing user data."""

import argparse
import json
from datetime import datetime, timezone

from app.accounts.auth import passwords
from app.accounts.store import AccountStore, ensure_personal_profile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", required=True)
    parser.add_argument("--password", default="IqtadiDemo!2026")
    args = parser.parse_args()
    store = AccountStore(args.db)
    created = datetime.now(timezone.utc).isoformat()
    with store.transaction() as db:
        admin = db.execute(
            "SELECT id FROM guardians WHERE email='admin@example.com'"
        ).fetchone()
        if admin:
            admin_id = admin["id"]
        else:
            import uuid

            admin_id = str(uuid.uuid4())
            db.execute(
                """INSERT INTO guardians
                   (id,name,email,role,created_at,password_hash,email_verified,
                    learning_stage,accessibility_mode)
                   VALUES(?,?,?,?,?,?,?,?,?)""",
                (
                    admin_id,
                    "مدير منصة اقتدِ",
                    "admin@example.com",
                    "PARENT",
                    created,
                    passwords.hash(args.password),
                    1,
                    "GENERAL",
                    "STANDARD",
                ),
            )
            ensure_personal_profile(db, admin_id, "مدير منصة اقتدِ", created)
        db.execute(
            "INSERT OR IGNORE INTO platform_admins VALUES(?,?)", (admin_id, created)
        )

        owner = db.execute(
            "SELECT id FROM guardians WHERE email='demo@example.com'"
        ).fetchone()
        elder = db.execute(
            "SELECT id FROM guardians WHERE email='elder@example.com'"
        ).fetchone()
        if owner:
            schedule_row = db.execute(
                "SELECT schedule FROM groups WHERE id='demo-family'"
            ).fetchone()
            schedule = schedule_row["schedule"] if schedule_row else json.dumps({})
            db.execute(
                """INSERT OR IGNORE INTO groups
                   (id,owner_user_id,name,type,timezone,schedule,created_at)
                   VALUES(?,?,?,?,?,?,?)""",
                (
                    "demo-second-family",
                    owner["id"],
                    "أسرة آل سالم",
                    "FAMILY",
                    "Asia/Riyadh",
                    schedule,
                    created,
                ),
            )
            db.execute(
                "INSERT OR IGNORE INTO family_memberships VALUES(?,?,?,?)",
                ("demo-second-family", owner["id"], "OWNER", created),
            )
            if elder:
                db.execute(
                    "INSERT OR IGNORE INTO family_memberships VALUES(?,?,?,?)",
                    ("demo-second-family", elder["id"], "SUPPORTER", created),
                )
    print("Account demo v3 upgrade complete")


if __name__ == "__main__":
    main()
