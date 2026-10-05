import 'dart:async';
import 'package:flutter/material.dart';
import '../models/keypoint.dart';
import '../services/pose_detector.dart';
import 'prayer_definition.dart';

/// Explicit synthetic developer mode. Never selected as real pose evidence.
class PrayerDemoDetector extends PoseDetector {
  PrayerDemoDetector(this.definition);
  final PrayerDefinition definition;
  final _frames = StreamController<List<Keypoint>>.broadcast();
  Timer? _timer;
  int _tick = 0;
  @override
  Stream<List<Keypoint>> get stream => _frames.stream;
  @override
  Widget buildPreview() =>
      const Center(child: Text('محاكاة للتجربة — ليست رصداً بالكاميرا'));
  @override
  Future<void> start() async {
    final stations = definition.rakahs.expand((r) => r.stations).toList();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final index = _tick++ ~/ 15;
      if (index >= stations.length) {
        _timer?.cancel();
        return;
      }
      _frames.add(syntheticPrayerKeypoints(stations[index].pose));
    });
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _frames.close();
  }
}

/// Geometric fixtures shared with tests, not a trained model or camera output.
List<Keypoint> syntheticPrayerKeypoints(PrayerPose pose) {
  final coordinates = switch (pose) {
    PrayerPose.standing => [
        (0.50, 0.20),
        (0.50, 0.45),
        (0.50, 0.67),
        (0.50, 0.90)
      ],
    PrayerPose.ruku => [(0.24, 0.45), (0.50, 0.45), (0.50, 0.67), (0.50, 0.90)],
    PrayerPose.sitting => [
        (0.50, 0.27),
        (0.50, 0.52),
        (0.72, 0.72),
        (0.42, 0.75)
      ],
    PrayerPose.sujood => [
        (0.30, 0.78),
        (0.50, 0.48),
        (0.65, 0.72),
        (0.40, 0.78)
      ],
    PrayerPose.unknown => <(double, double)>[],
  };
  if (coordinates.isEmpty) return [];
  const ids = [
    KeypointId.leftShoulder,
    KeypointId.leftHip,
    KeypointId.leftKnee,
    KeypointId.leftAnkle
  ];
  return List.generate(
      4,
      (i) => Keypoint(
          id: ids[i],
          x: coordinates[i].$1,
          y: coordinates[i].$2,
          confidence: 0.95));
}
