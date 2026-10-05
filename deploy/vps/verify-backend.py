"""Temporary live API/cookie/persistence smoke. No emails or provider calls."""
import json
import secrets
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import Request, urlopen
from app.accounts.auth import passwords
from app.accounts.store import AccountStore
from app.config import get_settings

s = get_settings()
state = Path('/app/data/vps-acceptance-private.json')
store = AccountStore(s.account_db)

def call(route, body=None, cookie=None):
    headers = {'X-Iqtadi-Account': '1', 'X-Iqtadi-Platform': 'web', 'Origin': s.account_public_url}
    if body is not None:
        headers['Content-Type'] = 'application/json'
    if cookie:
        headers['Cookie'] = cookie
    request = Request(s.account_public_url + '/api/v1/accounts' + route,
                      data=json.dumps(body).encode() if body is not None else None,
                      headers=headers)
    with urlopen(request, timeout=30) as response:
        return json.load(response), response.headers

if sys.argv[1] == 'seed':
    uid = 'vps-smoke-' + str(uuid.uuid4())
    email = uid + '@example.com'
    password = secrets.token_urlsafe(24)
    with store.transaction() as db:
        db.execute('INSERT INTO guardians VALUES(?,?,?,?,?,?,?)',
                   (uid, 'VPS synthetic acceptance', email, 'PARENT',
                    datetime.now(timezone.utc).isoformat(), passwords.hash(password), 1))
    state.write_text(json.dumps({'id': uid}))
    state.chmod(0o600)
    data, headers = call('/session', {'email': email, 'password': password})
    assert data['guardian']['id'] == uid
    assert 'session_token' not in data
    cookie = headers.get('Set-Cookie', '')
    assert all(value in cookie for value in ['HttpOnly', 'Secure', 'SameSite=strict', 'Path=/api/v1/accounts'])
    state.write_text(json.dumps({'id': uid, 'cookie': cookie.split(';')[0]}))
    identity, _ = call('/me', cookie=cookie.split(';')[0])
    assert identity['guardian']['id'] == uid if 'guardian' in identity else identity['id'] == uid
    print(json.dumps({'real_https_login': 'passed', 'secure_httponly_samesite_cookie': 'passed'}))
else:
    values = json.loads(state.read_text())
    try:
        identity, _ = call('/me', cookie=values['cookie'])
        assert (identity.get('guardian', identity))['id'] == values['id']
        print(json.dumps({'sqlite_session_after_container_restart': 'passed'}))
    finally:
        with store.transaction() as db:
            db.execute('DELETE FROM guardian_sessions WHERE user_id=?', (values['id'],))
            db.execute('DELETE FROM guardians WHERE id=?', (values['id'],))
        state.unlink()
