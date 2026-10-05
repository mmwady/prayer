"""Offline golden tests from the preserved raw Python validator."""
import json
from pathlib import Path
import random
import sys
ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / 'backend'))
from app.analysis.sequence import analyze
from app.analysis.domain import stations, STATION_POSES
from app.analysis.contracts import MovementEvent

rng = random.Random(8111)
cases = []
for prayer in ('demo','fajr','dhuhr','asr','maghrib','isha'):
    full = [STATION_POSES[s] for row in stations(prayer) for s in row]
    for variant in range(16):
        poses = full.copy()
        if variant > 0:
            poses = [p for p in poses if rng.random() > .2]
            if variant % 2: poses.insert(rng.randrange(len(poses)+1), 'sitting')
        events = [MovementEvent(event_id=f'e_{i}',pose=p,start_ms=i*500,end_ms=i*500,
             confidence=.85,representative_frame_id=None,observation_status='detected') for i,p in enumerate(poses)]
        if variant % 3 == 0 and variant > 0:
            events.insert(0,MovementEvent(event_id='gap',pose='unknown',start_ms=0,end_ms=100,
                 confidence=0,representative_frame_id=None,observation_status='uncertain'))
        expected = analyze('local',prayer,events,'real',4,len(events)).model_dump(mode='json')
        projection = dict(overall_result=expected['overall_result'], observed_rakahs=expected['observed_rakahs'],
           rakahs=[dict(result=r['result'], stations=[dict(station=s['station'],status=s['status'],event_id=s['event_id']) for s in r['stations']]) for r in expected['rakahs']],
           unexpected=[dict(event_id=e['event_id'],reason=e['reason']) for e in expected['unexpected_movements']])
        cases.append(dict(prayer=prayer,events=[e.model_dump(mode='json') for e in events],expected=projection))
(ROOT / 'mobile/coaching/browser/test/fixtures/sequence.json').write_text(json.dumps(cases,ensure_ascii=False),encoding='utf-8')
print(f'{len(cases)} Python sequence reference cases')
