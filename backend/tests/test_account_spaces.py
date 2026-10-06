"""Unified accounts, family levels, guardian consent and mosque attendance."""

import uuid
from datetime import date, datetime, timezone

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.accounts import auth
from app.accounts.api import router as account_router
from app.accounts.api import store
from app.accounts.boundary import AccountBoundary
from app.accounts.community import router as spaces_router
from app.config import get_settings

BASE = "/api/v1/accounts"
HEADERS = {"X-Iqtadi-Account": "1", "X-Iqtadi-Platform": "android"}
PASSWORD = "Iqtadi test password!"


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
    app.include_router(account_router)
    app.include_router(spaces_router)
    client = TestClient(app, headers=HEADERS)
    yield client, messages, store()
    get_settings.cache_clear()


def signup(env, name, email, **extra):
    client, messages, _ = env
    response = client.post(
        BASE + "/auth/signup",
        json={"name": name, "email": email, "password": PASSWORD, **extra},
    )
    assert response.status_code == 200, response.text
    assert client.post(BASE + "/auth/verify", json={"token": messages[-1][2]}).status_code == 200
    login = client.post(BASE + "/session", json={"email": email, "password": PASSWORD})
    assert login.status_code == 200, login.text
    body = login.json()
    return (
        {**HEADERS, "Authorization": "Bearer " + body["session_token"]},
        body,
    )


def seed_mosque(database, leader_id):
    mosque_id = str(uuid.uuid4())
    created = datetime.now(timezone.utc).isoformat()
    with database.transaction() as db:
        db.execute(
            "INSERT INTO mosques VALUES(?,?,?,?,?)",
            (mosque_id, "مسجد النور", "سكاكا", 1, created),
        )
        db.execute(
            "INSERT INTO mosque_staff VALUES(?,?,?,?,?)",
            (mosque_id, leader_id, "LEADER", "demo-admin", created),
        )
    return mosque_id


def valid_attempt(key="camera-1"):
    return {
        "client_attempt_id": key,
        "prayer": "fajr",
        "performed_at": datetime.now(timezone.utc).isoformat(),
        "valid": True,
        "sequence_valid": True,
        "uncertain": False,
        "rakats_expected": 2,
        "rakats_completed": 2,
        "analysis_version": "camera-local-v1",
    }


def test_unified_signup_creates_self_practice_profile(env):
    client, _, _ = env
    headers, login = signup(
        env,
        "Abdullah",
        "abdullah@example.com",
        learning_stage="NEW_MUSLIM",
        accessibility_mode="LARGE_TEXT",
    )
    assert login["guardian"]["role"] == "MEMBER"
    assert login["guardian"]["learning_stage"] == "NEW_MUSLIM"
    assert login["practice_profile"]["profile_kind"] == "SELF"
    practice = {**HEADERS, "Authorization": "Bearer " + login["practice_session_token"]}
    assert (
        client.post(BASE + "/attempts", headers=practice, json=valid_attempt()).status_code == 200
    )
    overview = client.get(BASE + "/overview", headers=headers).json()
    assert overview["practice_profile"]["name"] == "Abdullah"
    assert overview["families"] == []


def test_family_levels_and_guardian_invitation(env):
    client, _, _ = env
    owner, _ = signup(env, "Mohamed", "owner@example.com")
    guardian, _ = signup(env, "Mariam", "guardian@example.com")
    family = client.post(BASE + "/families", headers=owner, json={"name": "أسرة محمد"}).json()["id"]
    child = client.post(
        BASE + f"/families/{family}/dependents",
        headers=owner,
        json={"name": "Omar", "age_band": "CHILD_10_13", "alias": "النجم الأخضر"},
    ).json()["id"]
    invite = client.post(
        BASE + f"/families/{family}/invites", headers=owner, json={"role": "GUARDIAN"}
    ).json()
    redeemed = client.post(
        BASE + "/family-invitations/redeem",
        headers=guardian,
        json={"token": invite["code"]},
    )
    assert redeemed.status_code == 200
    detail = client.get(BASE + f"/families/{family}", headers=guardian).json()
    assert {m["role"] for m in detail["members"]} == {"OWNER", "GUARDIAN"}
    # A co-guardian can securely issue a device code for the same dependent.
    assert client.post(BASE + f"/children/{child}/pairing", headers=guardian).status_code == 200


def test_parent_consent_alias_privacy_and_separate_attendance(env):
    client, _, database = env
    parent, _ = signup(env, "Parent Real Name", "parent@example.com")
    leader, leader_login = signup(env, "Sheikh Leader", "leader@example.com")
    family = client.post(BASE + "/families", headers=parent, json={"name": "Family"}).json()["id"]
    child = client.post(
        BASE + f"/families/{family}/dependents",
        headers=parent,
        json={"name": "Child Real Name", "age_band": "CHILD_10_13"},
    ).json()["id"]
    mosque = seed_mosque(database, leader_login["guardian"]["id"])
    group = client.post(
        BASE + f"/mosques/{mosque}/groups",
        headers=leader,
        json={"name": "براعم الفجر", "age_band": "CHILD_10_13"},
    ).json()["id"]
    invitation = client.post(BASE + f"/mosque-groups/{group}/invite", headers=leader).json()

    # The leader cannot manage or pair a child.  Only the guardian can consent.
    assert client.post(BASE + f"/children/{child}/pairing", headers=leader).status_code == 404
    joined = client.post(
        BASE + "/mosque-groups/join",
        headers=parent,
        json={
            "token": invitation["qr_payload"],
            "profile_id": child,
            "alias": "النجم الأخضر",
            "share_practice": True,
            "share_attendance": True,
            "leaderboard": True,
        },
    )
    assert joined.status_code == 200, joined.text
    assert joined.json()["status"] == "PENDING"
    pending_dashboard = client.get(
        BASE + f"/mosque-groups/{group}/dashboard", headers=leader
    ).json()
    assert pending_dashboard["pending_members"][0]["profile_id"] == child
    approved = client.post(
        BASE + f"/mosque-groups/{group}/members/{child}/approve", headers=leader
    )
    assert approved.status_code == 200

    # Existing camera/device pairing remains the source of practice points.
    pairing = client.post(BASE + f"/children/{child}/pairing", headers=parent).json()
    device_session = client.post(
        BASE + "/pairing/redeem",
        json={"token": pairing["code"], "platform": "android"},
    ).json()["session_token"]
    device_headers = {**HEADERS, "Authorization": "Bearer " + device_session}
    assert (
        client.post(BASE + "/attempts", headers=device_headers, json=valid_attempt()).status_code
        == 200
    )
    child_score = client.get(BASE + "/device/progress", headers=device_headers)
    assert child_score.status_code == 200
    assert child_score.json()["child_id"] == child
    assert child_score.json()["weekly_valid_prayers"] == 1
    assert child_score.json()["weekly_points"] >= 5

    attendance = client.post(
        BASE + f"/mosque-groups/{group}/attendance-sessions",
        headers=leader,
        json={"prayer": "fajr", "prayer_day": date.today().isoformat(), "valid_minutes": 30},
    ).json()
    check_in = client.post(
        BASE + "/attendance/check-in",
        headers=device_headers,
        json={"token": attendance["qr_payload"]},
    )
    assert check_in.status_code == 200, check_in.text

    dashboard = client.get(BASE + f"/mosque-groups/{group}/dashboard", headers=leader).json()
    text = str(dashboard)
    assert "Child Real Name" not in text and "parent@example.com" not in text
    assert dashboard["attendance_leaderboard"][0]["alias"] == "النجم الأخضر"
    assert dashboard["attendance_leaderboard"][0]["attendance"]["attended"] == 1
    assert dashboard["practice_leaderboard"][0]["practice"]["weekly_valid_prayers"] == 1
    mosque_board = client.get(BASE + f"/mosques/{mosque}/leaderboard", headers=leader).json()
    assert mosque_board["identity_policy"] == "GROUP_TOTALS_ONLY"
    assert "alias" not in str(mosque_board)

    # Revoking consent blocks future attendance even while the old device exists.
    assert (
        client.delete(BASE + f"/mosque-groups/{group}/members/{child}", headers=parent).status_code
        == 200
    )
    another = client.post(
        BASE + f"/mosque-groups/{group}/attendance-sessions",
        headers=leader,
        json={"prayer": "dhuhr", "prayer_day": date.today().isoformat()},
    ).json()
    assert (
        client.post(
            BASE + "/attendance/check-in",
            headers=device_headers,
            json={"token": another["code"]},
        ).status_code
        == 403
    )


def test_group_audience_is_enforced_and_admin_approves_leader(env):
    client, _, database = env
    parent, parent_login = signup(env, "Parent", "audience-parent@example.com")
    applicant, applicant_login = signup(env, "Applicant", "applicant@example.com")
    admin, admin_login = signup(env, "Platform Admin", "admin@example.com")
    with database.transaction() as db:
        db.execute(
            "INSERT INTO platform_admins VALUES(?,?)",
            (admin_login["guardian"]["id"], datetime.now(timezone.utc).isoformat()),
        )
    request = client.post(
        BASE + "/mosque-leader-requests",
        headers=applicant,
        json={"mosque_name": "Test Mosque", "city": "Riyadh", "requested_role": "LEADER"},
    )
    assert request.status_code == 200
    decision = client.post(
        BASE + f"/admin/mosque-leader-requests/{request.json()['id']}/decision",
        headers=admin,
        json={"approve": True},
    )
    assert decision.status_code == 200
    mosque_id = decision.json()["mosque_id"]
    child_group = client.post(
        BASE + f"/mosques/{mosque_id}/groups",
        headers=applicant,
        json={"name": "Children", "age_band": "CHILD_10_13"},
    ).json()["id"]
    invite = client.post(
        BASE + f"/mosque-groups/{child_group}/invite", headers=applicant
    ).json()
    self_profile = client.get(BASE + "/overview", headers=parent).json()["practice_profile"]["id"]
    rejected = client.post(
        BASE + "/mosque-groups/join",
        headers=parent,
        json={"token": invite["code"], "profile_id": self_profile, "alias": "Adult"},
    )
    assert rejected.status_code == 400
    assert rejected.json()["detail"] == "ADULT_CANNOT_JOIN_CHILD_GROUP"


def test_owner_can_manage_two_families_and_scoped_member_roles(env):
    client, _, _ = env
    owner, _ = signup(env, "Owner", "two-families@example.com")
    member, member_login = signup(env, "Member", "member@example.com")
    first = client.post(BASE + "/families", headers=owner, json={"name": "First"}).json()["id"]
    second = client.post(BASE + "/families", headers=owner, json={"name": "Second"}).json()["id"]
    assert len(client.get(BASE + "/families", headers=owner).json()) == 2
    invite = client.post(
        BASE + f"/families/{first}/invites", headers=owner, json={"role": "ADULT"}
    ).json()
    assert client.post(
        BASE + "/family-invitations/redeem", headers=member, json={"token": invite["code"]}
    ).status_code == 200
    user_id = member_login["guardian"]["id"]
    changed = client.put(
        BASE + f"/families/{first}/members/{user_id}",
        headers=owner,
        json={"role": "GUARDIAN"},
    )
    assert changed.status_code == 200
    first_roles = {
        row["role"]
        for row in client.get(BASE + f"/families/{first}", headers=owner).json()["members"]
    }
    second_roles = {
        row["role"]
        for row in client.get(BASE + f"/families/{second}", headers=owner).json()["members"]
    }
    assert first_roles == {"OWNER", "GUARDIAN"}
    assert second_roles == {"OWNER"}


def test_adult_group_chat_supports_replies_and_excludes_children(env):
    client, _, database = env
    adult, adult_login = signup(env, "Adult", "chat-adult@example.com")
    leader, leader_login = signup(env, "Leader", "chat-leader@example.com")
    mosque = seed_mosque(database, leader_login["guardian"]["id"])
    adult_group = client.post(
        BASE + f"/mosques/{mosque}/groups",
        headers=leader,
        json={"name": "Adults", "age_band": "ADULT"},
    ).json()["id"]
    invite = client.post(
        BASE + f"/mosque-groups/{adult_group}/invite", headers=leader
    ).json()
    profile = adult_login["practice_profile"]["child_id"]
    assert client.post(
        BASE + "/mosque-groups/join",
        headers=adult,
        json={"token": invite["code"], "profile_id": profile, "alias": "On my way"},
    ).json()["status"] == "ACTIVE"
    post = client.post(
        BASE + f"/mosque-groups/{adult_group}/messages",
        headers=adult,
        json={"body": "I am on the way to the mosque. Who will join?"},
    )
    assert post.status_code == 200
    reply = client.post(
        BASE + f"/mosque-groups/{adult_group}/messages",
        headers=adult,
        json={"body": "I will join", "parent_id": post.json()["id"]},
    )
    assert reply.status_code == 200
    messages = client.get(
        BASE + f"/mosque-groups/{adult_group}/messages", headers=adult
    ).json()
    assert len(messages) == 2
    assert messages[1]["parent_id"] == messages[0]["id"]

    child_group = client.post(
        BASE + f"/mosques/{mosque}/groups",
        headers=leader,
        json={"name": "Children", "age_band": "CHILD_10_13"},
    ).json()["id"]
    assert client.get(
        BASE + f"/mosque-groups/{child_group}/messages", headers=leader
    ).status_code == 403
