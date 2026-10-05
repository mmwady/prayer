"""HTTP checks in disposable LOCAL demo sessions; no tokens or coordinates printed."""
import json
from pathlib import Path
from urllib.request import Request, urlopen

BASE = 'http://127.0.0.1:8011/api/v1/mosque-demo'

def call(path, body=None, token=None, actor='U01'):
    headers = {'Content-Type': 'application/json', 'X-Demo-Actor': actor}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    request = Request(BASE + path, headers=headers,
                      data=json.dumps(body).encode() if body is not None else None)
    with urlopen(request, timeout=15) as response:
        return json.load(response)

assert call('/config')['enabled'] is True
results = {}
for label, owner, beneficiary, provider, mosque, mode, back, time in [
    ('S03', 'U01', 'U01', 'U02', 'quba', 'walk', False, '11:50'),
    ('S04', 'U04', 'U03', 'U05', 'qiblatain', 'car', True, '11:55'),
]:
    token = call('/sessions', {})['token']
    current = call('/state', token=token, actor=owner)
    payload = dict(origin=current['me']['origin'], mosque=mosque,
                   departure=f'2026-10-02T{time}:00+03:00', prayer='الجمعة', mode=mode,
                   support=back, beneficiary=beneficiary, language='ar', gender='any',
                   passengers=1, return_required=back,
                   desired_return_at='2026-10-02T13:00:00+03:00' if back else None,
                   meeting='home' if back else 'public', note='',
                   adult_confirmed=True, basic_support_only=True)
    rid = call('/requests', payload, token, owner)['id']
    matches = call(f'/requests/{rid}/matches', token=token, actor=owner)
    assert matches['matches'][0]['provider'] == provider
    tid = matches['matches'][0]['trip']
    call('/actions', dict(action='join', id=rid, trip=tid), token, owner)
    inbox = call('/state', token=token, actor=provider)
    request = next(r for r in inbox['requests'] if r['id'] == rid)
    assert 'origin' not in request and 'meeting_point' not in request
    iid = inbox['invitations'][0]['id']
    call('/actions', dict(action='accept', id=iid, return_commit=back), token, provider)
    confirmed = call('/actions', dict(action='confirm', id=rid), token, owner)
    assert confirmed['requests'][0]['status'] == 'confirmed'
    assert call('/state', token=token, actor=provider)['requests'][0]['status'] == 'confirmed'
    for stage in ['departed', 'meeting', 'started', 'arrived']:
        arrived = call('/actions', dict(action='progress', id=rid, stage=stage), token, owner)
    r = arrived['requests'][0]
    assert r['status'] == 'ongoing' and r['offer']['stage'] == 'arrived'
    if back:
        assert r['return_required'] and r['offer']['return_at']
        call('/actions', dict(action='progress', id=rid, stage='return_started'), token, owner)
    final = call('/actions', dict(action='progress', id=rid, stage='completed'), token, owner)
    assert final['requests'][0]['status'] == 'completed'
    results[label] = dict(provider=provider, privacy_before_confirmation=True,
                          both_confirmed=True, reached_mosque=True,
                          return_independent=back, final_status='completed')

path = Path('../output/mosque/live-verification.json')
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding='utf8')
print(json.dumps(results, ensure_ascii=False, indent=2))
