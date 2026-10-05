"""Prayer guidance route: guardrails, degraded fallback and memoisation.

No network call is made here — the DeepSeek client is replaced by a fake so the
tests stay deterministic and cost nothing.
"""
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.admin import prayer_references as refs
from app.config import Settings
from app.llm.deepseek_client import LLMNotConfigured
from app.prayer import guidance


class FakeClient:
    """Stand-in for `DeepSeekClient` that records the prompt it received."""

    def __init__(self, reply: str = 'خذ نفسًا هادئًا وأعد الحركة بتمهّل.', error=None):
        self.reply = reply
        self.error = error
        self.calls = 0
        self.messages: list[dict[str, str]] = []

    async def complete(self, messages):
        self.calls += 1
        self.messages = list(messages)
        if self.error is not None:
            raise self.error
        return self.reply


@pytest.fixture
def client():
    guidance.clear_cache()
    app = FastAPI()
    app.include_router(guidance.router)
    return TestClient(app)


def payload(**overrides):
    body = {'prayer': 'dhuhr', 'station': 'ruku', 'event': 'retry'}
    body.update(overrides)
    return body


def test_station_vocabulary_matches_reference_editor():
    """The guidance vocabulary and the authoring segments must not drift."""

    assert tuple(refs.STATIONS) == guidance.CORE_STATIONS


def test_request_accepts_no_pixel_or_identity_data():
    """Guardrail: the wire model cannot carry frames, keypoints or identity."""

    assert set(guidance.PrayerGuidanceRequest.model_fields) == {
        'prayer', 'station', 'event', 'rakah', 'station_index',
        'total_stations', 'retries', 'core_movements_done',
    }


def test_returns_model_text_and_forbids_religious_rulings(client, monkeypatch):
    fake = FakeClient()
    monkeypatch.setattr(guidance, 'get_deepseek_client', lambda: fake)

    result = client.post('/api/v1/prayer-guidance', json=payload())

    assert result.status_code == 200
    body = result.json()
    assert body['text'] == fake.reply
    assert body['degraded'] is False
    assert body['model'] == Settings().deepseek_model
    assert fake.calls == 1

    system_prompt = fake.messages[0]['content']
    assert 'لا تذكر أحكامًا شرعية' in system_prompt
    assert 'لا تفتِ' in system_prompt
    # The session facts are sent as text only — never as media.
    assert 'الركوع' in fake.messages[1]['content']


def test_missing_api_key_degrades_to_static_text(client, monkeypatch):
    fake = FakeClient(error=LLMNotConfigured('no key'))
    monkeypatch.setattr(guidance, 'get_deepseek_client', lambda: fake)

    body = client.post('/api/v1/prayer-guidance', json=payload()).json()

    assert body['degraded'] is True
    assert body['model'] == 'static'
    assert body['text'] == guidance.STATIC_FALLBACK['retry']


def test_provider_failure_degrades_instead_of_erroring(client, monkeypatch):
    fake = FakeClient(error=RuntimeError('upstream 503'))
    monkeypatch.setattr(guidance, 'get_deepseek_client', lambda: fake)

    result = client.post('/api/v1/prayer-guidance', json=payload())

    assert result.status_code == 200
    assert result.json()['degraded'] is True


def test_empty_model_reply_degrades(client, monkeypatch):
    fake = FakeClient(reply='')
    monkeypatch.setattr(guidance, 'get_deepseek_client', lambda: fake)

    body = client.post('/api/v1/prayer-guidance', json=payload()).json()

    assert body['degraded'] is True
    assert body['text'] == guidance.STATIC_FALLBACK['retry']


def test_repeated_context_is_served_from_cache(client, monkeypatch):
    fake = FakeClient()
    monkeypatch.setattr(guidance, 'get_deepseek_client', lambda: fake)

    first = client.post('/api/v1/prayer-guidance', json=payload()).json()
    second = client.post('/api/v1/prayer-guidance', json=payload()).json()

    assert fake.calls == 1
    assert first == second

    # A different station is a different cache key and does hit the model.
    client.post('/api/v1/prayer-guidance', json=payload(station='sujood_first'))
    assert fake.calls == 2


def test_kill_switch_serves_static_text_without_calling_the_model(client, monkeypatch):
    fake = FakeClient()
    monkeypatch.setattr(guidance, 'get_deepseek_client', lambda: fake)
    monkeypatch.setattr(
        guidance, 'get_settings', lambda: Settings(prayer_guidance_enabled=False)
    )

    body = client.post('/api/v1/prayer-guidance', json=payload()).json()

    assert fake.calls == 0
    assert body['model'] == 'static'
    assert body['degraded'] is True


def test_rejects_unknown_station_and_prayer(client):
    assert client.post(
        '/api/v1/prayer-guidance', json=payload(station='flying')
    ).status_code == 422
    assert client.post(
        '/api/v1/prayer-guidance', json=payload(prayer='tahajjud')
    ).status_code == 422
    assert client.post(
        '/api/v1/prayer-guidance', json=payload(event='judged')
    ).status_code == 422


def test_info_route_reports_configuration(client):
    body = client.get('/api/v1/prayer-guidance').json()

    assert body['enabled'] is True
    assert body['model'] == Settings().deepseek_model
    assert body['thinking'] is False
