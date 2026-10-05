"""Replaceable demo providers. Every route/time is synthetic, never a street claim."""
from dataclasses import dataclass
from datetime import datetime, timedelta
from math import cos, radians, hypot
from typing import Protocol

PLACES = [
    dict(id='quba', name='مسجد قباء', lat=24.43927, lng=39.61710,
         source='https://mapcarta.com/29219118',
         name_source='https://www.visitsaudi.com/ar/madinah/attractions/masjid-quba-in-madinah',
         meeting=dict(lat=24.441, lng=39.617, label='نطاق مقصد قباء — نقطة لقاء مقترحة تحتاج تأكيدًا', approximate=True),
         entrance=None, dropoff=None),
    dict(id='qiblatain', name='مسجد القبلتين', lat=24.48416, lng=39.57881,
         source='https://mapcarta.com/29219122',
         name_source='https://www.visitsaudi.com/en/madinah/attractions/masjid-al-qiblatain-in-madinah',
         meeting=dict(lat=24.484, lng=39.580, label='نقطة لقاء مقترحة قرب القبلتين — تحتاج تأكيدًا', approximate=True),
         entrance=None, dropoff=None),
]

class Clock(Protocol):
    def now(self, state: dict) -> datetime: ...

class DemoClock:
    def now(self, state):
        return datetime.fromisoformat(state['now'])
    def advance(self, state, minutes):
        state['now'] = (self.now(state) + timedelta(minutes=minutes)).isoformat()

class MosqueProvider(Protocol):
    def places(self) -> list[dict]: ...

class CatalogMosques:
    def places(self):
        return PLACES

class RouteProvider(Protocol):
    def route(self, points: list[dict], mode: str) -> dict: ...

@dataclass(frozen=True)
class MatchConfig:
    time_window: int = 20
    arrival_window: int = 45
    walking_detour: int = 15
    destination_weight: float = 100
    detour_weight: float = 4
    time_weight: float = 2
    pickup_weight: float = 1
    language_weight: float = 10
    # All legs use the same demo speed/traffic assumption.
    walk_meters_minute: float = 75
    car_meters_minute: float = 500

class DemoGridRoutes:
    """Rectilinear synthetic network; no road compatibility inferred from crow-flight.

    Horizontal then vertical grid segments, including a synthetic connection to each
    input point. It intentionally is NOT a model of actual Medina streets.
    """
    def __init__(self, config=MatchConfig()):
        self.config = config
    def route(self, points, mode):
        path = [points[0]]
        meters = 0.0
        for a, b in zip(points, points[1:]):
            corner = dict(lat=a['lat'], lng=b['lng'])
            path.extend([corner, b])
            meters += abs(a['lng'] - b['lng']) * 111320 * cos(radians(a['lat']))
            meters += abs(a['lat'] - b['lat']) * 111320
        speed = self.config.walk_meters_minute if mode == 'walk' else self.config.car_meters_minute
        return dict(path=path, meters=round(meters), minutes=round(meters / speed, 1),
                    simulated=True, label='مسار وزمن محاكيان — ليس توجيهًا فعليًا', traffic='demo-fixed')

class Notifications(Protocol):
    def send(self, state: dict, recipient: str, text: str) -> None: ...

class DemoNotifications:
    def send(self, state, recipient, text):
        # Persisted in-app only. No push, phone, email or external provider.
        state['notifications'].append(dict(user=recipient, text=text, at=state['now']))

def direct_distance(a, b):
    return round(hypot((a['lat']-b['lat'])*111320,
                       (a['lng']-b['lng'])*111320*cos(radians(a['lat']))))
