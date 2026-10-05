"""Sampled-frame temporal processing; gaps remain explicit events."""
from .contracts import MovementEvent
from .inference import Observation


def process(observations: list[Observation], *, confidence: float = .65,
            min_observations: int = 1, min_duration_ms: int = 0,
            max_gap_ms: int = 1000) -> list[MovementEvent]:
    ordered = sorted(observations, key=lambda o: o.timestamp_ms)
    if any(b.timestamp_ms <= a.timestamp_ms or b.sequence_index <= a.sequence_index
           for a, b in zip(ordered, ordered[1:])):
        raise ValueError('INVALID_TIMESTAMP_ORDER')
    groups: list[list[Observation]] = []
    events = []
    for item in ordered:
        valid = item.detected and item.confidence >= confidence and item.pose != 'unknown'
        if groups:
            prev = groups[-1][-1]
            previous_valid = prev.detected and prev.confidence >= confidence and prev.pose != 'unknown'
            if item.timestamp_ms - prev.timestamp_ms > max_gap_ms:
                events.append(MovementEvent(event_id='', pose='unknown', start_ms=prev.timestamp_ms,
                              end_ms=item.timestamp_ms, confidence=0,
                              representative_frame_id=None, observation_status='uncertain'))
            elif valid == previous_valid and (not valid or item.pose == prev.pose):
                groups[-1].append(item)
                continue
        groups.append([item])
    for group in groups:
        start, end = group[0], group[-1]
        stable = (start.detected and start.pose != 'unknown' and start.confidence >= confidence
                  and len(group) >= min_observations
                  and end.timestamp_ms - start.timestamp_ms >= min_duration_ms)
        # Prefer interior high confidence frames; endpoints only for short runs.
        candidates = group
        representative = max(candidates, key=lambda x: x.confidence)
        guesses = [x for x in group if x.detected and x.pose != 'unknown']
        candidate = representative if stable else max(guesses, key=lambda x: x.confidence, default=None)
        events.append(MovementEvent(event_id='', pose=start.pose if stable else 'unknown',
                      start_ms=start.timestamp_ms, end_ms=end.timestamp_ms,
                      confidence=sum(x.confidence for x in group) / len(group),
                      representative_frame_id=candidate.frame_id if candidate else None,
                      candidate_pose=candidate.pose if candidate else None,
                      candidate_confidence=candidate.confidence if candidate else None,
                      candidate_timestamp_ms=candidate.timestamp_ms if candidate else None,
                      observation_status='detected' if stable else 'uncertain'))
    events.sort(key=lambda e: (e.start_ms, e.end_ms))
    return [e.model_copy(update={'event_id': f'evt_{i:04d}'}) for i, e in enumerate(events)]
