from fastapi.testclient import TestClient
from tools.tunnel_gateway import app
from app.config import Settings
from app.mosque import api as mosque_api


def test_public_gateway_retains_health_and_config():
    with TestClient(app) as client:
        assert client.get('/healthz').json()['status'] == 'ok'
        assert client.get('/api/v1/prayer-analyses/config').status_code == 200


def test_public_gateway_exposes_only_account_namespace():
    with TestClient(app) as client:
        response = client.get('/api/v1/accounts/config', headers={'X-Iqtadi-Account':'1'})
        assert response.status_code == 200
        assert 'email_configured' in response.json()
        assert response.headers['cache-control'] == 'no-store'
        assert client.get('/api/v1/accounts-other/config').status_code == 404


def test_public_gateway_blocks_operator_routes_even_from_loopback():
    with TestClient(app) as client:
        for path in ('/admin/prayer', '/admin/prayer/', '/docs', '/openapi.json'):
            assert client.get(path).status_code == 404


def test_public_gateway_mosque_flow_and_browser_preflight(monkeypatch, tmp_path):
    settings = Settings(mosque_demo_enabled=True,
                        mosque_demo_db=str(tmp_path / 'mosque.sqlite3'))
    monkeypatch.setattr(mosque_api, 'get_settings', lambda: settings)
    from tools.tunnel_gateway import backend_app
    monkeypatch.delattr(backend_app.state, 'mosque_store', raising=False)
    with TestClient(app) as client:
        origin = {'Origin': 'http://localhost:50861'}
        config = client.get('/api/v1/mosque-demo/config', headers=origin)
        assert config.status_code == 200
        assert config.json()['enabled'] is True
        assert config.headers['access-control-allow-origin'] in ('*', origin['Origin'])
        preflight = client.options('/api/v1/mosque-demo/state', headers={
            **origin, 'Access-Control-Request-Method': 'GET',
            'Access-Control-Request-Headers': 'authorization,x-demo-actor',
        })
        assert preflight.status_code == 200
        assert 'authorization' in preflight.headers['access-control-allow-headers']
        assert client.get('/api/v1/mosque-demo/state').status_code == 401
        session = client.post('/api/v1/mosque-demo/sessions')
        assert session.status_code == 200
        state = client.get('/api/v1/mosque-demo/state', headers={
            'Authorization': f"Bearer {session.json()['token']}",
            'X-Demo-Actor': 'U01',
        })
        assert state.status_code == 200
        assert client.get('/api/v1/mosque-demo-other/config').status_code == 404


def test_public_gateway_preserves_mosque_opt_in(monkeypatch):
    monkeypatch.setattr(mosque_api, 'get_settings',
                        lambda: Settings(mosque_demo_enabled=False))
    with TestClient(app) as client:
        assert client.get('/api/v1/mosque-demo/config').json()['enabled'] is False
        assert client.post('/api/v1/mosque-demo/sessions').status_code == 503
