"""Real Argon2, SQLite and HTTP boundaries; only email delivery is captured."""

from datetime import date, datetime, timezone
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from app.accounts import auth
from app.accounts.boundary import AccountBoundary
from app.accounts.api import router, store
from app.accounts.domain import PrayerTimeService, progress
from app.accounts.store import digest
from app.config import get_settings

BASE = "/api/v1/accounts"
HEADERS = {"X-Iqtadi-Account": "1"}
PASSWORD = "correct horse battery staple"


@pytest.fixture
def env(tmp_path, monkeypatch):
    monkeypatch.setenv("ACCOUNT_DB", str(tmp_path / "accounts.sqlite3"))
    monkeypatch.setenv("ACCOUNT_ALLOWED_ORIGINS", '["http://testserver"]')
    monkeypatch.setenv("ACCOUNT_SECURE_COOKIES", "false")
    get_settings.cache_clear()
    messages = []
    monkeypatch.setattr(
        auth, "send_email", lambda address, kind, token: messages.append((address, kind, token))
    )
    app = FastAPI()
    app.add_middleware(AccountBoundary)
    app.include_router(router)
    client = TestClient(app, headers=HEADERS)
    yield client, messages, store()
    get_settings.cache_clear()


def parent(env, name="Mohamed", role="PARENT"):
    client, emails, db = env
    address = name.lower() + "@example.com"
    assert (
        client.post(
            BASE + "/auth/signup",
            json={"name": name, "email": address, "password": PASSWORD, "role": role},
        ).status_code
        == 200
    )
    raw = emails[-1][2]
    assert client.post(BASE + "/auth/verify", json={"token": raw}).status_code == 200
    r = client.post(BASE + "/session", json={"email": address, "password": PASSWORD})
    assert r.status_code == 200, r.text
    return {**HEADERS, "Authorization": "Bearer " + r.json()["session_token"]}


def setup_child(env):
    client, _, _ = env
    owner = parent(env)
    group = client.post(BASE + "/groups", json={"name": "Family"}, headers=owner).json()["id"]
    child = client.post(
        BASE + f"/groups/{group}/children", json={"name": "Omar", "age": 11}, headers=owner
    ).json()["id"]
    return owner, group, child


def pair(env, owner, child, platform="android"):
    client, _, _ = env
    token = client.post(BASE + f"/children/{child}/pairing", headers=owner).json()
    r = client.post(
        BASE + "/pairing/redeem",
        json={"token": token["qr_payload"], "platform": platform},
        headers={**HEADERS, "X-Iqtadi-Platform": platform},
    )
    assert r.status_code == 200, r.text
    return token, r.json()


def attempt_payload(key="one", prayer="fajr"):
    n = {"fajr": 2, "dhuhr": 4, "asr": 4, "maghrib": 3, "isha": 4}[prayer]
    return {
        "client_attempt_id": key,
        "prayer": prayer,
        "performed_at": datetime.now(timezone.utc).isoformat(),
        "valid": True,
        "sequence_valid": True,
        "uncertain": False,
        "rakats_expected": n,
        "rakats_completed": n,
        "analysis_version": "local-v1",
    }


def test_account_boundary_size_and_private_cache(env):
    client, _, _ = env
    response = client.post(
        BASE + "/auth/signup", content=b"x" * 17000, headers={"Content-Type": "application/json"}
    )
    assert response.status_code == 413
    assert response.headers["cache-control"] == "no-store"
    assert client.get(BASE + "/groups").headers["cache-control"] == "no-store"
    assert client.get(BASE + "/auth/action").headers["referrer-policy"] == "no-referrer"


def test_teacher_group_type_and_role_cannot_change_at_login(env):
    client, _, _ = env
    owner = parent(env, "Teacher", "TEACHER")
    client.post(BASE + "/groups", headers=owner, json={"name": "Class"})
    assert client.get(BASE + "/groups", headers=owner).json()[0]["type"] == "CLASSROOM"
    assert (
        client.post(
            BASE + "/session",
            json={"email": "teacher@example.com", "password": PASSWORD, "role": "PARENT"},
        ).status_code
        == 422
    )


def test_inconsistent_final_results_rejected(env):
    client, _, _ = env
    owner, _, child = setup_child(env)
    _, session = pair(env, owner, child)
    h = {**HEADERS, "Authorization": "Bearer " + session["session_token"]}
    assert (
        client.post(
            BASE + "/attempts", headers=h, json=attempt_payload() | {"uncertain": True}
        ).status_code
        == 422
    )
    assert (
        client.post(
            BASE + "/attempts", headers=h, json=attempt_payload() | {"rakats_completed": 1}
        ).status_code
        == 422
    )


def test_backend_auth_hash_verify_reset_and_session_invalidation(env):
    client, emails, database = env
    body = {"name": "Parent", "email": "parent@example.com", "password": PASSWORD, "role": "PARENT"}
    assert client.post(BASE + "/auth/signup", json=body).status_code == 200
    with database.transaction() as db:
        row = db.execute("SELECT * FROM guardians").fetchone()
        assert (
            row["password_hash"].startswith("$argon2id$") and PASSWORD not in row["password_hash"]
        )
    assert (
        client.post(
            BASE + "/session", json={"email": body["email"], "password": PASSWORD}
        ).status_code
        == 403
    )
    verify = emails[-1][2]
    assert client.post(BASE + "/auth/verify", json={"token": verify}).status_code == 200
    assert client.post(BASE + "/auth/verify", json={"token": verify}).status_code == 400
    r = client.post(BASE + "/session", json={"email": body["email"], "password": PASSWORD})
    h = {**HEADERS, "Authorization": "Bearer " + r.json()["session_token"]}
    assert client.get(BASE + "/me", headers=h).status_code == 200
    assert "password_hash" not in client.get(BASE + "/me", headers=h).json()
    client.post(BASE + "/auth/recover", json={"email": body["email"]})
    raw = emails[-1][2]
    assert (
        client.post(
            BASE + "/auth/reset", json={"token": raw, "password": "new long password!"}
        ).status_code
        == 200
    )
    assert client.get(BASE + "/me", headers=h).status_code == 401
    assert (
        client.post(
            BASE + "/auth/reset", json={"token": raw, "password": "new long password!"}
        ).status_code
        == 400
    )
    assert (
        client.post(
            BASE + "/session", json={"email": body["email"], "password": PASSWORD}
        ).status_code
        == 401
    )


def test_expired_email_and_wrong_password(env):
    client, emails, db = env
    parent(env)
    client.post(BASE + "/auth/recover", json={"email": "mohamed@example.com"})
    raw = emails[-1][2]
    with db.transaction() as conn:
        conn.execute("UPDATE email_tokens SET expires_at=0 WHERE token_hash=?", (digest(raw),))
    assert (
        client.post(BASE + "/auth/reset", json={"token": raw, "password": PASSWORD}).status_code
        == 400
    )
    assert (
        client.post(
            BASE + "/session",
            json={"email": "mohamed@example.com", "password": "wrong long password"},
        ).status_code
        == 401
    )


@pytest.mark.parametrize("kind", ["invalid", "expired", "reused", "revoked"])
def test_pairing_security(env, kind):
    client, _, db = env
    owner, group, child = setup_child(env)
    payload = client.post(BASE + f"/children/{child}/pairing", headers=owner).json()
    value = payload["code"]
    if kind == "invalid":
        value = "WRONGCODE123"
    if kind == "expired":
        with db.transaction() as conn:
            conn.execute("UPDATE pairing_tokens SET expires_at=0")
    if kind == "revoked":
        client.post(BASE + f"/children/{child}/pairing", headers=owner)
    if kind == "reused":
        assert (
            client.post(
                BASE + "/pairing/redeem", json={"token": value, "platform": "android"}
            ).status_code
            == 200
        )
    assert (
        client.post(
            BASE + "/pairing/redeem", json={"token": value, "platform": "android"}
        ).status_code
        == 400
    )


def test_ownership_and_unauthenticated_dashboard(env):
    client, _, _ = env
    owner, group, child = setup_child(env)
    stranger = parent(env, "Other")
    assert client.get(BASE + "/groups").status_code == 401
    assert client.get(BASE + f"/groups/{group}/progress").status_code == 401
    for path in [f"/groups/{group}/progress", f"/children/{child}/devices"]:
        assert client.get(BASE + path, headers=stranger).status_code == 404
    assert client.post(BASE + f"/children/{child}/pairing", headers=stranger).status_code == 404
    assert (
        client.post(
            BASE + f"/groups/{group}/children", headers=stranger, json={"name": "X", "age": 11}
        ).status_code
        == 404
    )


def test_device_scope_revocation_and_idempotency(env):
    client, _, database = env
    owner, group, child = setup_child(env)
    _, session = pair(env, owner, child)
    h = {**HEADERS, "Authorization": "Bearer " + session["session_token"]}
    payload = attempt_payload()
    assert client.post(BASE + "/attempts", headers=h, json=payload).status_code == 200
    assert client.post(BASE + "/attempts", headers=h, json=payload).json()["duplicate"]
    assert (
        client.post(
            BASE + "/attempts", headers=h, json=payload | {"child_id": "different-child"}
        ).status_code
        == 422
    )
    with database.transaction() as db:
        assert db.execute("SELECT count(*) FROM attempts").fetchone()[0] == 1
        assert db.execute("SELECT child_id FROM attempts").fetchone()[0] == child
    assert client.get(BASE + f"/groups/{group}/progress", headers=h).status_code == 401
    assert (
        client.delete(
            BASE + f"/children/{child}/devices/{session['device_id']}", headers=owner
        ).status_code
        == 200
    )
    assert (
        client.post(BASE + "/attempts", headers=h, json=attempt_payload("two")).status_code == 401
    )


@pytest.mark.parametrize(
    "field", ["image", "video", "frame", "landmarks", "features", "tensor", "predictions"]
)
def test_visual_data_rejected(env, field):
    client, _, _ = env
    owner, _, child = setup_child(env)
    _, session = pair(env, owner, child)
    assert (
        client.post(
            BASE + "/attempts",
            headers={**HEADERS, "Authorization": "Bearer " + session["session_token"]},
            json=attempt_payload() | {field: [1, 2, 3]},
        ).status_code
        == 422
    )


def test_web_httponly_cookie_persistence_csrf_and_logout(env):
    client, _, _ = env
    parent(env)
    h = {**HEADERS, "X-Iqtadi-Platform": "web", "Origin": "http://testserver"}
    r = client.post(
        BASE + "/session", headers=h, json={"email": "mohamed@example.com", "password": PASSWORD}
    )
    assert "session_token" not in r.json()
    assert "HttpOnly" in r.headers["set-cookie"] and "SameSite=strict" in r.headers["set-cookie"]
    assert client.get(BASE + "/me", headers=h).status_code == 200
    assert (
        client.get(BASE + "/me", headers=h | {"Origin": "https://evil.invalid"}).status_code == 403
    )
    assert client.get(BASE + "/me", headers={"X-Iqtadi-Account": "0"}).status_code == 403
    assert client.delete(BASE + "/session", headers=h).status_code == 200
    assert client.get(BASE + "/me", headers=h).status_code == 401


def test_manual_code_and_web_device_cookie(env):
    client, _, _ = env
    owner, _, child = setup_child(env)
    code = client.post(BASE + f"/children/{child}/pairing", headers=owner).json()["code"]
    r = client.post(
        BASE + "/pairing/redeem",
        headers={**HEADERS, "X-Iqtadi-Platform": "web"},
        json={"token": code, "platform": "web"},
    )
    assert r.status_code == 200 and "session_token" not in r.json()
    assert client.get(BASE + "/device").json()["child_id"] == child
    assert client.post(BASE + "/attempts", json=attempt_payload()).status_code == 200
    assert client.delete(BASE + "/device").status_code == 200
    assert client.post(BASE + "/attempts", json=attempt_payload("new")).status_code == 401


def test_no_double_points_streak_and_future_windows():
    schedule = {
        "from": "2026-10-01",
        "until": "2026-10-07",
        "fajr": "05:00",
        "sunrise": "06:00",
        "dhuhr": "12:00",
        "asr": "15:00",
        "maghrib": "18:00",
        "isha": "19:00",
    }
    timing = PrayerTimeService("UTC", schedule)
    rows = []
    for day in (3, 4, 5):
        for prayer in ("fajr", "dhuhr", "asr", "maghrib", "isha"):
            rows.append(
                {
                    "prayer": prayer,
                    "performed_at": f"2026-10-0{day}T{schedule[prayer]}:00+00:00",
                    "valid": 1,
                    "sequence_valid": 1,
                    "uncertain": 0,
                    "on_time": 1,
                }
            )
    rows += rows[:5]
    p = progress(rows, timing, date(2026, 10, 5), datetime(2026, 10, 5, 21, tzinfo=timezone.utc))
    assert p["points"] == 38 and p["weekly_points"] == 114 and p["streak"] == 3
    empty = progress([], timing, date(2026, 10, 5), datetime(2026, 10, 5, 13, tzinfo=timezone.utc))
    assert empty["states"]["asr"] == "PENDING" and empty["states"]["fajr"] == "NO_ATTEMPT"
    assert timing.on_time(datetime(2026, 10, 5, 6, tzinfo=timezone.utc), "fajr") is False
    assert timing.day_for(datetime(2026, 10, 6, 1, tzinfo=timezone.utc), "isha") == date(
        2026, 10, 5
    )
    assert timing.on_time(datetime(2026, 11, 1, 12, tzinfo=timezone.utc), "dhuhr") is None


def test_uncertainty_never_scores_and_deactivation_revokes(env):
    client, _, _ = env
    owner, group, child = setup_child(env)
    _, session = pair(env, owner, child)
    h = {**HEADERS, "Authorization": "Bearer " + session["session_token"]}
    payload = attempt_payload() | {"valid": False, "sequence_valid": False, "uncertain": True}
    assert client.post(BASE + "/attempts", headers=h, json=payload).status_code == 200
    report = client.get(BASE + f"/groups/{group}/progress", headers=owner).json()["children"][0]
    assert report["points"] == 0 and report["states"]["fajr"] == "UNCERTAIN"
    assert (
        client.put(
            BASE + f"/children/{child}",
            headers=owner,
            json={"name": "Omar", "age": 11, "active": False},
        ).status_code
        == 200
    )
    assert (
        client.post(BASE + "/attempts", headers=h, json=attempt_payload("other")).status_code == 401
    )


def test_rate_limit_invalid_codes_commits(env):
    client, _, _ = env
    for _ in range(10):
        assert (
            client.post(
                BASE + "/pairing/redeem", json={"token": "invalid-value", "platform": "web"}
            ).status_code
            == 400
        )
    assert (
        client.post(
            BASE + "/pairing/redeem", json={"token": "invalid-value", "platform": "web"}
        ).status_code
        == 429
    )


def test_movement_score_persists_and_retries_without_success_points(env):
    client, _, database = env
    owner, group, child = setup_child(env)
    _, session = pair(env, owner, child)
    headers = {**HEADERS, "Authorization": "Bearer " + session["session_token"]}
    payload = attempt_payload() | {
        "valid": False,
        "sequence_valid": False,
        "uncertain": True,
        "movements_detected": 12,
        "movements_expected": 16,
        "movement_score": 75.0,
    }
    assert client.post(BASE + "/attempts", headers=headers, json=payload).status_code == 200
    assert client.post(BASE + "/attempts", headers=headers, json=payload).json()["duplicate"]
    with database.transaction() as db:
        row = dict(db.execute("SELECT * FROM attempts WHERE child_id=?", (child,)).fetchone())
        assert (row["movements_detected"], row["movements_expected"], row["movement_score"]) == (
            12,
            16,
            75,
        )
        assert db.execute("SELECT count(*) FROM attempts").fetchone()[0] == 1
    report = client.get(BASE + f"/groups/{group}/progress", headers=owner).json()["children"][0]
    assert report["movement_score"] == report["weekly_movement_score"] == 75
    assert report["movement_results"]["fajr"]["uncertain"] is True
    assert report["points"] == 0 and report["states"]["fajr"] == "UNCERTAIN"
    # Older queued summaries remain valid and have no fabricated score.
    assert (
        client.post(BASE + "/attempts", headers=headers, json=attempt_payload("legacy")).status_code
        == 200
    )
    with database.transaction() as db:
        assert (
            db.execute(
                "SELECT movement_score FROM attempts WHERE client_attempt_id='legacy'"
            ).fetchone()[0]
            is None
        )


@pytest.mark.parametrize(
    "patch",
    [
        {"movements_detected": 17},
        {"movements_expected": 15},
        {"movement_score": 80},
        {"movement_score": None},
        {"movements_detected": -1},
        {"movements_detected": 12.5},
    ],
)
def test_movement_counts_and_percentage_are_validated(patch):
    from pydantic import ValidationError
    from app.accounts.api import AttemptBody

    payload = attempt_payload() | {
        "valid": False,
        "sequence_valid": False,
        "uncertain": True,
        "movements_detected": 12,
        "movements_expected": 16,
        "movement_score": 75,
    }
    AttemptBody.model_validate(payload)
    with pytest.raises(ValidationError):
        AttemptBody.model_validate(payload | patch)


def test_weekly_score_weights_movements_and_uses_best_attempt_per_prayer_day():
    timing = PrayerTimeService("UTC", {})
    base = {"valid": False, "sequence_valid": False, "uncertain": True, "on_time": None}
    rows = [
        base
        | {
            "prayer": prayer,
            "performed_at": stamp,
            "movements_detected": detected,
            "movements_expected": expected,
        }
        for prayer, stamp, detected, expected in [
            ("fajr", "2026-10-05T04:00:00+00:00", 12, 16),
            ("fajr", "2026-10-05T05:00:00+00:00", 10, 16),
            ("dhuhr", "2026-10-05T12:00:00+00:00", 24, 29),
            ("fajr", "2026-10-04T04:00:00+00:00", 8, 16),
        ]
    ]
    p = progress(rows, timing, date(2026, 10, 5))
    assert (p["movements_detected"], p["movements_expected"], p["movement_score"]) == (36, 45, 80)
    assert (
        p["weekly_movements_detected"],
        p["weekly_movements_expected"],
        p["weekly_movement_score"],
    ) == (44, 61, 72.13)
    assert p["weekly_points"] == 0 and p["valid_prayers"] == 0
    assert progress([], timing, date(2026, 10, 5))["weekly_movement_score"] is None


def test_leaderboard_uses_score_to_break_equal_points(env):
    client, _, _ = env
    owner, group, child = setup_child(env)
    second = client.post(
        BASE + f"/groups/{group}/children", headers=owner, json={"name": "Ziad", "age": 10}
    ).json()["id"]
    for index, (child_id, detected) in enumerate([(child, 8), (second, 12)]):
        _, session = pair(env, owner, child_id)
        payload = attempt_payload(str(index)) | {
            "valid": False,
            "sequence_valid": False,
            "uncertain": True,
            "movements_detected": detected,
            "movements_expected": 16,
            "movement_score": detected * 100 / 16,
        }
        assert (
            client.post(
                BASE + "/attempts",
                headers={**HEADERS, "Authorization": "Bearer " + session["session_token"]},
                json=payload,
            ).status_code
            == 200
        )
    board = client.get(BASE + f"/groups/{group}/progress", headers=owner).json()["leaderboard"]
    assert [r["id"] for r in board] == [second, child]
    assert [r["weekly_points"] for r in board] == [0, 0]


def test_schema_v2_preserves_v1_attempts_and_is_idempotent(tmp_path):
    import sqlite3
    from app.accounts.store import AccountStore

    path = str(tmp_path / "legacy.sqlite3")
    with sqlite3.connect(path) as db:
        db.execute(
            "CREATE TABLE attempts (id TEXT PRIMARY KEY, child_id TEXT, client_attempt_id TEXT, prayer TEXT, performed_at TEXT, valid INTEGER, sequence_valid INTEGER, uncertain INTEGER, on_time INTEGER, confidence REAL, rakats_expected INTEGER, rakats_completed INTEGER, analysis_version TEXT, created_at TEXT)"
        )
        db.execute(
            "INSERT INTO attempts VALUES('old','child','old','fajr','2026-10-05T04:00:00+00:00',1,1,0,NULL,NULL,2,2,'legacy','2026-10-05')"
        )
    AccountStore(path)
    with AccountStore(path).transaction() as db:
        row = dict(db.execute("SELECT * FROM attempts").fetchone())
        assert row["id"] == "old" and row["valid"] == 1
        assert row["movement_score"] is None and row["movements_detected"] is None
        assert db.execute("SELECT max(version) FROM account_schema").fetchone()[0] == 2
