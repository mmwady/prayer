"""Fixed adult personas and fictional homes, around source-verified mosque centers."""
from .providers import PLACES

def seed():
    names = ['أحمد', 'يوسف', 'الحاج محمود', 'عمر', 'خالد', 'فهد', 'بلال', 'سعيد', 'ناصر', 'مريم', 'سارة']
    coords = [(24.444,39.617),(24.445,39.617),(24.480,39.583),(24.480,39.583),
              (24.478,39.584),(24.4801,39.5831),(24.445,39.620),(24.446,39.620),
              (24.479,39.583),(24.444,39.618),(24.445,39.618)]
    users = {}
    for n, (name, (lat,lng)) in enumerate(zip(names,coords),1):
        uid = f'U{n:02}'
        users[uid] = dict(id=uid, name=name, adult=True, elder=n==3,
            gender='female' if n>=10 else 'male',
            languages=['ar','ur'] if n in (7,8) else ['ar','en'],
            assistance_approved=n==5, verification='demo-approved' if n==5 else 'demo-profile',
            manages=['U03'] if n==4 else [],
            origin=dict(lat=lat,lng=lng,label='منزل تجريبي — نقطة خيالية',approximate=True), home=None)
    trips = {}
    for uid, mosque, mode, time, seats, support, back, detour in [
        ('U02','quba','walk','11:50',4,False,False,15),
        ('U05','qiblatain','car','11:55',2,True,True,8),
        ('U06','quba','car','12:10',2,False,False,8),
        ('U08','quba','car','12:00',1,False,False,8),
        ('U09','qiblatain','car','11:55',2,True,True,8),
        ('U11','quba','walk','11:50',2,False,False,15)]:
        tid = 'T'+uid[1:]
        trips[tid] = dict(id=tid,provider=uid,mosque=mosque,mode=mode,prayer='الجمعة',
            departure=f'2026-10-02T{time}:00+03:00', seats=seats, support=support,
            return_enabled=back, return_at='2026-10-02T13:00:00+03:00' if back else None,
            max_detour=detour, languages=users[uid]['languages'], origin=users[uid]['origin'], status='available')
    return dict(now='2026-10-02T11:30:00+03:00',users=users,trips=trips,requests={},
                invitations={},bookings={},notifications=[],seq=0,route_failure=False,places=PLACES)
