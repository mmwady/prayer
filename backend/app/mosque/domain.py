"""Deterministic eligibility, capacity, privacy and independent outbound/return lifecycle."""
from copy import deepcopy
from datetime import datetime, timedelta
from .providers import DemoClock, DemoGridRoutes, DemoNotifications, MatchConfig, CatalogMosques

class DomainError(ValueError):
    pass

LABELS = {'draft':'مسودة','searching':'يبحث عن مرافق','offered':'عرض بانتظار تأكيدك',
          'confirmed':'مؤكد','ongoing':'جارٍ','completed':'مكتمل','cancelled':'ملغى',
          'rejected':'مرفوض','expired':'انتهت المهلة','no_match':'لا يوجد مرافق مناسب'}
ACTIVE = {'held','confirmed'}
STEPS = ['confirmed','departed','meeting','started','arrived','return_started','completed']

class Companion:
    def __init__(self, routes=None, clock=None, notifications=None, config=None, mosques=None,
                 hold_minutes=5, invitation_minutes=10, batch=3):
        self.config = config or MatchConfig()
        self.mosques = mosques or CatalogMosques()
        self.places = self.mosques.places()
        self.routes = routes or DemoGridRoutes(self.config)
        self.clock = clock or DemoClock()
        self.notifications = notifications or DemoNotifications()
        self.hold_minutes = hold_minutes
        self.invitation_minutes = invitation_minutes
        self.batch = batch
    def ident(self,s,prefix):
        s['seq'] += 1
        return prefix+str(s['seq'])
    def user(self,s,actor):
        if actor not in s['users']: raise DomainError('شخصية غير معروفة')
        return s['users'][actor]
    def owner(self,s,r,actor):
        return actor in (r['owner'],r['beneficiary']) or r['beneficiary'] in self.user(s,actor)['manages']
    def remaining(self,s,t):
        return t['seats'] - sum(b['passengers'] for b in s['bookings'].values()
            if b['trip']==t['id'] and b['status'] in ACTIVE)
    def expire(self,s):
        now = self.clock.now(s)
        for b in s['bookings'].values():
            if b['status']=='held' and datetime.fromisoformat(b['expires'])<=now:
                b['status']='expired'
                r=s['requests'][b['request']]
                if r.get('booking')==b['id']:
                    r['status']='expired'
                self.notifications.send(s,r['owner'],'انتهت مهلة العرض؛ يمكنك البحث مجددًا.')
        for i in s['invitations'].values():
            if i['status']=='pending' and datetime.fromisoformat(i['expires'])<=now:
                i['status']='expired'
        for r in s['requests'].values():
            invites=[i for i in s['invitations'].values() if i['request']==r['id']]
            if r['status']=='searching' and invites and all(i['status']!='pending' for i in invites):
                r['status']='expired' if any(i['status']=='expired' for i in invites) else 'rejected'
    def conflict(self,s,users,departure,return_at=None,exclude_trip=None,exclude_request=None):
        start=datetime.fromisoformat(departure)
        end=datetime.fromisoformat(return_at) + timedelta(minutes=45) if return_at else start+timedelta(minutes=self.config.arrival_window)
        for b in s['bookings'].values():
            if b['status'] not in ACTIVE or b['request']==exclude_request: continue
            t=s['trips'][b['trip']]
            if t['id']==exclude_trip: continue
            r=s['requests'][b['request']]
            if not set(users).intersection([t['provider'],r['beneficiary'],r['owner']]): continue
            other=datetime.fromisoformat(t['departure'])
            other_end=datetime.fromisoformat(t['return_at'])+timedelta(minutes=45) if r['return_required'] else other+timedelta(minutes=self.config.arrival_window)
            if start<other_end and other<end: return True
        # A provider's own published trip is also a commitment.
        for t in s['trips'].values():
            if t['id']==exclude_trip or t['status'] in ('cancelled','completed','closed'): continue
            if t['provider'] not in users: continue
            other=datetime.fromisoformat(t['departure'])
            other_end=datetime.fromisoformat(t['return_at'])+timedelta(minutes=45) if t['return_enabled'] else other+timedelta(minutes=self.config.arrival_window)
            if start<other_end and other<end: return True
        return False
    def matches(self,s,r):
        result=[]
        u=s['users'][r['beneficiary']]
        dest=next(p for p in self.places if p['id']==r['mosque'])
        now=self.clock.now(s)
        for t in s['trips'].values():
            p=s['users'][t['provider']]
            dep=datetime.fromisoformat(t['departure'])
            delta=abs((dep-datetime.fromisoformat(r['departure'])).total_seconds()/60)
            if not p['adult'] or t['status']!='available' or dep<=now or t['provider'] in (r['owner'],r['beneficiary']): continue
            if t['mosque']!=r['mosque'] or t['mode']!=r['mode'] or delta>self.config.time_window: continue
            if t.get('prayer','الجمعة')!=r.get('prayer','الجمعة'): continue
            if self.remaining(s,t)<r['passengers']: continue
            if r['support'] and (not t['support'] or not p['assistance_approved']): continue
            if u['elder'] and (not t['support'] or not p['assistance_approved']): continue
            if r['return_required'] and not t['return_enabled']: continue
            if r['return_required'] and r.get('desired_return_at') and abs((datetime.fromisoformat(t['return_at'])-datetime.fromisoformat(r['desired_return_at'])).total_seconds()/60)>self.config.time_window: continue
            if r['gender']!='any' and p['gender']!=r['gender']: continue
            if r['language'] not in t['languages']: continue
            if self.conflict(s,[t['provider'],r['owner'],r['beneficiary']],t['departure'],t['return_at'] if r['return_required'] else None,t['id'],r['id']): continue
            # Same synthetic network/traffic for all three legs; never use straight distance.
            meeting = r['origin'] if r['meeting']=='home' and t['mode']=='car' else (r.get('public_meeting') or dest['meeting'])
            base=self.routes.route([t['origin'],dest['meeting']],t['mode'])
            pickup=self.routes.route([t['origin'],meeting],t['mode'])
            via=self.routes.route([t['origin'],meeting,dest['meeting']],t['mode'])
            detour=round(max(0,via['minutes']-base['minutes']),1)
            if detour>t['max_detour']: continue
            requester=self.routes.route([r['origin'],meeting],'walk')
            wait=requester['minutes'] if t['mode']=='walk' else 0
            meet_at=dep+timedelta(minutes=max(pickup['minutes'],wait))
            arrival=meet_at+timedelta(minutes=self.routes.route([meeting,dest['meeting']],t['mode'])['minutes'])
            if arrival>datetime.fromisoformat(r['departure'])+timedelta(minutes=self.config.arrival_window): continue
            score=self.config.destination_weight+self.config.language_weight-detour*self.config.detour_weight-delta*self.config.time_weight-pickup['minutes']*self.config.pickup_weight
            result.append(dict(trip=t['id'],provider=p['id'],name=p['name'],verification=p['verification'],
                mode=t['mode'],support=t['support'],languages=t['languages'],mosque=t['mosque'],
                departure=t['departure'],meeting_label=meeting.get('label','نقطة اللقاء'),
                meeting_at=meet_at.isoformat(),detour=detour,seats=self.remaining(s,t),
                return_enabled=t['return_enabled'],return_at=t['return_at'],score=round(score,2),
                route_label='مسار محاكى من شبكة الديمو',
                reasons=[dest['name'],f'انحراف محاكى {detour} دقيقة',f'فرق موعد {delta:g} دقيقة',
                         'اللغة المطلوبة متاحة']+(['اعتماد مساعدة تجريبي محفوظ'] if u['elder'] else [])+
                         (['عودة ملتزم بها'] if r['return_required'] else [])))
        return sorted(result,key=lambda m:(-m['score'],m['trip']))
    def create_request(self,s,actor,data):
        self.user(s,actor)
        beneficiary=data.get('beneficiary') or actor
        if beneficiary!=actor and beneficiary not in s['users'][actor]['manages']: raise DomainError('لا توجد علاقة أسرية مخولة')
        if not s['users'][beneficiary]['adult']: raise DomainError('الخدمة للبالغين فقط')
        if datetime.fromisoformat(data['departure'])<=self.clock.now(s): raise DomainError('اختر موعدًا مستقبليًا')
        for r in s['requests'].values():
            if r['beneficiary']==beneficiary and r['status'] in ('draft','searching','offered','confirmed','ongoing','no_match'):
                raise DomainError('يوجد طلب قائم؛ ألغِه أو تابعه أولًا')
        if self.conflict(s,[actor,beneficiary],data['departure']): raise DomainError('لديك التزام متعارض')
        rid=self.ident(s,'R')
        r=dict(data,id=rid,owner=actor,beneficiary=beneficiary,status='draft',booking=None)
        if s['users'][beneficiary]['elder'] and not r['support']: raise DomainError('طلب المسن يتطلب اعتمادًا ودعمًا بسيطًا')
        s['requests'][rid]=r
        return rid
    def exclusions(self,s,r,candidates):
        eligible={m['trip'] for m in candidates}
        results=[]
        for t in s['trips'].values():
            if t['id'] in eligible or t['provider'] in (r['owner'],r['beneficiary']): continue
            p=s['users'][t['provider']]
            reasons=[]
            if t['mosque']!=r['mosque']:
                reasons.append('وجهة مختلفة: '+next(x['name'] for x in self.places if x['id']==t['mosque']))
            if t['mode']!=r['mode']: reasons.append('وسيلة انتقال مختلفة')
            if t.get('prayer','الجمعة')!=r.get('prayer','الجمعة'): reasons.append('الصلاة المختارة مختلفة')
            if r['support'] and (not p['assistance_approved'] or not t['support']): reasons.append('اعتماد الدعم المطلوب غير متاح')
            if r['return_required'] and not t['return_enabled']: reasons.append('ذهاب فقط؛ العودة المطلوبة غير مغطاة')
            if r['return_required'] and t['return_enabled'] and r.get('desired_return_at') and abs((datetime.fromisoformat(t['return_at'])-datetime.fromisoformat(r['desired_return_at'])).total_seconds()/60)>self.config.time_window:
                reasons.append('موعد العودة لا يوافق الطلب')
            if r['language'] not in t['languages']: reasons.append('اللغة المطلوبة غير متاحة')
            if r['gender']!='any' and p['gender']!=r['gender']: reasons.append('لا يطابق تفضيل المرافق')
            if self.remaining(s,t)<r['passengers']: reasons.append('مقاعد غير كافية')
            if t['status']!='available': reasons.append('الرحلة غير متاحة')
            if datetime.fromisoformat(t['departure'])<=self.clock.now(s): reasons.append('انتهى موعد الخروج')
            delta=abs((datetime.fromisoformat(t['departure'])-datetime.fromisoformat(r['departure'])).total_seconds()/60)
            if delta>self.config.time_window: reasons.append('موعد الخروج خارج النافذة المسموحة')
            if not reasons: reasons.append('لا يستوفي توافق المسار أو الوقت أو الالتزامات وفق الحساب الحالي')
            results.append(dict(name=p['name'],reasons=reasons))
        return results
    def search(self,s,r,actor,trip=None):
        if not self.owner(s,r,actor): raise DomainError('الطلب ليس لك')
        if r['status'] in ('offered','confirmed','ongoing','completed','cancelled'): raise DomainError('لا يمكن إرسال طلب جديد في هذه الحالة')
        if any(i['request']==r['id'] and i['status']=='pending' for i in s['invitations'].values()):
            raise DomainError('توجد دعوات بانتظار الرد؛ تابعها أو انتظر انتهاء المهلة')
        candidates=self.matches(s,r)
        tried={i['trip'] for i in s['invitations'].values() if i['request']==r['id']}
        candidates=[c for c in candidates if c['trip'] not in tried]
        if trip: candidates=[c for c in candidates if c['trip']==trip]
        if not candidates:
            r['status']='no_match'
            return
        for c in candidates[:1 if trip else self.batch]:
            iid=self.ident(s,'I')
            s['invitations'][iid]=dict(id=iid,request=r['id'],trip=c['trip'],provider=c['provider'],
                status='pending',expires=(self.clock.now(s)+timedelta(minutes=self.invitation_minutes)).isoformat())
            self.notifications.send(s,c['provider'],'دعوة مرافقة جديدة؛ راجع الطلب.')
        r['status']='searching'
    def accept(self,s,i,actor,return_commit):
        if i['provider']!=actor: raise DomainError('الدعوة ليست لك')
        r=s['requests'][i['request']]
        if i['status']!='pending' or r['status'] not in ('searching','rejected','expired'): raise DomainError('الدعوة مغلقة أو سبق تقديم عرض')
        if r['return_required'] and not return_commit: raise DomainError('يجب الالتزام بالعودة المطلوبة')
        matches={m['trip']:m for m in self.matches(s,r)}
        if i['trip'] not in matches: raise DomainError('لم يعد المقعد أو التوقيت متاحًا؛ لم يُحجز شيء')
        bid=self.ident(s,'B')
        s['bookings'][bid]=dict(id=bid,request=r['id'],trip=i['trip'],passengers=r['passengers'],status='held',
            stage='confirmed',return_required=r['return_required'],
            expires=(self.clock.now(s)+timedelta(minutes=self.hold_minutes)).isoformat(),
            meeting_at=matches[i['trip']]['meeting_at'])
        r.update(booking=bid,status='offered')
        i['status']='accepted'
        self.notifications.send(s,r['owner'],'وصل عرض مرافقة؛ راجعه وأكده قبل انتهاء المهلة.')
    def confirm(self,s,r,actor):
        if not self.owner(s,r,actor) or r['status']!='offered': raise DomainError('لا يوجد عرض قابل للتأكيد لهذا الحساب')
        b=s['bookings'][r['booking']]
        if b['status']!='held': raise DomainError('انتهت مهلة العرض')
        b['status']='confirmed'
        r['status']='confirmed'
        for i in s['invitations'].values():
            if i['request']==r['id'] and i['status']=='pending': i['status']='closed'
        self.notifications.send(s,s['trips'][b['trip']]['provider'],'تم تأكيد الطرفين؛ أصبحت نقطة اللقاء متاحة.')
    def cancel(self,s,r,actor,reason):
        b=s['bookings'].get(r.get('booking'))
        provider=s['trips'][b['trip']]['provider'] if b else None
        if not self.owner(s,r,actor) and actor!=provider: raise DomainError('غير مخول')
        if r['status']=='completed': raise DomainError('الرحلة مكتملة')
        r.update(status='cancelled',cancel_reason=reason)
        if b: b['status']='cancelled'
        for i in s['invitations'].values():
            if i['request']==r['id'] and i['status']=='pending': i['status']='closed'
        for uid in {r['owner'],r['beneficiary'],provider}-{None}:
            self.notifications.send(s,uid,'أُلغيت المرافقة: '+reason)
    def progress(self,s,r,actor,stage):
        b=s['bookings'].get(r.get('booking'))
        if not b or b['status']!='confirmed': raise DomainError('تحتاج رحلة مؤكدة')
        t=s['trips'][b['trip']]
        if not self.owner(s,r,actor) and actor!=t['provider']: raise DomainError('غير مخول')
        steps=STEPS if b['return_required'] else STEPS[:5]+['completed']
        idx=steps.index(b['stage'])
        if idx+1>=len(steps) or steps[idx+1]!=stage: raise DomainError('انتقال رحلة غير صالح')
        b['stage']=stage
        r['status']='completed' if stage=='completed' else 'ongoing'
        if stage=='completed': b['status']='completed'
        # Outbound arrival explicitly does not complete a booked return.
        t['status']='completed' if all(x['status'] in ('completed','cancelled','expired') for x in s['bookings'].values() if x['trip']==t['id']) else 'ongoing'
    def publish(self,s,actor,data):
        if datetime.fromisoformat(data['departure'])<=self.clock.now(s): raise DomainError('لا يمكن نشر موعد منتهٍ')
        if data['support'] and not self.user(s,actor)['assistance_approved']: raise DomainError('المساعدة تتطلب اعتمادًا مخزنًا')
        if data['return_enabled'] and (not data['return_at'] or datetime.fromisoformat(data['return_at'])<=datetime.fromisoformat(data['departure'])): raise DomainError('اختر موعد عودة بعد الخروج')
        if self.conflict(s,[actor],data['departure'],data['return_at'] if data['return_enabled'] else None): raise DomainError('لديك رحلة أو حجز متعارض')
        tid=self.ident(s,'T')
        s['trips'][tid]=dict(data,id=tid,provider=actor,status='available')
        return tid
    def view(self,s,actor):
        u=self.user(s,actor)
        requests=[]
        for r in s['requests'].values():
            b=s['bookings'].get(r.get('booking'))
            t=s['trips'].get(b['trip']) if b else None
            mine=self.owner(s,r,actor)
            invited=any(i['request']==r['id'] and i['provider']==actor for i in s['invitations'].values())
            if not mine and not invited and not (t and t['provider']==actor): continue
            out=deepcopy(r)
            precise=mine or (b and b['status'] in ('confirmed','completed') and t['provider']==actor)
            if not precise:
                out.pop('origin',None)
                out.pop('note',None)
                out.pop('public_meeting',None)
            out['area']='نطاق انطلاق تقريبي '+str(round(r['origin']['lat'],2))+', '+str(round(r['origin']['lng'],2))
            out['name']=s['users'][r['beneficiary']]['name']
            out['status_label']=LABELS[r['status']]
            out['mine']=mine
            if b:
                out['offer']=dict(id=b['id'],name=s['users'][t['provider']]['name'],provider=t['provider'],
                    trip=t['id'],status=b['status'],stage=b['stage'],expires=b['expires'],
                    return_at=t['return_at'] if b['return_required'] else None,meeting_at=b['meeting_at'])
                if precise:
                    destination=next(p for p in self.places if p['id']==r['mosque'])
                    meeting=r['origin'] if r['meeting']=='home' and t['mode']=='car' else (r.get('public_meeting') or destination['meeting'])
                    out['meeting_point']=meeting
                    out['route']=self.routes.route([r['origin'],meeting,destination['meeting']],r['mode'])
            requests.append(out)
        public_trips=[]
        for t in s['trips'].values():
            v=deepcopy(t)
            v.pop('origin',None)
            v['origin_area']='نطاق تقريبي '+str(round(t['origin']['lat'],2))+', '+str(round(t['origin']['lng'],2))
            v['remaining']=self.remaining(s,t)
            v['display_status']='full' if v['remaining']==0 and t['status']=='available' else t['status']
            v['name']=s['users'][t['provider']]['name']
            public_trips.append(v)
        return dict(demo=True,now=s['now'],timezone='Asia/Riyadh',me=deepcopy(u),
            personas=[{k:p[k] for k in ('id','name','gender','verification')} for p in s['users'].values()],
            places=self.places,requests=requests,trips=public_trips,
            invitations=[i for i in s['invitations'].values() if i['provider']==actor],
            notifications=[n for n in s['notifications'] if n['user']==actor][-10:],
            matching='مطابقة حسب المسار والتفضيلات',routing='توجيه محاكى؛ لا توجد خدمة طرق فعلية',
            route_failure=s['route_failure'])
