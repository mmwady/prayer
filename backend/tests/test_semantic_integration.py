"""Exercise Wady final summaries through Ezz's real identity/relationship APIs."""

from tests.test_account_spaces import BASE, HEADERS, signup, valid_attempt
from tests.test_account_spaces import env as env


def test_self_profile_coverage_survives_ezz_family_and_duplicate_sync(env):
    client, _, database = env
    owner, login = signup(env, "Adult", "adult.integration@example.com")
    family = client.post(BASE + "/families", headers=owner, json={"name": "Family"}).json()
    practice = {**HEADERS, "Authorization": "Bearer " + login["practice_session_token"]}
    payload = valid_attempt("local_union_1") | {
        "valid": False,
        "sequence_valid": False,
        "uncertain": True,
        "rakats_completed": 1,
        "movements_detected": 12,
        "movements_expected": 16,
        "movement_score": 75,
    }
    first = client.post(BASE + "/attempts", headers=practice, json=payload)
    assert first.status_code == 200, first.text
    assert client.post(BASE + "/attempts", headers=practice, json=payload).json() == {
        "id": first.json()["id"], "duplicate": True
    }
    for identity_field in ("user_id", "parent_id", "child_id"):
        assert client.post(
            BASE + "/attempts", headers=practice,
            json=payload | {identity_field: "untrusted"},
        ).status_code == 422
    personal = client.get(BASE + "/device/progress", headers=practice).json()
    assert personal["weekly_movement_score"] == 75
    assert personal["weekly_points"] == 0
    family_progress = client.get(
        BASE + f"/families/{family['id']}/progress", headers=owner
    ).json()
    profile = next(p for p in family_progress["profiles"] if p["profile_kind"] == "SELF")
    assert profile["id"] == login["practice_profile"]["child_id"]
    assert profile["weekly_movement_score"] == 75
    assert profile["movement_results"]["fajr"]["uncertain"] is True
    assert profile["weekly_points"] == 0
    with database.transaction() as db:
        row = db.execute("SELECT * FROM attempts").fetchone()
        assert row["child_id"] == profile["id"]
        assert db.execute("PRAGMA foreign_key_check").fetchall() == []
        assert db.execute("SELECT max(version) FROM account_schema").fetchone()[0] == 4


def test_family_leaderboard_keeps_coverage_tie_breaker(env):
    client, _, _ = env
    owner, _ = signup(env, "Owner", "owner.integration@example.com")
    family = client.post(BASE + "/families", headers=owner, json={"name": "Family"}).json()
    children = []
    for name, count in [("Adam", 8), ("Ziad", 12)]:
        dependent = client.post(
            BASE + f"/families/{family['id']}/dependents", headers=owner,
            json={"name": name, "age_band": "CHILD_10_13"},
        )
        assert dependent.status_code == 200, dependent.text
        child = dependent.json()["id"]
        children.append(child)
        pair = client.post(BASE + f"/children/{child}/pairing", headers=owner).json()
        session = client.post(BASE + "/pairing/redeem", json={
            "token": pair["code"], "platform": "android"
        }).json()
        response = client.post(BASE + "/attempts", headers={
            **HEADERS, "Authorization": "Bearer " + session["session_token"]
        }, json=valid_attempt("local_union_" + name) | {
            "valid": False, "sequence_valid": False, "uncertain": True,
            "movements_detected": count, "movements_expected": 16,
            "movement_score": 100 * count / 16,
        })
        assert response.status_code == 200, response.text
    board = client.get(BASE + f"/families/{family['id']}/progress", headers=owner).json()["leaderboard"]
    assert [p["id"] for p in board if p["profile_kind"] == "DEPENDENT"] == children[::-1]
