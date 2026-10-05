"""Explicit isolated developer seed. No authentication bypass or real account data.

python -m tools.seed_account_demo --db data/accounts.demo.sqlite3
Creates an unverified guardian; use normal email verification before login.
Password is prompted without echo; it is never a default production credential.
"""

import argparse
import getpass
import json
import uuid
from datetime import datetime, timedelta, timezone
from app.accounts.auth import SignupBody, register
from app.accounts.store import AccountStore
from app.config import get_settings


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", required=True)
    parser.add_argument("--email", default="mohamed@example.com")
    args = parser.parse_args()
    if not args.db.endswith(".demo.sqlite3") or args.db == get_settings().account_db:
        parser.error(
            "Use a separate filename ending .demo.sqlite3, not the running account database"
        )
    password = getpass.getpass("Demo guardian password (10+ characters): ")
    store = AccountStore(args.db)
    now = datetime.now(timezone.utc)
    with store.transaction() as db:
        if db.execute("SELECT 1 FROM guardians").fetchone():
            parser.error("Seed requires an empty isolated database")
        body = SignupBody(name="Mohamed — DEMO", email=args.email, password=password, role="PARENT")
        register(db, body)
        owner = db.execute("SELECT id FROM guardians").fetchone()["id"]
        group = str(uuid.uuid4())
        db.execute(
            "INSERT INTO groups VALUES(?,?,?,?,?,?,?)",
            (
                group,
                owner,
                "أسرة تجريبية — بيانات اصطناعية",
                "FAMILY",
                "Africa/Cairo",
                json.dumps({}),
                now.isoformat(),
            ),
        )
        for name, age, complete in [("Omar", 11, 4), ("Ali", 9, 5), ("Youssef", 13, 3)]:
            child = str(uuid.uuid4())
            db.execute(
                "INSERT INTO children VALUES(?,?,?,?,?,?,?)",
                (child, group, name + " — DEMO", age, None, 1, now.isoformat()),
            )
            for offset in range(1, 8):
                for index, (prayer, n) in enumerate(
                    [("fajr", 2), ("dhuhr", 4), ("asr", 4), ("maghrib", 3), ("isha", 4)]
                ):
                    if index >= complete:
                        continue
                    performed = (now - timedelta(days=offset)).replace(
                        hour=[3, 10, 13, 16, 18][index], minute=0, second=0, microsecond=0
                    )
                    db.execute(
                        "INSERT INTO attempts VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                        (
                            str(uuid.uuid4()),
                            child,
                            str(uuid.uuid4()),
                            prayer,
                            performed.isoformat(),
                            1,
                            1,
                            0,
                            None,
                            None,
                            n,
                            n,
                            "synthetic-demo-seed",
                            now.isoformat(),
                        ),
                    )
    print(
        "Isolated demo data created. Activate email using the configured SMTP/local outbox, then log in normally."
    )


if __name__ == "__main__":
    main()
