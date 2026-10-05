"""Demo-only API. Bearer capability + persona selection exist only behind opt-in.

No production authentication is implied; disabled mode exposes no real-user flow.
"""
from datetime import datetime
from typing import Literal
from fastapi import APIRouter, Depends, Header, HTTPException, Request
from pydantic import BaseModel, Field, field_validator, model_validator
from ..config import get_settings
from .domain import Companion, DomainError
from .providers import direct_distance
from .seed import seed
from .store import Store

router=APIRouter(prefix='/api/v1/mosque-demo',tags=['Mosque Companion demo'])

class Point(BaseModel):
    lat: float = Field(ge=-90,le=90)
    lng: float = Field(ge=-180,le=180)
    label: str = Field(default='نقطة يدوية',max_length=120)
    approximate: bool = True

class Journey(BaseModel):
    origin: Point
    mosque: Literal['quba','qiblatain']
    departure: str
    mode: Literal['walk','car']
    support: bool = False
    prayer: Literal['الجمعة','الفجر','الظهر','العصر','المغرب','العشاء'] = 'الجمعة'
    @field_validator('departure')
    @classmethod
    def time(cls,value):
        try: dt=datetime.fromisoformat(value)
        except ValueError: raise ValueError('موعد غير صالح')
        if dt.tzinfo is None: raise ValueError('يجب تحديد المنطقة الزمنية')
        return dt.isoformat()

class AssistanceRequest(Journey):
    beneficiary: str | None = None
    language: Literal['ar','en','ur'] = 'ar'
    gender: Literal['any','male','female'] = 'any'
    passengers: int = Field(default=1,ge=1,le=4)
    return_required: bool = False
    desired_return_at: str | None = None
    meeting: Literal['home','public'] = 'public'
    public_meeting: Point | None = None
    note: str = Field(default='',max_length=240)
    adult_confirmed: bool
    basic_support_only: bool
    @field_validator('desired_return_at')
    @classmethod
    def desired_return_time(cls,value):
        return Journey.time(value) if value else value
    @model_validator(mode='after')
    def limits(self):
        if not self.adult_confirmed or not self.basic_support_only:
            raise ValueError('الديمو للبالغين والدعم البسيط؛ النقل الطبي المتخصص غير متاح')
        if self.mode=='walk' and self.support: raise ValueError('اختر توصيلة مع دعم بسيط')
        if self.return_required and self.desired_return_at and datetime.fromisoformat(self.desired_return_at)<=datetime.fromisoformat(self.departure):
            raise ValueError('موعد العودة يجب أن يلي الخروج')
        return self

class Publish(Journey):
    seats: int = Field(ge=1,le=6)
    languages: list[Literal['ar','en','ur']] = Field(min_length=1,max_length=3)
    max_detour: int = Field(ge=0,le=30)
    return_enabled: bool = False
    return_at: str | None = None
    @field_validator('return_at')
    @classmethod
    def return_time(cls,value):
        return Journey.time(value) if value else value

class Action(BaseModel):
    action: Literal['search','join','accept','reject','confirm','cancel','progress','cancel_trip']
    id: str = Field(max_length=40)
    trip: str | None = None
    return_commit: bool = False
    stage: str = ''
    reason: str = Field(default='',max_length=160)

class Tools(BaseModel):
    action: Literal['reset','advance','route_failure']
    minutes: int = Field(default=6,ge=1,le=120)
    enabled: bool = True


def services(request: Request):
    settings=get_settings()
    if not settings.mosque_demo_enabled:
        raise HTTPException(503,'رفيق المسجد التجريبي غير مفعّل على الخادم؛ لا يوجد اتصال بحسابات حقيقية')
    # Lazy per-app construction, no interference with prayer jobs.
    if not hasattr(request.app.state,'mosque_store'):
        request.app.state.mosque_store=Store(settings.mosque_demo_db)
    return request.app.state.mosque_store,Companion(hold_minutes=settings.mosque_hold_minutes,
        invitation_minutes=settings.mosque_invitation_minutes,batch=settings.mosque_invitation_batch)

def identity(authorization: str=Header(default=''),x_demo_actor: str=Header(default='U01')):
    if not authorization.startswith('Bearer '): raise HTTPException(401,'جلسة الديمو مطلوبة')
    return authorization[7:],x_demo_actor

def transact(store,engine,ident,fn):
    token,actor=ident
    try:
        with store.transaction(token) as state:
            engine.user(state,actor)
            engine.expire(state)
            result=fn(state,actor)
        return result
    except PermissionError as e: raise HTTPException(401,str(e))
    except (DomainError,KeyError) as e: raise HTTPException(409,str(e))

@router.get('/config')
def config():
    return dict(enabled=get_settings().mosque_demo_enabled,demo=True,production_available=False)

@router.post('/sessions')
def session(svc=Depends(services)):
    return dict(token=svc[0].create(),demo=True)

@router.get('/state')
def state(svc=Depends(services),ident=Depends(identity)):
    store,engine=svc
    return transact(store,engine,ident,lambda s,a: engine.view(s,a))

@router.post('/home')
def home(point: Point,consent: bool=False,svc=Depends(services),ident=Depends(identity)):
    if not consent: raise HTTPException(422,'موافقة صريحة مطلوبة لحفظ البيت')
    store,engine=svc
    def save(s,a):
        s['users'][a]['home']=point.model_dump()
        return engine.view(s,a)
    return transact(store,engine,ident,save)

@router.post('/preview')
def preview(data: Journey,svc=Depends(services),ident=Depends(identity)):
    store,engine=svc
    def render(s,a):
        origin=data.origin.model_dump()
        mosques=[]
        for p in engine.places:
            route=engine.routes.route([origin,p['meeting']],data.mode)
            if s['route_failure']:
                route=dict(path=[],minutes=None,meters=None,simulated=True,
                    label='تعذر التوجيه؛ النقاط والمسافة المباشرة فقط، وليست طريقًا')
            mosques.append(dict(p,direct_meters=direct_distance(origin,p),route=route))
        return dict(places=sorted(mosques,key=lambda p:p['direct_meters']))
    return transact(store,engine,ident,render)

@router.post('/requests')
def create(data: AssistanceRequest,svc=Depends(services),ident=Depends(identity)):
    store,engine=svc
    def save(s,a):
        rid=engine.create_request(s,a,data.model_dump())
        return dict(id=rid,state=engine.view(s,a))
    return transact(store,engine,ident,save)

@router.get('/requests/{rid}/matches')
def matches(rid: str,svc=Depends(services),ident=Depends(identity)):
    store,engine=svc
    def find(s,a):
        r=s['requests'][rid]
        if not engine.owner(s,r,a): raise DomainError('غير مخول لعرض المرشحين')
        candidates=engine.matches(s,r)
        return dict(matches=candidates,excluded=engine.exclusions(s,r,candidates),label='مطابقة حسب المسار والتفضيلات — توجيه محاكى')
    return transact(store,engine,ident,find)

@router.post('/trips')
def publish(data: Publish,svc=Depends(services),ident=Depends(identity)):
    store,engine=svc
    def save(s,a):
        tid=engine.publish(s,a,data.model_dump())
        return dict(id=tid,state=engine.view(s,a))
    return transact(store,engine,ident,save)

@router.post('/actions')
def action(data: Action,svc=Depends(services),ident=Depends(identity)):
    store,engine=svc
    def apply(s,a):
        if data.action in ('accept','reject'):
            i=s['invitations'][data.id]
            if i['provider']!=a: raise DomainError('غير مخول')
            if data.action=='accept': engine.accept(s,i,a,data.return_commit)
            else:
                if i['status']!='pending': raise DomainError('الدعوة مغلقة')
                i['status']='rejected'
                engine.expire(s)
                engine.notifications.send(s,s['requests'][i['request']]['owner'],'رفض المرافق؛ يمكنك البحث عن خيار تالٍ.')
        elif data.action=='cancel_trip':
            t=s['trips'][data.id]
            if t['provider']!=a: raise DomainError('الرحلة ليست لك')
            if not data.reason.strip(): raise DomainError('سبب الإلغاء مطلوب')
            for b in list(s['bookings'].values()):
                if b['trip']==t['id'] and b['status'] in ('held','confirmed'):
                    engine.cancel(s,s['requests'][b['request']],a,data.reason)
            t['status']='cancelled'
            for i in s['invitations'].values():
                if i['trip']==t['id'] and i['status']=='pending': i['status']='closed'
        else:
            r=s['requests'][data.id]
            if data.action in ('search','join'): engine.search(s,r,a,data.trip if data.action=='join' else None)
            elif data.action=='confirm': engine.confirm(s,r,a)
            elif data.action=='cancel':
                if not data.reason.strip(): raise DomainError('سبب الإلغاء مطلوب')
                engine.cancel(s,r,a,data.reason)
            elif data.action=='progress': engine.progress(s,r,a,data.stage)
        return engine.view(s,a)
    return transact(store,engine,ident,apply)

@router.post('/tools')
def tools(data: Tools,svc=Depends(services),ident=Depends(identity)):
    store,engine=svc
    def apply(s,a):
        if data.action=='reset':
            s.clear()
            s.update(seed())
        elif data.action=='advance':
            engine.clock.advance(s,data.minutes)
            engine.expire(s)
        else: s['route_failure']=data.enabled
        return engine.view(s,a)
    return transact(store,engine,ident,apply)
