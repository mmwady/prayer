"""Operator import: preserve existing identities and reject partial sample writes."""

import contextlib
import io
import json
import shutil
import sqlite3
import sys

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.accounts import api, community
from app.accounts.auth import passwords
from app.accounts.boundary import AccountBoundary
from app.accounts.store import AccountStore, digest, ensure_personal_profile
from app.config import get_settings
from tools import seed_account_demo
from tools.import_account_demo import import_demo, snapshot
from tools.prepare_account_demo_import import prepare_demo
from tools import prepare_account_demo_import

MEMBER_PASSWORD = "Private sample password for focused tests!"
ADMIN_PASSWORD = "Separate admin password for focused tests!"
BASE = "/api/v1/accounts"


@pytest.fixture(scope="module")
def source_template(tmp_path_factory):
    path = tmp_path_factory.mktemp("rich-source") / "clean.demo.sqlite3"
    old_args = sys.argv
    try:
        sys.argv = ["seed", "--db", str(path), "--password", MEMBER_PASSWORD]
        with contextlib.redirect_stdout(io.StringIO()):
            seed_account_demo.main()
    finally:
        sys.argv = old_args
    with sqlite3.connect(path) as db:
        db.execute("UPDATE guardians SET password_hash=? WHERE email='admin@example.com'",
                   (passwords.hash(ADMIN_PASSWORD),))
        db.execute("UPDATE group_invites SET token_hash=?,code_hash=?",
                   (digest("private-test-invite-token"), digest("private-test-invite-code")))
        db.execute("UPDATE attendance_sessions SET token_hash=?,code_hash=? WHERE id='demo-live-attendance'",
                   (digest("private-test-attendance-token"), digest("private-test-attendance-code")))
    return path


@pytest.fixture
def databases(tmp_path, source_template):
    source = tmp_path / "source.demo.sqlite3"
    shutil.copyfile(source_template, source)
    target = tmp_path / "live.sqlite3"
    store = AccountStore(str(target))
    with store.transaction() as db:
        db.execute("INSERT INTO guardians(id,name,email,role,created_at,password_hash,email_verified) VALUES(?,?,?,?,?,?,?)",
                   ("real-user", "Existing user", "real@valid.test", "PARENT", "2026-01-01",
                    passwords.hash("Existing private password!"), 1))
        ensure_personal_profile(db, "real-user", "Existing user", "2026-01-01")
        db.execute("INSERT INTO guardian_sessions VALUES('real-session','real-user',9999999999)")
        db.execute("INSERT INTO devices VALUES('real-device','profile-real-user','real-device-token','web',1,1,9999999999,NULL)")
        before = snapshot(db)
    return source, target, tmp_path / "backup.sqlite3", before


def state(target):
    with sqlite3.connect(target) as db:
        return snapshot(db)


def test_dry_run_and_apply_preserve_real_user_sessions_and_history(databases):
    source, target, backup, before = databases
    preview = import_demo(source, target)
    assert preview["status"] == "DRY_RUN_PASS"
    assert state(target) == before
    result = import_demo(source, target, apply=True, backup=backup)
    assert result["added"]["guardians"] == 6
    assert result["added"]["attempts"] == 189
    assert result["added"]["attendance_events"] == 65
    assert result["added"]["mosque_groups"] == 4
    assert result["added"]["attendance_sessions"] == 80
    assert result["age_memberships_corrected"] == 2
    after = state(target)
    assert all(rows <= after[table] for table, rows in before.items())
    assert state(backup) == before
    assert import_demo(source, target)["status"] == "ALREADY_IMPORTED"
    assert state(target) == after
    with sqlite3.connect(target) as db:
        assert db.execute("PRAGMA foreign_key_check").fetchall() == []
        assert db.execute("SELECT count(*) FROM group_memberships m JOIN children c ON c.id=m.child_id JOIN mosque_groups g ON g.id=m.group_id WHERE c.age_band<>g.age_band").fetchone()[0] == 0
        assert db.execute("SELECT count(*) FROM attendance_events e JOIN attendance_sessions s ON s.id=e.session_id LEFT JOIN group_memberships m ON m.group_id=s.group_id AND m.child_id=e.child_id WHERE m.child_id IS NULL").fetchone()[0] == 0


def test_conflict_rolls_back_earlier_inserted_tables(databases):
    source, target, backup, _ = databases
    with sqlite3.connect(target) as db:
        db.execute("INSERT INTO mosques VALUES('demo-mosque','Existing mosque','City',1,'2026-01-01')")
    before = state(target)
    with pytest.raises(sqlite3.IntegrityError):
        import_demo(source, target, apply=True, backup=backup)
    assert state(target) == before
    assert state(backup) == before


@pytest.mark.parametrize("problem", ["session", "default_password", "default_code", "real_email", "missing_attempt", "schema"])
def test_unsafe_source_is_rejected_without_target_changes(databases, problem):
    source, target, backup, before = databases
    with sqlite3.connect(source) as db:
        user = db.execute("SELECT id FROM guardians LIMIT 1").fetchone()[0]
        if problem == "session":
            db.execute("INSERT INTO guardian_sessions VALUES('private-token',?,9999999999)", (user,))
        elif problem == "default_password":
            db.execute("UPDATE guardians SET password_hash=? WHERE id=?", (passwords.hash("IqtadiDemo!2026"), user))
        elif problem == "default_code":
            db.execute("UPDATE group_invites SET code_hash=?", (digest("DEMOJOIN24"),))
        elif problem == "real_email":
            db.execute("UPDATE guardians SET email='real@valid.test' WHERE id=?", (user,))
        elif problem == "missing_attempt":
            db.execute("DELETE FROM attempts WHERE id=(SELECT id FROM attempts LIMIT 1)")
        else:
            db.execute("DELETE FROM account_schema WHERE version=4")
    with pytest.raises(ValueError):
        import_demo(source, target, apply=True, backup=backup)
    assert state(target) == before
    assert not backup.exists()


def test_requires_new_backup_and_distinct_existing_target(databases):
    source, target, backup, before = databases
    with pytest.raises(ValueError):
        import_demo(source, source)
    with pytest.raises(ValueError):
        import_demo(source, target, apply=True)
    backup.write_text("preserve existing backup")
    with pytest.raises(FileExistsError):
        import_demo(source, target, apply=True, backup=backup)
    assert backup.read_text() == "preserve existing backup"
    assert state(target) == before


def test_imported_real_api_permissions_family_history_and_mosque_rankings(databases, monkeypatch):
    source, target, backup, _ = databases
    import_demo(source, target, apply=True, backup=backup)
    monkeypatch.setenv("ACCOUNT_DB", str(target))
    monkeypatch.setenv("ACCOUNT_SECURE_COOKIES", "false")
    get_settings.cache_clear()
    app = FastAPI()
    app.add_middleware(AccountBoundary)
    app.include_router(api.router)
    app.include_router(community.router)
    try:
        with TestClient(app, headers={"X-Iqtadi-Account": "1"}) as client:
            def login(email, password=MEMBER_PASSWORD):
                response = client.post(BASE + "/session", json={"email": email, "password": password})
                assert response.status_code == 200, response.text
                return {"Authorization": "Bearer " + response.json()["session_token"]}

            owner = login("demo@example.com")
            overview = client.get(BASE + "/overview", headers=owner).json()
            assert len(overview["families"]) == 2
            assert not overview["is_platform_admin"]
            family = client.get(BASE + "/families/demo-family", headers=owner)
            assert family.status_code == 200
            board = client.get(BASE + "/families/demo-family/progress", headers=owner)
            assert board.status_code == 200 and board.json()["leaderboard"]
            assert client.get(BASE + "/admin/mosque-leader-requests", headers=owner).status_code == 403
            leader = login("sheikh@example.com")
            assert client.get(BASE + "/families/demo-family", headers=leader).status_code == 404
            for group in ("demo-youth-group", "demo-age-child_5_9", "demo-age-teen_14_17", "demo-adult-group"):
                response = client.get(BASE + f"/mosque-groups/{group}/dashboard", headers=leader)
                assert response.status_code == 200, response.text
                assert response.json()["practice_leaderboard"]
                assert response.json()["attendance_leaderboard"]
                attendance = response.json()["attendance_leaderboard"][0]["attendance"]
                if group == "demo-age-child_5_9":
                    assert attendance == {"attended": 14, "eligible": 22, "rate": round(14 / 22, 4)}
                elif group == "demo-age-teen_14_17":
                    assert attendance == {"attended": 11, "eligible": 22, "rate": round(11 / 22, 4)}
            admin = login("admin@example.com", ADMIN_PASSWORD)
            assert client.get(BASE + "/admin/mosque-leader-requests", headers=admin).status_code == 200
            assert client.get(BASE + "/overview", headers=admin).json()["is_platform_admin"]
            assert client.post(BASE + "/session", json={"email": "demo@example.com", "password": "IqtadiDemo!2026"}).status_code == 401
    finally:
        get_settings.cache_clear()


@pytest.mark.parametrize("leading_dash", [False, True])
def test_private_preparation_normalized_codes_and_existing_api_contract(tmp_path, monkeypatch, capsys, leading_dash):
    if leading_dash:
        original = prepare_account_demo_import.secrets.token_urlsafe
        monkeypatch.setattr(prepare_account_demo_import.secrets, "token_urlsafe", lambda n: "-" + original(n))
    source = tmp_path / "private.demo.sqlite3"
    credentials = tmp_path / "credentials.private.json"
    summary = prepare_demo(source, credentials)
    private = json.loads(credentials.read_text(encoding="utf-8"))
    assert capsys.readouterr().out == ""
    owner = next(account for account in private["accounts"] if account["email"] == "demo@example.com")
    admin = next(account for account in private["accounts"] if account["email"] == "admin@example.com")
    assert owner["password"] != admin["password"]
    assert all("تجريبي" in account["name"] for account in private["accounts"])
    assert summary["added"]["attempts"] == 189 and not summary["mail_sent"]
    for key in ("youth_join_code", "today_youth_attendance_code"):
        assert private[key] == private[key].upper().replace(" ", "").replace("-", "")
    with pytest.raises(FileExistsError):
        prepare_demo(source, credentials)
    target = tmp_path / "target.sqlite3"
    AccountStore(str(target))
    import_demo(source, target, apply=True, backup=tmp_path / "before.sqlite3")
    monkeypatch.setenv("ACCOUNT_DB", str(target))
    get_settings.cache_clear()
    app = FastAPI()
    app.add_middleware(AccountBoundary)
    app.include_router(api.router)
    app.include_router(community.router)
    try:
        with TestClient(app, headers={"X-Iqtadi-Account": "1"}) as client:
            session = client.post(BASE + "/session", json={"email": owner["email"], "password": owner["password"]})
            assert session.status_code == 200
            headers = {"Authorization": "Bearer " + session.json()["session_token"]}
            family = client.get(BASE + "/families/demo-family", headers=headers).json()
            young = next(child for child in family["dependents"] if child["age_band"] == "CHILD_5_9")
            rejected = client.post(BASE + "/mosque-groups/join", headers=headers,
                                   json={"token": private["youth_join_code"], "profile_id": young["id"], "alias": "Test alias"})
            # Code resolves successfully; age validation blocks before any write.
            assert rejected.status_code == 400 and rejected.json()["detail"] == "CHILD_AGE_GROUP_MISMATCH"
            device_headers = {"Authorization": "Bearer " + session.json()["practice_session_token"]}
            check_in = client.post(BASE + "/attendance/check-in", headers=device_headers,
                                   json={"token": private["today_youth_attendance_code"]})
            # Code resolves successfully; this adult is not a consented child.
            assert check_in.status_code == 403 and check_in.json()["detail"] == "ATTENDANCE_CONSENT_REQUIRED"
    finally:
        get_settings.cache_clear()
