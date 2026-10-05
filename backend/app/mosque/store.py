"""SQLite transactions serialize holds across threads/processes sharing the same file."""
import hashlib
import json
import secrets
import sqlite3
from contextlib import contextmanager
from pathlib import Path
from .seed import seed

class Store:
    def __init__(self,path):
        self.path=str(path)
        Path(path).parent.mkdir(parents=True,exist_ok=True)
        with sqlite3.connect(self.path) as db:
            db.execute('CREATE TABLE IF NOT EXISTS sessions (token TEXT PRIMARY KEY, state TEXT NOT NULL)')
    def create(self):
        token=secrets.token_urlsafe(32)
        with sqlite3.connect(self.path) as db:
            db.execute('INSERT INTO sessions VALUES (?,?)',(self.key(token),json.dumps(seed(),ensure_ascii=False)))
        return token
    @staticmethod
    def key(token):
        return hashlib.sha256(token.encode()).hexdigest()
    @contextmanager
    def transaction(self,token):
        db=sqlite3.connect(self.path,timeout=15)
        try:
            db.execute('BEGIN IMMEDIATE')
            row=db.execute('SELECT state FROM sessions WHERE token=?',(self.key(token),)).fetchone()
            if not row: raise PermissionError('جلسة ديمو غير صالحة')
            state=json.loads(row[0])
            yield state
            db.execute('UPDATE sessions SET state=? WHERE token=?',(json.dumps(state,ensure_ascii=False),self.key(token)))
            db.commit()
        except BaseException:
            db.rollback()
            raise
        finally:
            db.close()
