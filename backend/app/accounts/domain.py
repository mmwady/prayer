"""Deterministic timing and encouragement. Valid means observed sequence only."""

from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

PRAYERS = ("fajr", "dhuhr", "asr", "maghrib", "isha")
RAKATS = dict(zip(PRAYERS, (2, 4, 4, 3, 4)))


class PrayerTimeService:
    """Explicit dated local timetable, no GPS or guessed astronomical calculation.

    The guardian supplies reviewed mosque/city times for a bounded date range.
    Outside that range timing stays unknown. Fajr ends at sunrise; Isha at
    the next configured Fajr. Isha after midnight belongs to the previous day.
    """

    def __init__(self, tz: str, schedule: dict):
        self.tz = ZoneInfo(tz)
        self.schedule = schedule

    def window(self, day: date, prayer: str):
        s = self.schedule
        if not s or not (s["from"] <= day.isoformat() <= s["until"]):
            return None

        def at(key, offset=0):
            return datetime.combine(
                day + timedelta(days=offset), time.fromisoformat(s[key]), self.tz
            )

        end = {
            "fajr": "sunrise",
            "dhuhr": "asr",
            "asr": "maghrib",
            "maghrib": "isha",
            "isha": "fajr",
        }[prayer]
        return at(prayer), at(end, 1 if prayer == "isha" else 0)

    def day_for(self, performed: datetime, prayer: str):
        local = performed.astimezone(self.tz)
        day = local.date()
        previous = self.window(day - timedelta(days=1), prayer)
        if prayer == "isha" and previous and previous[0] <= local < previous[1]:
            return day - timedelta(days=1)
        return day

    def on_time(self, performed: datetime, prayer: str):
        w = self.window(self.day_for(performed, prayer), prayer)
        return None if w is None else w[0] <= performed < w[1]


def daily(attempts, day, timing, now):
    states, valid, on_time = {}, 0, 0
    movement_results = {}
    for prayer in PRAYERS:
        rows = [
            a
            for a in attempts
            if a["prayer"] == prayer
            and timing.day_for(datetime.fromisoformat(a["performed_at"]), prayer) == day
        ]
        scored = [
            a
            for a in rows
            if a.get("movements_expected") and a.get("movements_detected") is not None
        ]
        if scored:
            best = max(
                scored,
                key=lambda a: (
                    a["movements_detected"] / a["movements_expected"],
                    a["performed_at"],
                ),
            )
            movement_results[prayer] = {
                "movements_detected": best["movements_detected"],
                "movements_expected": best["movements_expected"],
                "movement_score": round(
                    100 * best["movements_detected"] / best["movements_expected"], 2
                ),
                "uncertain": bool(best["uncertain"]),
            }
        correct = [a for a in rows if a["valid"] and a["sequence_valid"] and not a["uncertain"]]
        if correct:
            valid += 1
            timely = any(a["on_time"] == 1 for a in correct)
            on_time += int(timely)
            states[prayer] = (
                "ON_TIME"
                if timely
                else (
                    "LATE" if all(a["on_time"] == 0 for a in correct) else "CORRECT_TIMING_UNKNOWN"
                )
            )
        elif rows:
            latest = max(rows, key=lambda a: a["performed_at"])
            states[prayer] = "UNCERTAIN" if latest["uncertain"] else "INCOMPLETE"
        else:
            w = timing.window(day, prayer)
            states[prayer] = "PENDING" if w is None or now < w[1] else "NO_ATTEMPT"
    completed = valid == 5
    detected = sum(r["movements_detected"] for r in movement_results.values())
    expected = sum(r["movements_expected"] for r in movement_results.values())
    return {
        "date": day.isoformat(),
        "states": states,
        "valid_prayers": valid,
        "on_time_prayers": on_time,
        "points": valid * 5 + on_time * 2 + (3 if completed else 0),
        "completed": completed,
        "movement_results": movement_results,
        "movements_detected": detected,
        "movements_expected": expected,
        "movement_score": round(100 * detected / expected, 2) if expected else None,
    }


def progress(attempts, timing, day, now=None):
    now = now or datetime.now(timezone.utc)
    today = daily(attempts, day, timing, now)
    week = [daily(attempts, day - timedelta(days=i), timing, now) for i in range(7)]
    cursor = day if today["completed"] else day - timedelta(days=1)
    streak = 0
    # Bound by actual history, not an arbitrary streak limit.
    earliest = min(
        (timing.day_for(datetime.fromisoformat(a["performed_at"]), a["prayer"]) for a in attempts),
        default=day,
    )
    while cursor >= earliest and daily(attempts, cursor, timing, now)["completed"]:
        streak += 1
        cursor -= timedelta(days=1)
    detected = sum(d["movements_detected"] for d in week)
    expected = sum(d["movements_expected"] for d in week)
    return {
        **today,
        "weekly_movements_detected": detected,
        "weekly_movements_expected": expected,
        "weekly_movement_score": round(100 * detected / expected, 2) if expected else None,
        "weekly_points": sum(d["points"] for d in week),
        "weekly_valid_prayers": sum(d["valid_prayers"] for d in week),
        "weekly_on_time_prayers": sum(d["on_time_prayers"] for d in week),
        "streak": streak,
        "week": week,
    }
