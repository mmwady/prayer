"""Additive SQLite schema, separate from existing demo and analysis data."""

import hashlib
import sqlite3
from contextlib import contextmanager
from pathlib import Path


def digest(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


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
