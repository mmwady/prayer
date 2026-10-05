from concurrent.futures import ThreadPoolExecutor
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from app.mosque import api
from app.mosque.domain import Companion, DomainError
from app.mosque.seed import seed
from app.mosque.store import Store
from app.config import Settings

def data(s,actor='U01',**kw):
    elder=actor=='U03'
    d=dict(origin=s['users'][actor]['origin'],mosque='qiblatain' if elder else 'quba',
      departure='2026-10-02T11:55:00+03:00' if elder else '2026-10-02T11:50:00+03:00',
      mode='car' if elder else 'walk',support=elder,language='ar',gender='any',passengers=1,
      return_required=elder,meeting='home' if elder else 'public',note='مساعدة بسيطة',
      adult_confirmed=True,basic_support_only=True,beneficiary=actor)
    d.update(kw);return d

def invite(e,s,actor='U01',**kw):
    rid=e.create_request(s,actor,data(s,actor,**kw));e.search(s,s['requests'][rid],actor)
    return rid,next(i for i in s['invitations'].values() if i['request']==rid)

def test_s03_walk_and_gps_not_home():
    s=seed();e=Companion();rid,i=invite(e,s)
    assert i['provider']=='U02' and s['users']['U01']['home'] is None
    assert e.remaining(s,s['trips']['T02'])==4
    e.accept(s,i,'U02',False);e.confirm(s,s['requests'][rid],'U01')
    assert e.view(s,'U02')['requests'][0]['status']=='confirmed'
    assert e.view(s,'U01')['requests'][0]['meeting_point']==s['places'][0]['meeting']

def test_s04_elder_authorization_and_privacy():
    s=seed();e=Companion();rid=e.create_request(s,'U04',data(s,'U03'));r=s['requests'][rid]
    assert [m['provider'] for m in e.matches(s,r)]==['U05']
    e.search(s,r,'U04');i=next(iter(s['invitations'].values()))
    before=e.view(s,'U05')['requests'][0]
    assert 'origin' not in before and 'note' not in before and 'meeting_point' not in before
    assert all('origin' not in t for t in e.view(s,'U05')['trips'])
    assert all('home' not in p for p in e.view(s,'U05')['personas'])
    with pytest.raises(DomainError):e.accept(s,i,'U05',False)
    e.accept(s,i,'U05',True)
    assert 'origin' not in e.view(s,'U05')['requests'][0]
    e.confirm(s,r,'U04');assert e.view(s,'U05')['requests'][0]['origin']==r['origin']
    with pytest.raises(DomainError):e.create_request(seed(),'U01',data(s,'U03'))

def test_s05_last_seat_atomic(tmp_path):
    path=tmp_path/'demo.db';store=Store(path);token=store.create();e=Companion()
    with store.transaction(token) as s:
        r1,i1=invite(e,s,'U07',mode='car',language='ur',departure='2026-10-02T12:00:00+03:00')
        r2,i2=invite(e,s,'U01',mode='car',language='ur',departure='2026-10-02T12:00:00+03:00')
        ids=[i1['id'],i2['id']]
    def accept(iid):
        try:
            with Store(path).transaction(token) as s:e.accept(s,s['invitations'][iid],'U08',False)
            return True
        except DomainError:return False
    with ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(accept,ids))
    assert sorted(results)==[False,True]
    with store.transaction(token) as s:
        assert e.remaining(s,s['trips']['T08'])==0
        assert len([b for b in s['bookings'].values() if b['status']=='held'])==1

def test_s06_gender_and_language():
    s=seed();e=Companion();rid=e.create_request(s,'U10',data(s,'U10',gender='female'))
    m=e.matches(s,s['requests'][rid]);assert [v['provider'] for v in m]==['U11']
    assert m[0]['meeting_at']>'2026-10-02T11:50:00+03:00'

def test_s07_no_match_s10_return():
    s=seed();e=Companion();rid=e.create_request(s,'U01',data(s,departure='2026-10-02T15:00:00+03:00'))
    e.search(s,s['requests'][rid],'U01');assert s['requests'][rid]['status']=='no_match'
    s=seed();rid=e.create_request(s,'U03',data(s,'U03'));s['trips']['T05']['return_enabled']=False
    assert e.matches(s,s['requests'][rid])==[]

def test_s08_reject_invite_expiry_hold_expiry():
    s=seed();e=Companion();rid,i=invite(e,s)
    for invitation in s['invitations'].values(): invitation['status']='rejected'
    e.expire(s)
    assert s['requests'][rid]['status']=='rejected'
    s=seed();rid,i=invite(e,s);e.clock.advance(s,11);e.expire(s)
    assert i['status']=='expired' and s['requests'][rid]['status']=='expired'
    s=seed();rid,i=invite(e,s);e.accept(s,i,'U02',False);e.clock.advance(s,6);e.expire(s);e.expire(s)
    assert e.remaining(s,s['trips']['T02'])==4 and s['requests'][rid]['status']=='expired'
    with pytest.raises(DomainError):e.confirm(s,s['requests'][rid],'U01')

def test_s09_cancel_release_once():
    s=seed();e=Companion();rid,i=invite(e,s,'U07',mode='car',language='ur',departure='2026-10-02T12:00:00+03:00')
    e.accept(s,i,'U08',False);e.confirm(s,s['requests'][rid],'U07')
    e.cancel(s,s['requests'][rid],'U08','تعذر الخروج');e.cancel(s,s['requests'][rid],'U08','تعذر الخروج')
    assert e.remaining(s,s['trips']['T08'])==1 and s['requests'][rid]['status']=='cancelled'
    assert len(s['bookings'])==1

def test_s12_independent_return():
    s=seed();e=Companion();rid=e.create_request(s,'U04',data(s,'U03'));r=s['requests'][rid]
    e.search(s,r,'U04');i=next(iter(s['invitations'].values()));e.accept(s,i,'U05',True);e.confirm(s,r,'U04')
    with pytest.raises(DomainError):e.progress(s,r,'U04','arrived')
    for stage in ['departed','meeting','started','arrived']:e.progress(s,r,'U05',stage)
    assert r['status']=='ongoing' and e.remaining(s,s['trips']['T05'])==1
    e.progress(s,r,'U04','return_started');e.progress(s,r,'U03','completed')
    assert r['status']=='completed' and e.remaining(s,s['trips']['T05'])==2

def test_self_duplicate_conflicts():
    s=seed();e=Companion();rid=e.create_request(s,'U01',data(s))
    with pytest.raises(DomainError):e.create_request(s,'U01',data(s))
    s['trips']['T02']['provider']='U01';assert all(m['provider']!='U01' for m in e.matches(s,s['requests'][rid]))
    s=seed()
    with pytest.raises(DomainError):e.create_request(s,'U02',data(s,'U02'))
    with pytest.raises(DomainError):e.publish(s,'U05',dict(s['trips']['T05']))

@pytest.fixture
def client(tmp_path,monkeypatch):
    settings=Settings(mosque_demo_enabled=True,mosque_demo_db=str(tmp_path/'api.db'),_env_file=None)
    monkeypatch.setattr(api,'get_settings',lambda:settings)
    app=FastAPI();app.include_router(api.router);c=TestClient(app)
    token=c.post('/api/v1/mosque-demo/sessions',json={}).json()['token']
    c.headers.update({'Authorization':'Bearer '+token,'X-Demo-Actor':'U01'});return c

def test_api_auth_consent_s11_fallback_and_validation(client):
    root='/api/v1/mosque-demo';point=dict(lat=24.444,lng=39.617,label='منزل تجريبي')
    assert client.get(root+'/state',headers={'Authorization':'Bearer invalid'}).status_code==401
    assert client.post(root+'/home',json=point).status_code==422
    assert client.get(root+'/state').json()['me']['home'] is None
    assert client.post(root+'/home?consent=true',json=point).status_code==200
    client.post(root+'/tools',json={'action':'route_failure'})
    p=client.post(root+'/preview',json=data(seed())).json()['places']
    assert all(v['route']['path']==[] and v['route']['minutes'] is None for v in p)
    assert all(v['direct_meters']>0 for v in p)
    for kw in [dict(passengers=0),dict(adult_confirmed=False),dict(departure='bad')]:
        assert client.post(root+'/requests',json=data(seed(),**kw)).status_code==422

def test_api_roles_and_bilateral_confirmation(client):
    root='/api/v1/mosque-demo';rid=client.post(root+'/requests',json=data(seed())).json()['id']
    assert client.post(root+'/actions',json={'action':'join','id':rid,'trip':'T02'}).status_code==200
    client.headers['X-Demo-Actor']='U06'
    assert client.get(root+f'/requests/{rid}/matches').status_code==409
    assert client.get(root+'/state').json()['requests']==[]
    client.headers['X-Demo-Actor']='U02';v=client.get(root+'/state').json();i=v['invitations'][0]
    assert 'origin' not in v['requests'][0]
    assert client.post(root+'/actions',json={'action':'accept','id':i['id']}).status_code==200
    assert client.post(root+'/actions',json={'action':'confirm','id':rid}).status_code==409
    client.headers['X-Demo-Actor']='U01'
    assert client.post(root+'/actions',json={'action':'confirm','id':rid}).status_code==200
    client.headers['X-Demo-Actor']='U02'
    assert 'meeting_point' in client.get(root+'/state').json()['requests'][0]

def test_disabled_demo(monkeypatch):
    monkeypatch.setattr(api,'get_settings',lambda:Settings(mosque_demo_enabled=False,_env_file=None))
    app=FastAPI();app.include_router(api.router);c=TestClient(app)
    assert c.post('/api/v1/mosque-demo/sessions',json={}).status_code==503
    assert c.get('/api/v1/mosque-demo/config').json()['production_available'] is False

def test_route_network_comparison():
    s=seed();e=Companion();rid=e.create_request(s,'U03',data(s,'U03'));r=s['requests'][rid];m=e.matches(s,r)[0]
    t=s['trips'][m['trip']];dest=s['places'][1]['meeting']
    direct=e.routes.route([t['origin'],dest],'car');via=e.routes.route([t['origin'],r['origin'],dest],'car')
    assert m['detour']==round(via['minutes']-direct['minutes'],1)
    assert all(x['provider']!='U06' for x in e.matches(s,r))

def test_store_persistence_isolation(tmp_path):
    path=tmp_path/'db';store=Store(path);a=store.create();b=store.create()
    with store.transaction(a) as s:s['users']['U01']['home']={'lat':24,'lng':39}
    with Store(path).transaction(a) as s:assert s['users']['U01']['home'] is not None
    with store.transaction(b) as s:assert s['users']['U01']['home'] is None

def test_prayer_return_time_and_publish_validation(client):
    s=seed();e=Companion();rid=e.create_request(s,'U03',data(s,'U03',desired_return_at='2026-10-02T14:00:00+03:00'))
    assert e.matches(s,s['requests'][rid])==[]
    s=seed();rid=e.create_request(s,'U01',data(s,prayer='الفجر'))
    assert e.matches(s,s['requests'][rid])==[]
    root='/api/v1/mosque-demo'
    trip=dict(origin=s['users']['U01']['origin'],mosque='quba',departure='bad',mode='car',seats=1,languages=['ar'],max_detour=8)
    assert client.post(root+'/trips',json=trip).status_code==422
    trip['departure']='2026-10-02T12:00:00' # no timezone
    assert client.post(root+'/trips',json=trip).status_code==422
    trip['departure']='2026-10-02T12:00:00+03:00';trip['seats']=0
    assert client.post(root+'/trips',json=trip).status_code==422


def test_exclusions_derived_from_data():
    s=seed();e=Companion();rid=e.create_request(s,'U03',data(s,'U03'));r=s['requests'][rid]
    candidates=e.matches(s,r);excluded={v['name']:v['reasons'] for v in e.exclusions(s,r,candidates)}
    assert 'خالد' not in excluded
    assert any('وجهة مختلفة' in v for v in excluded['فهد'])
    assert 'اعتماد الدعم المطلوب غير متاح' in excluded['ناصر']
    s['trips']['T05']['return_enabled']=False
    excluded={v['name']:v['reasons'] for v in e.exclusions(s,r,e.matches(s,r))}
    assert 'ذهاب فقط؛ العودة المطلوبة غير مغطاة' in excluded['خالد']

def test_api_publish_and_cancel_trip_affects_passenger(client):
    root='/api/v1/mosque-demo';s=seed()
    body=dict(origin=s['users']['U01']['origin'],mosque='quba',departure='2026-10-02T12:00:00+03:00',mode='car',seats=1,languages=['ur'],max_detour=8)
    response=client.post(root+'/trips',json=body);assert response.status_code==200
    tid=response.json()['id'];assert all('origin' not in t for t in response.json()['state']['trips'])
    client.headers['X-Demo-Actor']='U07'
    rid=client.post(root+'/requests',json=data(s,'U07',mode='car',language='ur',departure='2026-10-02T12:00:00+03:00')).json()['id']
    assert client.post(root+'/actions',json={'action':'join','id':rid,'trip':tid}).status_code==200
    client.headers['X-Demo-Actor']='U01';view=client.get(root+'/state').json();iid=view['invitations'][0]['id']
    assert client.post(root+'/actions',json={'action':'accept','id':iid}).status_code==200
    client.headers['X-Demo-Actor']='U07'
    assert client.post(root+'/actions',json={'action':'confirm','id':rid}).status_code==200
    client.headers['X-Demo-Actor']='U01'
    assert client.post(root+'/actions',json={'action':'cancel_trip','id':tid,'reason':'تغيير خطة الديمو'}).status_code==200
    client.headers['X-Demo-Actor']='U07';v=client.get(root+'/state').json()
    assert v['requests'][0]['status']=='cancelled'
    assert next(t for t in v['trips'] if t['id']==tid)['remaining']==1
