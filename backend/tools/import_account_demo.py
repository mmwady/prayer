"""Explicit, additive import of an isolated Ezz demo into an existing account DB.

No schema migration, registration, mail transport, overwrite or database reset.
Dry-run is the default. Apply requires a new backup path outside source/target.
"""

import argparse
import hashlib
import json
import os
import sqlite3
import uuid
from contextlib import closing
from datetime import datetime, timezone
from pathlib import Path

from app.accounts.auth import passwords

TABLES = (
    "guardians", "groups", "children", "family_memberships", "guardian_links",
    "mosques", "mosque_staff", "platform_admins", "mosque_groups", "group_invites",
    "group_memberships", "guardian_consents", "attempts", "attendance_sessions",
    "attendance_events",
)
EMPTY_TABLES = {
    "email_tokens", "pairing_tokens", "devices", "guardian_sessions", "rate_limits",
    "family_invites", "mosque_leader_requests", "mosque_group_messages",
    "account_audit_events", "account_email_outbox", "account_email_events",
}
EMAILS = {
    "demo@example.com", "guardian@example.com", "newmuslim@example.com",
    "elder@example.com", "sheikh@example.com", "admin@example.com",
}
ACTION = "RICH_DEMO_IMPORTED_V1"


def connect_readonly(path):
    db = sqlite3.connect(Path(path).resolve().as_uri() + "?mode=ro", uri=True, timeout=30)
    db.row_factory = sqlite3.Row
    return db


def schema(db):
    if db.execute("SELECT max(version) FROM account_schema").fetchone()[0] != 4:
        raise ValueError("Expected existing account schema v4; run normal migrations first")
    return {table: [tuple(row) for row in db.execute(f"PRAGMA table_info({table})")]
            for table in TABLES + ("account_audit_events",)}


def split_age_groups(rows):
    """Repair only generated demo relationships, retaining every attendance event."""
    profiles = {row["id"]: row for row in rows["children"]}
    groups = {row["id"]: row for row in rows["mosque_groups"]}
    sessions = {row["id"]: row for row in rows["attendance_sessions"]}
    clones = {}
    moved = 0
    for membership in rows["group_memberships"]:
        profile = profiles[membership["child_id"]]
        original = groups[membership["group_id"]]
        band = profile["age_band"]
        if band == original["age_band"]:
            continue
        if (profile["profile_kind"] != "DEPENDENT" or
                original["id"] != "demo-youth-group" or
                band not in {"CHILD_5_9", "TEEN_14_17"}):
            raise ValueError("Unexpected demo age-group mismatch")
        group_id = "demo-age-" + band.lower()
        if group_id not in groups:
            group = dict(original, id=group_id, age_band=band,
                         name=("براعم الصغار — تجريبي" if band == "CHILD_5_9"
                               else "رفقاء الشباب — تجريبي"))
            groups[group_id] = group
            rows["mosque_groups"].append(group)
            # Copy the full schedule, including missed sessions, to retain each
            # child's original attendance denominator and ranking percentage.
            for session in sessions.values():
                if session["group_id"] != original["id"]:
                    continue
                key = (session["id"], group_id)
                clone_id = str(uuid.uuid5(uuid.NAMESPACE_URL, "iqtadi-demo:" + ":".join(key)))
                clone = dict(session, id=clone_id, group_id=group_id,
                             token_hash=hashlib.sha256((clone_id + ":token").encode()).hexdigest(),
                             code_hash=hashlib.sha256((clone_id + ":code").encode()).hexdigest())
                clone["closed_at"] = session["closed_at"] or session["created_at"]
                clone["expires_at"] = 0
                rows["attendance_sessions"].append(clone)
                clones[key] = clone_id
        membership["group_id"] = group_id
        for consent in rows["guardian_consents"]:
            if consent["child_id"] == profile["id"] and consent["group_id"] == original["id"]:
                consent["group_id"] = group_id
        for event in rows["attendance_events"]:
            if event["child_id"] != profile["id"]:
                continue
            session = sessions[event["session_id"]]
            if session["group_id"] != original["id"]:
                raise ValueError("Unexpected demo attendance relationship")
            key = (session["id"], group_id)
            event["session_id"] = clones[key]
        moved += 1
    return moved


def load_source(path):
    path = Path(path).resolve()
    if not path.name.endswith(".demo.sqlite3") or not path.is_file():
        raise ValueError("Source must be an existing isolated .demo.sqlite3 file")
    with closing(connect_readonly(path)) as db:
        definition = schema(db)
        if db.execute("PRAGMA integrity_check").fetchone()[0] != "ok" or db.execute("PRAGMA foreign_key_check").fetchall():
            raise ValueError("Source database integrity failed")
        names = {row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        if names != set(TABLES) | EMPTY_TABLES | {"account_schema"}:
            raise ValueError("Unexpected source tables")
        for table in EMPTY_TABLES:
            if db.execute(f"SELECT count(*) FROM {table}").fetchone()[0]:
                raise ValueError("Source includes non-demo state: " + table)
        rows = {table: [dict(row) for row in db.execute(f"SELECT * FROM {table}")]
                for table in TABLES}
    accounts = rows["guardians"]
    if len(accounts) != 6 or {row["email"] for row in accounts} != EMAILS:
        raise ValueError("Expected exactly the six Ezz sample accounts")
    for account in accounts:
        if not account["email_verified"] or passwords.verify("IqtadiDemo!2026", account["password_hash"]):
            raise ValueError("Verified demo accounts must use private replacement passwords")
    admin = next(row for row in accounts if row["email"] == "admin@example.com")
    if len(rows["platform_admins"]) != 1 or rows["platform_admins"][0]["user_id"] != admin["id"]:
        raise ValueError("Unexpected sample platform-admin permissions")
    if any(not row["analysis_version"].startswith("demo-") for row in rows["attempts"]):
        raise ValueError("Only explicitly synthetic demo attempts may be imported")
    if len(rows["attempts"]) != 189 or len(rows["attendance_events"]) != 65:
        raise ValueError("Expected complete rich Ezz practice/attendance samples")
    public_codes = {hashlib.sha256(value.encode()).hexdigest() for value in
                    ("DEMOJOIN24", "demo-group-invite-token", "FAJRDEMO", "demo-attendance-token")}
    active_codes = rows["group_invites"] + [row for row in rows["attendance_sessions"]
                                           if row["id"] == "demo-live-attendance"]
    for row in active_codes:
        if {row["token_hash"], row["code_hash"]} & public_codes:
            raise ValueError("Replace publicly documented invitation/check-in codes first")
    moved = split_age_groups(rows)
    canonical = json.dumps(rows, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    fingerprint = hashlib.sha256(canonical.encode()).hexdigest()
    return rows, definition, fingerprint, moved


def snapshot(db):
    """All pre-existing rows, including sessions, tokens, audits and rate limits."""
    names = [row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")]
    result = {}
    for table in names:
        quoted = '"' + table.replace('"', '""') + '"'
        result[table] = {tuple(row) for row in db.execute("SELECT * FROM " + quoted)}
    return result


def import_demo(source, target, *, apply=False, backup=None):
    source, target = Path(source).resolve(), Path(target).resolve()
    if source == target or not target.is_file():
        raise ValueError("Target must be a different, existing account database")
    rows, definition, fingerprint, moved = load_source(source)
    with closing(connect_readonly(target)) as read:
        if schema(read) != definition:
            raise ValueError("Source and target schema columns differ")
        if read.execute("PRAGMA integrity_check").fetchone()[0] != "ok" or read.execute("PRAGMA foreign_key_check").fetchall():
            raise ValueError("Target database integrity failed")
    # The SQLite backup API captures a consistent live DB including WAL pages.
    # Take it before the writer lock; never copy a live .sqlite3 file directly.
    if apply:
        if backup is None:
            raise ValueError("Apply requires a new, explicit backup file")
        backup = Path(backup).resolve()
        if backup in {source, target}:
            raise ValueError("Backup must be separate from source and target")
        backup.parent.mkdir(parents=True, exist_ok=True)
        descriptor = os.open(backup, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        os.close(descriptor)
        with closing(connect_readonly(target)) as read, closing(sqlite3.connect(backup)) as saved:
            read.backup(saved)
            if saved.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
                raise ValueError("Backup integrity failed")
    db = sqlite3.connect(target, timeout=30)
    db.row_factory = sqlite3.Row
    try:
        db.execute("PRAGMA foreign_keys=ON")
        db.execute("BEGIN IMMEDIATE")
        # Revalidate after taking the lock in case another process migrated.
        if schema(db) != definition:
            raise ValueError("Target schema changed before import")
        existing = db.execute(
            "SELECT id FROM account_audit_events WHERE action=? AND subject_id=?",
            (ACTION, fingerprint),
        ).fetchone()
        if existing:
            # Verify immutable identities remain; users may have edited sample names.
            for row in rows["guardians"]:
                current = db.execute("SELECT email FROM guardians WHERE id=?", (row["id"],)).fetchone()
                if not current or current["email"] != row["email"]:
                    raise ValueError("Imported sample identities have changed; investigate manually")
            db.rollback()
            return {"status": "ALREADY_IMPORTED", "fingerprint": fingerprint}
        before = snapshot(db)
        for table in TABLES:
            columns = [column[1] for column in definition[table]]
            statement = f"INSERT INTO {table} ({','.join(columns)}) VALUES ({','.join('?' for _ in columns)})"
            for row in rows[table]:
                db.execute(statement, tuple(row[column] for column in columns))
        after = snapshot(db)
        if any(not original.issubset(after[table]) for table, original in before.items()):
            raise ValueError("Pre-existing data changed; refusing import")
        if db.execute("PRAGMA foreign_key_check").fetchall():
            raise ValueError("Imported relationships failed foreign-key validation")
        result = {"status": "IMPORTED" if apply else "DRY_RUN_PASS",
                  "fingerprint": fingerprint,
                  "added": {table: len(value) for table, value in rows.items()},
                  "age_memberships_corrected": moved,
                  "existing_rows_preserved": True, "foreign_keys": "PASS",
                  "mail_sent": False}
        if apply:
            db.execute("INSERT INTO account_audit_events VALUES(?,?,?,?,?,?)",
                       (str(uuid.uuid4()), None, ACTION, fingerprint, "explicit-demo-import",
                        datetime.now(timezone.utc).isoformat()))
            db.commit()
        else:
            db.rollback()
        return result
    except BaseException:
        db.rollback()
        raise
    finally:
        db.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--backup")
    args = parser.parse_args()
    print(json.dumps(import_demo(args.source, args.target, apply=args.apply, backup=args.backup)))


if __name__ == "__main__":
    main()
