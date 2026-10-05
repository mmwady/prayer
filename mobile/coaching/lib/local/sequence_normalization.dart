import 'dart:math' as math;

/// Port of the optional Python sequence normalization. Input events stay intact.
List<Map<String, dynamic>> normalizeLocalEvents(
    List<Map<String, dynamic>> events) {
  var detected = events
      .where((e) => e['observation_status'] == 'detected')
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  final opening = detected.indexWhere((e) => e['pose'] == 'takbir');
  if (opening >= 0) detected = detected.sublist(opening);
  // An isolated directional prediction during floor movements is not the end.
  final terminal = detected.lastIndexWhere((e) =>
      e['pose'] == 'salam_left' &&
      detected.takeWhile((p) => p != e).any((p) => p['pose'] == 'salam_right'));
  if (terminal >= 0) {
    detected = detected.sublist(0, terminal + 1);
    final right = detected.lastIndexWhere((e) => e['pose'] == 'salam_right');
    detected = detected.indexed
        .where((p) => !(p.$1 > right && p.$2['pose'] == 'sitting'))
        .map((p) => p.$2)
        .toList();
  }
  detected = detected.indexed
      .where((p) => p.$2['pose'] != 'takbir' || p.$1 == 0)
      .map((p) => p.$2)
      .toList();
  final merged = <Map<String, dynamic>>[];
  for (final event in detected) {
    final previous = merged.isEmpty ? null : merged.last;
    final bridge = previous != null &&
        events.any((e) =>
            e['pose'] == 'takbir' &&
            (previous['end_ms'] as int) <= (e['start_ms'] as int) &&
            (e['start_ms'] as int) <= (event['start_ms'] as int));
    final separator = previous != null &&
        events.any((e) =>
            (previous['end_ms'] as int) < (e['start_ms'] as int) &&
            (e['start_ms'] as int) < (event['start_ms'] as int) &&
            !['unknown', 'takbir', event['pose']]
                .contains(e['candidate_pose'] ?? e['pose']));
    if (previous != null &&
        previous['pose'] == event['pose'] &&
        !separator &&
        ((event['start_ms'] as int) - (previous['end_ms'] as int) <= 1000 ||
            bridge)) {
      final representative =
          _confidence(previous) >= _confidence(event) ? previous : event;
      merged[merged.length - 1] = {
        ...representative,
        'start_ms': previous['start_ms'],
        'end_ms': event['end_ms'],
        'confidence': _confidence(representative)
      };
    } else {
      merged.add(event);
    }
  }
  return merged;
}

double _confidence(Map<String, dynamic> e) =>
    ((e['candidate_confidence'] ?? e['confidence']) as num).toDouble();

Map<int, Map<String, dynamic>> normalizedLocalAlignment(
    List<List<String>> rows,
    List<Map<String, dynamic>> detected,
    String Function(String) stationPose,
    Set<int> used) {
  final n = detected.length, starts = <int>[0];
  var floorSeen = false, seatedSeen = false;
  for (var i = 0; i < n; i++) {
    final pose = detected[i]['pose'];
    floorSeen |= pose == 'sujood';
    seatedSeen |= pose == 'sitting';
    if (pose == 'standing' &&
        floorSeen &&
        seatedSeen &&
        i + 2 < n &&
        detected[i + 1]['pose'] == 'ruku' &&
        detected[i + 2]['pose'] == 'standing' &&
        starts.length < rows.length) {
      starts.add(i);
      floorSeen = seatedSeen = false;
    }
  }
  starts.add(n);
  final confirmed = <int, Map<String, dynamic>>{};
  var base = 0;
  for (var r = 0; r < rows.length && r < starts.length - 1; r++) {
    final row = rows[r],
        indices =
            List.generate(starts[r + 1] - starts[r], (i) => starts[r] + i),
        poses = row.map(stationPose).toList(),
        size = indices.length,
        width = row.length;
    final score = List.generate(size + 1, (_) => List.filled(width + 1, 0));
    int weight(int i) =>
        (n + 1) * 1001 + _pythonRound(_confidence(detected[indices[i]]) * 1000);
    for (var i = size - 1; i >= 0; i--) {
      for (var j = width - 1; j >= 0; j--) {
        score[i][j] = math.max(score[i + 1][j], score[i][j + 1]);
        if (detected[indices[i]]['pose'] == poses[j]) {
          score[i][j] = math.max(score[i][j], weight(i) + score[i + 1][j + 1]);
        }
      }
    }
    var i = 0, j = 0;
    while (i < size && j < width) {
      if (detected[indices[i]]['pose'] == poses[j] &&
          weight(i) + score[i + 1][j + 1] == score[i][j]) {
        confirmed[base + j] = detected[indices[i]];
        used.add(indices[i]);
        i++;
        j++;
      } else if (score[i + 1][j] == score[i][j]) {
        i++;
      } else {
        j++;
      }
    }
    base += width;
  }
  return confirmed;
}

// Python round uses ties to even, unlike Dart's round.
int _pythonRound(double value) {
  final floor = value.floor(), fraction = value - value.floor();
  return fraction == .5 ? (floor.isEven ? floor : floor + 1) : value.round();
}
