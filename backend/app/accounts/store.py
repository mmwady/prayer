"""Additive SQLite schema, separate from existing demo and analysis data.

Schema v2 deliberately keeps the original ``guardians``/``children`` tables so
already-paired devices and prayer attempts remain valid.  The names are legacy;
new code treats them as accounts and practice profiles.  Family, mosque and
consent relationships live in separate many-to-many tables.
"""

import hashlib
import sqlite3
from contextlib import contextmanager
from pathlib import Path


def digest(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def _columns(db, table: str) -> set[str]:
    return {row[1] for row in db.execute(f"PRAGMA table_info({table})")}


def _ensure_column(db, table: str, name: str, definition: str) -> None:
    if name not in _columns(db, table):
        db.execute(f"ALTER TABLE {table} ADD COLUMN {name} {definition}")


def ensure_personal_profile(db, user_id: str, name: str, created_at: str) -> str:
    """Return the account's self profile, creating its private practice space."""

    existing = db.execute(
        "SELECT id FROM children WHERE account_user_id=? AND profile_kind='SELF'",
        (user_id,),
    ).fetchone()
    if existing:
        return existing["id"]
    group_id = "personal-" + user_id
    profile_id = "profile-" + user_id
    db.execute(
        """INSERT OR IGNORE INTO groups
           (id,owner_user_id,name,type,timezone,schedule,created_at)
           VALUES(?,?,?,?,?,?,?)""",
        (group_id, user_id, "تقدمي الشخصي", "PERSONAL", "Asia/Riyadh", "{}", created_at),
    )
    db.execute(
        """INSERT OR IGNORE INTO children
           (id,group_id,name,age,avatar,active,created_at,profile_kind,account_user_id,age_band,alias)
           VALUES(?,?,?,?,?,?,?,?,?,?,?)""",
        (
            profile_id,
            group_id,
            name,
            18,
            None,
            1,
            created_at,
            "SELF",
            user_id,
            "ADULT",
            None,
        ),
    )
    return profile_id


class AccountStore:
    def __init__(self, path: str):
        self.path = path
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        with self.transaction() as db:
            db.executescript("""
            CREATE TABLE IF NOT EXISTS account_schema(version INTEGER PRIMARY KEY);
            INSERT OR IGNORE INTO account_schema VALUES(1);
            CREATE TABLE IF NOT EXISTS guardians(
              id TEXT PRIMARY KEY, name TEXT NOT NULL, email TEXT NOT NULL,
              role TEXT NOT NULL CHECK(role IN ('PARENT','TEACHER')), created_at TEXT NOT NULL,
              password_hash TEXT NOT NULL, email_verified INTEGER NOT NULL DEFAULT 0);
            CREATE UNIQUE INDEX IF NOT EXISTS guardian_email ON guardians(email);
            CREATE TABLE IF NOT EXISTS email_tokens(
              token_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES guardians(id),
              kind TEXT NOT NULL, expires_at REAL NOT NULL, used_at REAL);
            CREATE TABLE IF NOT EXISTS groups(
              id TEXT PRIMARY KEY, owner_user_id TEXT NOT NULL REFERENCES guardians(id),
              name TEXT NOT NULL, type TEXT NOT NULL, timezone TEXT NOT NULL,
              schedule TEXT NOT NULL, created_at TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS children(
              id TEXT PRIMARY KEY, group_id TEXT NOT NULL REFERENCES groups(id),
              name TEXT NOT NULL, age INTEGER NOT NULL, avatar TEXT,
              active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS pairing_tokens(
              id TEXT PRIMARY KEY, child_id TEXT NOT NULL REFERENCES children(id),
              token_hash TEXT UNIQUE NOT NULL, code_hash TEXT UNIQUE NOT NULL,
              expires_at REAL NOT NULL, used_at REAL, created_by TEXT NOT NULL,
              revoked INTEGER NOT NULL DEFAULT 0);
            CREATE TABLE IF NOT EXISTS devices(
              id TEXT PRIMARY KEY, child_id TEXT NOT NULL REFERENCES children(id),
              token_hash TEXT UNIQUE NOT NULL, platform TEXT NOT NULL,
              created_at REAL NOT NULL, last_seen_at REAL NOT NULL,
              expires_at REAL NOT NULL, revoked_at REAL);
            CREATE TABLE IF NOT EXISTS guardian_sessions(
              token_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES guardians(id),
              expires_at REAL NOT NULL);
            CREATE TABLE IF NOT EXISTS attempts(
              id TEXT PRIMARY KEY, child_id TEXT NOT NULL REFERENCES children(id),
              client_attempt_id TEXT NOT NULL, prayer TEXT NOT NULL,
              performed_at TEXT NOT NULL, valid INTEGER NOT NULL,
              sequence_valid INTEGER NOT NULL, uncertain INTEGER NOT NULL,
              on_time INTEGER, confidence REAL, rakats_expected INTEGER NOT NULL,
              rakats_completed INTEGER NOT NULL, analysis_version TEXT NOT NULL,
              created_at TEXT NOT NULL, UNIQUE(child_id,client_attempt_id));
            CREATE INDEX IF NOT EXISTS attempts_child_date ON attempts(child_id,performed_at);
            CREATE TABLE IF NOT EXISTS rate_limits(
              key TEXT PRIMARY KEY, count INTEGER NOT NULL, resets_at REAL NOT NULL);
            """)
            _ensure_column(db, "guardians", "learning_stage", "TEXT NOT NULL DEFAULT 'GENERAL'")
            _ensure_column(
                db, "guardians", "accessibility_mode", "TEXT NOT NULL DEFAULT 'STANDARD'"
            )
            _ensure_column(db, "children", "profile_kind", "TEXT NOT NULL DEFAULT 'DEPENDENT'")
            _ensure_column(db, "children", "account_user_id", "TEXT")
            _ensure_column(db, "children", "age_band", "TEXT NOT NULL DEFAULT 'CHILD'")
            _ensure_column(db, "children", "alias", "TEXT")
            db.executescript(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS children_self_account
                  ON children(account_user_id) WHERE account_user_id IS NOT NULL;

                CREATE TABLE IF NOT EXISTS family_memberships(
                  family_id TEXT NOT NULL REFERENCES groups(id),
                  user_id TEXT NOT NULL REFERENCES guardians(id),
                  role TEXT NOT NULL CHECK(role IN ('OWNER','GUARDIAN','ADULT','SUPPORTER')),
                  created_at TEXT NOT NULL,
                  PRIMARY KEY(family_id,user_id));
                CREATE TABLE IF NOT EXISTS guardian_links(
                  user_id TEXT NOT NULL REFERENCES guardians(id),
                  child_id TEXT NOT NULL REFERENCES children(id),
                  authority TEXT NOT NULL CHECK(authority IN ('OWNER','GUARDIAN')),
                  created_at TEXT NOT NULL,
                  PRIMARY KEY(user_id,child_id));
                CREATE TABLE IF NOT EXISTS family_invites(
                  id TEXT PRIMARY KEY, family_id TEXT NOT NULL REFERENCES groups(id),
                  role TEXT NOT NULL CHECK(role IN ('GUARDIAN','ADULT','SUPPORTER')),
                  token_hash TEXT UNIQUE NOT NULL, code_hash TEXT UNIQUE NOT NULL,
                  expires_at REAL NOT NULL, created_by TEXT NOT NULL REFERENCES guardians(id),
                  used_by TEXT REFERENCES guardians(id), used_at REAL,
                  revoked INTEGER NOT NULL DEFAULT 0);

                CREATE TABLE IF NOT EXISTS mosques(
                  id TEXT PRIMARY KEY, name TEXT NOT NULL, city TEXT NOT NULL,
                  verified INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS mosque_staff(
                  mosque_id TEXT NOT NULL REFERENCES mosques(id),
                  user_id TEXT NOT NULL REFERENCES guardians(id),
                  role TEXT NOT NULL CHECK(role IN ('ADMIN','LEADER')),
                  verified_by TEXT, created_at TEXT NOT NULL,
                  PRIMARY KEY(mosque_id,user_id));
                CREATE TABLE IF NOT EXISTS platform_admins(
                  user_id TEXT PRIMARY KEY REFERENCES guardians(id),
                  created_at TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS mosque_leader_requests(
                  id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES guardians(id),
                  mosque_id TEXT REFERENCES mosques(id), mosque_name TEXT NOT NULL,
                  city TEXT NOT NULL, requested_role TEXT NOT NULL
                    CHECK(requested_role IN ('ADMIN','LEADER')),
                  status TEXT NOT NULL CHECK(status IN ('PENDING','APPROVED','REJECTED')),
                  note TEXT, created_at TEXT NOT NULL,
                  reviewed_by TEXT REFERENCES guardians(id), reviewed_at TEXT);
                CREATE TABLE IF NOT EXISTS mosque_groups(
                  id TEXT PRIMARY KEY, mosque_id TEXT NOT NULL REFERENCES mosques(id),
                  name TEXT NOT NULL, age_band TEXT NOT NULL, timezone TEXT NOT NULL,
                  schedule TEXT NOT NULL, created_by TEXT NOT NULL REFERENCES guardians(id),
                  active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS group_invites(
                  id TEXT PRIMARY KEY, group_id TEXT NOT NULL REFERENCES mosque_groups(id),
                  token_hash TEXT UNIQUE NOT NULL, code_hash TEXT UNIQUE NOT NULL,
                  expires_at REAL NOT NULL, created_by TEXT NOT NULL REFERENCES guardians(id),
                  revoked INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS group_memberships(
                  group_id TEXT NOT NULL REFERENCES mosque_groups(id),
                  child_id TEXT NOT NULL REFERENCES children(id), alias TEXT NOT NULL,
                  status TEXT NOT NULL CHECK(status IN ('PENDING','ACTIVE','REMOVED')),
                  joined_at TEXT NOT NULL, left_at TEXT,
                  PRIMARY KEY(group_id,child_id));
                CREATE UNIQUE INDEX IF NOT EXISTS active_group_alias
                  ON group_memberships(group_id,alias) WHERE status='ACTIVE';
                CREATE TABLE IF NOT EXISTS guardian_consents(
                  id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES guardians(id),
                  child_id TEXT NOT NULL REFERENCES children(id),
                  group_id TEXT NOT NULL REFERENCES mosque_groups(id),
                  share_practice INTEGER NOT NULL, share_attendance INTEGER NOT NULL,
                  leaderboard INTEGER NOT NULL, consented_at TEXT NOT NULL, revoked_at TEXT);
                CREATE UNIQUE INDEX IF NOT EXISTS active_guardian_consent
                  ON guardian_consents(child_id,group_id) WHERE revoked_at IS NULL;
                CREATE TABLE IF NOT EXISTS mosque_group_messages(
                  id TEXT PRIMARY KEY,
                  group_id TEXT NOT NULL REFERENCES mosque_groups(id),
                  author_profile_id TEXT NOT NULL REFERENCES children(id),
                  author_alias TEXT NOT NULL,
                  body TEXT NOT NULL,
                  parent_id TEXT REFERENCES mosque_group_messages(id),
                  created_at TEXT NOT NULL,
                  deleted_at TEXT);
                CREATE INDEX IF NOT EXISTS mosque_group_messages_group_created
                  ON mosque_group_messages(group_id,created_at);

                CREATE TABLE IF NOT EXISTS attendance_sessions(
                  id TEXT PRIMARY KEY, group_id TEXT NOT NULL REFERENCES mosque_groups(id),
                  prayer TEXT NOT NULL, prayer_day TEXT NOT NULL,
                  token_hash TEXT UNIQUE NOT NULL, code_hash TEXT UNIQUE NOT NULL,
                  expires_at REAL NOT NULL, created_by TEXT NOT NULL REFERENCES guardians(id),
                  created_at TEXT NOT NULL, closed_at TEXT);
                CREATE TABLE IF NOT EXISTS attendance_events(
                  id TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES attendance_sessions(id),
                  child_id TEXT NOT NULL REFERENCES children(id),
                  source TEXT NOT NULL CHECK(source IN ('QR','LEADER')),
                  marked_by TEXT NOT NULL, created_at TEXT NOT NULL,
                  UNIQUE(session_id,child_id));
                CREATE TABLE IF NOT EXISTS account_audit_events(
                  id TEXT PRIMARY KEY, actor_user_id TEXT, action TEXT NOT NULL,
                  subject_id TEXT, context_id TEXT, created_at TEXT NOT NULL);
                """
            )

            membership_sql = db.execute(
                "SELECT sql FROM sqlite_master WHERE type='table' AND name='group_memberships'"
            ).fetchone()[0]
            if "PENDING" not in membership_sql:
                db.executescript(
                    """
                    DROP INDEX IF EXISTS active_group_alias;
                    ALTER TABLE group_memberships RENAME TO group_memberships_v2_old;
                    CREATE TABLE group_memberships(
                      group_id TEXT NOT NULL REFERENCES mosque_groups(id),
                      child_id TEXT NOT NULL REFERENCES children(id), alias TEXT NOT NULL,
                      status TEXT NOT NULL CHECK(status IN ('PENDING','ACTIVE','REMOVED')),
                      joined_at TEXT NOT NULL, left_at TEXT,
                      PRIMARY KEY(group_id,child_id));
                    INSERT INTO group_memberships
                      SELECT * FROM group_memberships_v2_old;
                    DROP TABLE group_memberships_v2_old;
                    CREATE UNIQUE INDEX active_group_alias
                      ON group_memberships(group_id,alias) WHERE status='ACTIVE';
                    """
                )

            # Best-effort migration for v1 families. Classroom ownership is not
            # converted into guardianship: a teacher must never become a guardian.
            db.execute(
                """INSERT OR IGNORE INTO family_memberships(family_id,user_id,role,created_at)
                   SELECT id,owner_user_id,'OWNER',created_at FROM groups WHERE type='FAMILY'"""
            )
            db.execute(
                """INSERT OR IGNORE INTO guardian_links(user_id,child_id,authority,created_at)
                   SELECT g.owner_user_id,c.id,'OWNER',c.created_at
                   FROM children c JOIN groups g ON g.id=c.group_id
                   WHERE g.type='FAMILY' AND c.profile_kind='DEPENDENT'"""
            )
            for user in db.execute("SELECT id,name,created_at FROM guardians").fetchall():
                ensure_personal_profile(db, user["id"], user["name"], user["created_at"])
            db.execute("INSERT OR REPLACE INTO account_schema(version) VALUES(2)")

            # Version 3 combines both branches' distinct version-2 schemas.
            # Nullable counters preserve old attempts without inventing scores.
            columns = {r["name"] for r in db.execute("PRAGMA table_info(attempts)")}
            for name, kind in [
                ("movements_detected", "INTEGER"),
                ("movements_expected", "INTEGER"),
                ("movement_score", "REAL"),
            ]:
                if name not in columns:
                    db.execute(f"ALTER TABLE attempts ADD COLUMN {name} {kind}")
            db.execute("INSERT OR IGNORE INTO account_schema VALUES(3)")

    @contextmanager
    def transaction(self):
        db = sqlite3.connect(self.path, timeout=15)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA foreign_keys=ON")
        try:
            db.execute("BEGIN IMMEDIATE")
            yield db
            db.commit()
        except BaseException:
            db.rollback()
            raise
        finally:
            db.close()
