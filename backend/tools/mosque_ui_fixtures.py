from pathlib import Path
import json
from app.mosque.domain import Companion
from app.mosque.seed import seed
s=seed();e=Companion();result={'initial':e.view(s,'U01')}
r=e.create_request(s,'U01',dict(origin=s['users']['U01']['origin'],mosque='quba',departure='2026-10-02T11:50:00+03:00',mode='walk',support=False,language='ar',gender='any',passengers=1,return_required=False,meeting='public',note='',beneficiary='U01'))
result.update(created=e.view(s,'U01'),id=r,matches=e.matches(s,s['requests'][r]),preview=[])
for p in s['places']:
    from app.mosque.providers import direct_distance
    result['preview'].append(dict(p,direct_meters=direct_distance(s['users']['U01']['origin'],p),route=e.routes.route([s['users']['U01']['origin'],p['meeting']],'walk')))
e.search(s,s['requests'][r],'U01','T02');result['searching']=e.view(s,'U01')
result['inbox']=e.view(s,'U02');i=next(iter(s['invitations'].values()));e.accept(s,i,'U02',False)
result['offered']=e.view(s,'U01');e.confirm(s,s['requests'][r],'U01');result['confirmed']=e.view(s,'U01')
s=seed()
r=e.create_request(s,'U04',dict(origin=s['users']['U03']['origin'],mosque='qiblatain',departure='2026-10-02T11:55:00+03:00',mode='car',support=True,language='ar',gender='any',passengers=1,return_required=True,meeting='home',note='',beneficiary='U03'))
e.search(s,s['requests'][r],'U04');i=next(iter(s['invitations'].values()));e.accept(s,i,'U05',True);e.confirm(s,s['requests'][r],'U04')
for stage in ['departed','meeting','started','arrived']:e.progress(s,s['requests'][r],'U04',stage)
result['elder_arrived']=e.view(s,'U04')
path=Path('../mobile/coaching/test/fixtures/mosque_companion.json');path.parent.mkdir(exist_ok=True);path.write_text(json.dumps(result,ensure_ascii=False),encoding='utf8')
