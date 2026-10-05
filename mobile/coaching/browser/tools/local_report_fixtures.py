"""Fine-grained offline report parity against unchanged backend raw defaults."""
import json
from pathlib import Path
import random
import sys

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / 'backend'))
from app.analysis.inference import Observation
from app.analysis.temporal import process
from app.analysis.sequence import analyze
from app.analysis.domain import stations, STATION_POSES

rng = random.Random(20261005)
actions = {'standing':'1_Qiyam','takbir':'2_Takbir','ruku':'4_Ruku','sujood':'5_Sujud',
           'sitting':'6_Jalsa','salam_right':'7_Salam_Right','salam_left':'8_Salam_Left','unknown':None}
cases=[]
for prayer in ('demo','fajr','dhuhr','asr','maghrib','isha'):
    full=[STATION_POSES[s] for row in stations(prayer) for s in row]
    for variant in range(12):
        observations=[]
        timestamp=0
        for pose in full:
            if variant and rng.random()<.12:
                continue
            for duplicate in range(rng.randrange(1,4) if variant else 1):
                predicted='unknown' if variant and rng.random()<.08 else pose
                confidence=rng.choice([.25,.62,.65,.8,.95]) if variant else .95
                detected=predicted!='unknown'
                index=len(observations)
                observations.append(Observation(f'frame_{index}',timestamp,index,predicted,confidence if detected else 0,detected))
                timestamp+=rng.choice([125,250,250,1101]) if variant else 250
        events=process(observations)
        report=analyze('fixture',prayer,events,'real',4,len(observations),'local-test').model_dump(mode='json')
        samples=[dict(frame_id=o.frame_id,timestamp_ms=o.timestamp_ms,sequence_index=o.sequence_index,
                      result=dict(pose_detected=o.detected,predicted_action=actions[o.pose],confidence=o.confidence)) for o in observations]
        cases.append(dict(prayer=prayer,samples=samples,expected=report))
target=ROOT/'mobile/coaching/browser/test/fixtures/local_report.json'
target.write_text(json.dumps(cases,ensure_ascii=False,allow_nan=False),encoding='utf-8')
print(f'{len(cases)} full temporal/evidence/review-context Python reference cases')
