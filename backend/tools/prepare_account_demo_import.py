"""Generate private, labelled Ezz samples for an explicitly authorized import.

Never use this against the live DB. Credentials remain in a private local file;
stdout contains only paths/counts. The existing Ezz isolated seed stays intact.
"""

import argparse
import contextlib
import io
import json
import os
import secrets
import sqlite3
import sys
from pathlib import Path

from app.accounts.auth import passwords
from app.accounts.store import digest
from tools import seed_account_demo
from tools.import_account_demo import connect_readonly, load_source


def prepare_demo(database, credentials):
    database, credentials = Path(database).resolve(), Path(credentials).resolve()
    if not database.name.endswith(".demo.sqlite3") or database == credentials:
        raise ValueError("Use a separate isolated .demo.sqlite3 and credentials file")
    if database.exists() or credentials.exists():
        raise FileExistsError("Never replace an existing demo or credentials file")
    database.parent.mkdir(parents=True, exist_ok=True)
    credentials.parent.mkdir(parents=True, exist_ok=True)
    # Reserve the credential output before creating the source database.
    descriptor = os.open(credentials, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    member_password = secrets.token_urlsafe(24) + "aA1!"
    admin_password = secrets.token_urlsafe(30) + "aA1!"
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    join_code = "".join(secrets.choice(alphabet) for _ in range(16))
    attendance_code = "".join(secrets.choice(alphabet) for _ in range(16))
    old_args = sys.argv
    try:
        # Ezz itself refuses the configured live database and non-empty accounts.
        sys.argv = ["seed", "--db", str(database), "--password=" + member_password]
        with contextlib.redirect_stdout(io.StringIO()):
            seed_account_demo.main()
        os.chmod(database, 0o600)
        with contextlib.closing(sqlite3.connect(database)) as db, db:
            db.execute("UPDATE guardians SET password_hash=? WHERE email='admin@example.com'",
                       (passwords.hash(admin_password),))
            db.execute("UPDATE group_invites SET token_hash=?,code_hash=?",
                       (digest(secrets.token_urlsafe(32)), digest(join_code)))
            db.execute("UPDATE attendance_sessions SET token_hash=?,code_hash=? WHERE id='demo-live-attendance'",
                       (digest(secrets.token_urlsafe(32)), digest(attendance_code)))
            for table in ("guardians", "children", "groups", "mosques", "mosque_groups"):
                db.execute(f"UPDATE {table} SET name=name||' — تجريبي'")
        rows, _, fingerprint, moved = load_source(database)
        with contextlib.closing(connect_readonly(database)) as db:
            accounts = [dict(row) for row in db.execute("SELECT email,name FROM guardians ORDER BY email")]
        private = {"database": str(database), "demo_only": True,
                   "youth_join_code": join_code,
                   "today_youth_attendance_code": attendance_code,
                   "accounts": [{**account, "password": admin_password
                                  if account["email"] == "admin@example.com" else member_password}
                                 for account in accounts]}
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            descriptor = None
            json.dump(private, output, ensure_ascii=False, indent=2)
        return {"source": str(database), "private_credentials": str(credentials),
                "fingerprint": fingerprint, "added": {table: len(value) for table, value in rows.items()},
                "age_memberships_to_correct": moved, "mail_sent": False}
    finally:
        sys.argv = old_args
        if descriptor is not None:
            os.close(descriptor)
        # On failure preserve artifacts for investigation; never silently reset.


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", required=True)
    parser.add_argument("--credentials", required=True)
    args = parser.parse_args()
    print(json.dumps(prepare_demo(args.db, args.credentials)))


if __name__ == "__main__":
    main()
