"""Forward temporal assignment in normalized mode; conservative raw alignment.

Repeated physical poses can fit multiple rakahs/stations. A greedy next-station
algorithm invents certainty; an ambiguous optimal alignment instead stays unconfirmed.
"""
from .contracts import (AnalysisReport, Metrics, MOCK_NOTICE, RakahReport, Result,
                        StationReport, StationStatus, UnexpectedMovement)
from .domain import LABELS, STATION_POSES, stations


def analyze(analysis_id, prayer, events, provider, sample_fps, frame_count, model_version='mock-v1', *,
            normalize_sequence=False, transition_anchors=False, _configuration=None):
    configuration = stations(prayer) if _configuration is None else _configuration
    expected = [(ri, s) for ri, row in enumerate(configuration) for s in row]
    detected = [e for e in events if e.observation_status == 'detected']
    if normalize_sequence:
        # An opening gesture anchors the recording; preparation before it and
        # leaving the frame after terminal salam are outside the assessed sequence.
        openings = [i for i, e in enumerate(detected) if e.pose == 'takbir']
        if openings and configuration[0][0] == 'takbir':
            detected = detected[openings[0]:]
        terminal = next((i for i in range(len(detected)-1, -1, -1) if detected[i].pose == 'salam_left'
                         and any(p.pose == 'salam_right' for p in detected[:i])), None)
        if terminal is not None:
            detected = detected[:terminal + 1]
            right = max(i for i, e in enumerate(detected[:terminal]) if e.pose == 'salam_right')
            # Sitting between directional gestures is their shared body posture.
            detected = [e for i, e in enumerate(detected)
                        if not (i > right and e.pose == 'sitting')]
        # Transition takbir is observed but does not introduce another opening.
        detected = [e for i, e in enumerate(detected) if e.pose != 'takbir' or i == 0]
        merged = []
        for event in detected:
            bridge = (merged and any(e.pose == 'takbir' and
                      merged[-1].end_ms <= e.start_ms <= event.start_ms for e in events))
            separator = merged and any(merged[-1].end_ms < e.start_ms < event.start_ms
                        and (e.candidate_pose or e.pose) not in ('unknown', 'takbir', event.pose)
                        for e in events)
            if (merged and merged[-1].pose == event.pose
                    and not separator
                    and (event.start_ms - merged[-1].end_ms <= 1000 or bridge)):
                previous = merged[-1]
                representative = max((previous, event), key=lambda e: e.candidate_confidence if e.candidate_confidence is not None else e.confidence)
                merged[-1] = representative.model_copy(update={
                    'start_ms': previous.start_ms,
                    'end_ms': event.end_ms,
                    'confidence': representative.candidate_confidence if representative.candidate_confidence is not None else representative.confidence,
                    'representative_frame_id': representative.representative_frame_id})
            else:
                merged.append(event)
        detected = merged
    n, m = len(detected), len(expected)
    leading = None
    if normalize_sequence and _configuration is not None and configuration[0][0] == 'standing':
        for i, event in enumerate(detected):
            if event.pose == 'standing':
                leading = i
                break
            if event.pose not in ('takbir', 'sitting'):
                break
    def matches(i, j):
        if leading is not None and (j == 0 or i == leading):
            return i == leading and j == 0
        return detected[i].pose == STATION_POSES[expected[j][1]]
    prefix = [[0] * (m + 1) for _ in range(n + 1)]
    suffix = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n):
        for j in range(m):
            match = matches(i, j)
            prefix[i+1][j+1] = max(prefix[i][j+1], prefix[i+1][j],
                                   prefix[i][j] + int(match))
    for i in range(n-1, -1, -1):
        for j in range(m-1, -1, -1):
            match = matches(i, j)
            suffix[i][j] = max(suffix[i+1][j], suffix[i][j+1],
                               suffix[i+1][j+1] + int(match))
    best = suffix[0][0]
    candidates = {j: [i for i in range(n)
                      if matches(i, j)
                      and prefix[i][j] + 1 + suffix[i+1][j+1] == best] for j in range(m)}
    reverse = {i: [j for j in range(m) if i in candidates[j]] for i in range(n)}
    confirmed, used = {}, set()
    for j, options in candidates.items():
        optional = any(prefix[i][j] + suffix[i][j+1] == best for i in range(n+1))
        if len(options) == 1 and len(reverse[options[0]]) == 1 and not optional:
            confirmed[j] = detected[options[0]]
            used.add(options[0])
    # Optional partial-recording aid: witnessed standing/bowing/standing after
    # a floor phase can anchor a new row, without confirming missing floor poses.
    if transition_anchors and len(configuration) > 1:
        floor_seen = False
        triplets = []
        for i in range(len(detected)-2):
            if detected[i].pose in ('sujood', 'sitting'):
                floor_seen = True
            if floor_seen and [e.pose for e in detected[i:i+3]] == ['standing', 'ruku', 'standing']:
                triplets.append(i)
                floor_seen = False
        if len(triplets) == len(configuration)-1:
            for ri, i in enumerate(triplets, 1):
                base = sum(len(row) for row in configuration[:ri])
                for step in range(3):
                    j = base + step
                    if j not in confirmed and i+step not in used:
                        confirmed[j] = detected[i+step]
                        used.add(i+step)
    if normalize_sequence:
        confirmed, used = {}, set()
        starts = [0]
        floor_seen = seated_seen = False
        for i, event in enumerate(detected):
            floor_seen |= event.pose == 'sujood'
            seated_seen |= event.pose == 'sitting'
            if (event.pose == 'standing' and floor_seen and seated_seen
                    and i+2 < n and detected[i+1].pose == 'ruku'
                    and detected[i+2].pose == 'standing'
                    and len(starts) < len(configuration)):
                starts.append(i)
                floor_seen = seated_seen = False
        starts.append(n)
        base = 0
        for ri, row in enumerate(configuration):
            if ri >= len(starts)-1:
                break
            indices = list(range(starts[ri], starts[ri+1]))
            poses = [STATION_POSES[s] for s in row]
            size, width = len(indices), len(row)
            score = [[0]*(width+1) for _ in range(size+1)]
            def weight(i):
                event = detected[indices[i]]
                confidence = event.candidate_confidence if event.candidate_confidence is not None else event.confidence
                return (n+1)*1001 + round(confidence*1000)
            for i in range(size-1, -1, -1):
                for j in range(width-1, -1, -1):
                    score[i][j] = max(score[i+1][j], score[i][j+1])
                    if detected[indices[i]].pose == poses[j]:
                        score[i][j] = max(score[i][j], weight(i)+score[i+1][j+1])
            i = j = 0
            while i < size and j < width:
                if detected[indices[i]].pose == poses[j] and weight(i)+score[i+1][j+1] == score[i][j]:
                    confirmed[base+j] = detected[indices[i]]
                    used.add(indices[i])
                    i += 1
                    j += 1
                elif score[i+1][j] == score[i][j]:
                    i += 1
                else:
                    j += 1
            base += width
    rows, offset = [], 0
    for ri, row in enumerate(configuration):
        reports = []
        for s in row:
            event = confirmed.get(offset)
            reports.append(StationReport(station=s, arabic_label=LABELS[s],
                status=StationStatus.DETECTED if event else StationStatus.UNCONFIRMED,
                confidence=(event.candidate_confidence if event.candidate_confidence is not None else event.confidence) if event else None,
                timestamp_ms=(event.candidate_timestamp_ms if event.candidate_timestamp_ms is not None else event.start_ms) if event else None,
                event_id=event.event_id if event else None))
            offset += 1
        complete = all(s.status == StationStatus.DETECTED for s in reports)
        rows.append(RakahReport(rakah_number=ri+1,
            result=Result.OBSERVED_COMPLETE if complete else Result.REVIEW_REQUIRED,
            stations=reports, notes=[f'لم نتمكن من تأكيد {s.arabic_label} من الصور المتاحة.'
                                     for s in reports if s.status == StationStatus.UNCONFIRMED]))
    unexpected = [UnexpectedMovement(event_id=e.event_id, pose=e.pose, start_ms=e.start_ms,
                  confidence=e.candidate_confidence if e.candidate_confidence is not None else e.confidence,
                  timestamp_ms=e.candidate_timestamp_ms,
                  reason='ambiguous' if not normalize_sequence and reverse[i] else 'out_of_sequence_or_repeated')
                  for i, e in enumerate(detected) if i not in used]
    uncertain = (not normalize_sequence and
                 any(e.observation_status == 'uncertain' for e in events))
    anchors = sorted((e.start_ms, expected[j][0] + 1) for j, e in confirmed.items())
    boundaries = []
    base = 0
    for ri, row in enumerate(configuration[:-1]):
        if all(j in confirmed for j in range(base, base+len(row))):
            boundaries.append((confirmed[base+len(row)-1].end_ms, ri+2))
        base += len(row)
    # Review placement is temporal context only, never station confirmation.
    for item in [*unexpected, *events]:
        if not anchors:
            continue
        preceding = [a for a in anchors if a[0] <= item.start_ms]
        number = preceding[-1][1] if preceding else anchors[0][1]
        for end, next_number in boundaries:
            if item.start_ms > end:
                number = max(number, next_number)
        row = rows[number-1].stations
        slot = next((i for i, s in enumerate(row)
                     if s.timestamp_ms is not None and s.timestamp_ms > item.start_ms), len(row))
        item.review_rakah_number = number
        item.review_before_station_index = slot
    completed = sum(r.result == Result.OBSERVED_COMPLETE for r in rows)
    return AnalysisReport(analysis_id=analysis_id, prayer=prayer, expected_rakahs=len(rows),
        observed_rakahs=completed, analysis_mode=provider, synthetic=provider == 'mock',
        notice=MOCK_NOTICE if provider == 'mock' else 'تحليل ترتيب الحركات المرصودة، دون حكم على صحة الصلاة.',
        overall_result=Result.OBSERVED_COMPLETE if completed == len(rows) and not unexpected and not uncertain
                       else Result.REVIEW_REQUIRED,
        rakahs=rows, events=events, unexpected_movements=unexpected,
        metrics=Metrics(detected_stations=len(confirmed), unconfirmed_stations=m-len(confirmed),
                        unexpected_movements=len(unexpected), processed_frames=frame_count,
                        sample_fps=sample_fps, inference_provider=provider,
                        model_version=model_version))
