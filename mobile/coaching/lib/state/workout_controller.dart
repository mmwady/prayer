// ─────────────────────────────────────────────────────────────────────────────
// workout_controller.dart
//
// The client-side session brain.
//
// It loads both:
//   • movement templates from /api/v1/templates
//   • exercise rules from /api/v1/exercise-rules/<exercise>
//
// Templates answer: "what does a good rep look like?"
// Rules answer: "what invalid variants / form faults should we reject?"
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/coaching_reply.dart';
import '../models/keypoint.dart';
import '../models/pose_event.dart';
import '../services/audio_player.dart';
import '../services/form_analyzer.dart';
import '../services/pose_detector.dart';
import '../services/rep_counter.dart';
import '../services/ws_client.dart';

class WorkoutController extends ChangeNotifier {
  WorkoutController({
    required this.exercise,
    required this.detector,
    required this.ws,
    required this.audio,
    FormAnalyzer? analyzer,
  }) : analyzer = analyzer ?? FormAnalyzer() {
    _repCounter = DtwRepCounter(templateSequence: []);
  }

  final String exercise;
  final PoseDetector detector;
  final WsClient ws;
  final CoachingAudioPlayer audio;
  final FormAnalyzer analyzer;

  SequenceRepCounter _repCounter = DtwRepCounter(templateSequence: []);

  List<Keypoint> _keypoints = const <Keypoint>[];
  PoseEvent? _lastFault;
  DateTime _faultUntil = DateTime.fromMillisecondsSinceEpoch(0);
  int _repCount = 0;
  int _perfectReps = 0;
  int _faultsThisSet = 0;
  String? _lastCaption;

  StreamSubscription<List<Keypoint>>? _poseSub;
  StreamSubscription<CoachingReply>? _wsSub;

  List<Keypoint> get keypoints => _keypoints;
  int get repCount => _repCount;
  int get perfectReps => _perfectReps;
  String? get lastCaption => _lastCaption;

  List<String> get faultyJoints {
    if (_lastFault == null) return const [];
    if (DateTime.now().isAfter(_faultUntil)) return const [];
    return _lastFault!.faultyJoints;
  }

  /// Phase 1: connect WebSocket, templates, and exercise rules.
  /// Detector startup stays separate because browsers require a user gesture.
  Future<void> startWithoutDetector() async {
    await ws.connect();

    try {
      final uri = Uri.parse(ws.url);
      final httpUrl = '${uri.scheme == 'wss' ? 'https' : 'http'}://${uri.authority}';
      final targetExercise = exercise.toLowerCase();

      await _loadExerciseRules(httpUrl, targetExercise);
      await _loadTemplates(httpUrl, targetExercise);
    } catch (e) {
      debugPrint('Failed to load exercise configuration: $e');
    }

    _wsSub = ws.stream.listen(_onServerFrame);
  }

  Future<void> _loadExerciseRules(String httpUrl, String targetExercise) async {
    final rulesUrl = Uri.parse('$httpUrl/api/v1/exercise-rules/$targetExercise');
    final response = await http.get(rulesUrl);

    if (response.statusCode != 200) {
      debugPrint('No exercise rules found for $targetExercise');
      return;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final rules = data['rules'];
    if (rules is Map<String, dynamic> && rules.isNotEmpty) {
      analyzer.setExerciseRules(rules);
      debugPrint('Loaded exercise rules for $targetExercise');
    }
  }

  Future<void> _loadTemplates(String httpUrl, String targetExercise) async {
    final apiUrl = Uri.parse('$httpUrl/api/v1/templates');
    final response = await http.get(apiUrl);

    if (response.statusCode != 200) {
      debugPrint('Failed to load templates API: ${response.statusCode}');
      return;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final templatesMap = data['templates'] as Map<String, dynamic>?;

    if (templatesMap == null || !templatesMap.containsKey(targetExercise)) {
      debugPrint('No generated template found for $targetExercise');
      return;
    }

    final exerciseData = templatesMap[targetExercise] as List<dynamic>;
    final parsedTemplate = <List<Keypoint>>[];

    for (final frameData in exerciseData) {
      final pointsData = frameData as List<dynamic>;
      final framePoints = <Keypoint>[];

      for (final pt in pointsData) {
        final ptMap = pt as Map<String, dynamic>;
        framePoints.add(Keypoint(
          id: KeypointId.values.byName(ptMap['id'] as String),
          x: (ptMap['x'] as num).toDouble(),
          y: (ptMap['y'] as num).toDouble(),
          confidence: (ptMap['confidence'] as num).toDouble(),
        ));
      }

      parsedTemplate.add(framePoints);
    }

    _repCounter = DtwRepCounter(templateSequence: parsedTemplate);
    analyzer.setTemplate(parsedTemplate);
    debugPrint('Loaded templates for $targetExercise: ${parsedTemplate.length} frames');
  }

  Future<void> startDetector() async {
    _poseSub = detector.stream.listen(_onPose);
    await detector.start();
  }

  Future<void> finishSet() async {
    if (_faultsThisSet == 0 && _repCount > 0) {
      _perfectReps += _repCount;
      ws.send(PerfectSet(exercise: exercise, reps: _repCount));
    }
    _faultsThisSet = 0;
    _repCount = 0;
    _repCounter.reset();
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    await _poseSub?.cancel();
    await _wsSub?.cancel();
    await detector.stop();
    await ws.close();
    await audio.dispose();
    super.dispose();
  }

  void _onPose(List<Keypoint> kp) {
    _keypoints = kp;

    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final fault = analyzer.analyze(
      exercise: exercise,
      keypoints: kp,
      repCount: _repCount,
      now: now,
    );

    if (fault != null) {
      _lastFault = fault;
      _faultUntil = DateTime.now().add(const Duration(milliseconds: 1200));
      _faultsThisSet += 1;

      // Important: invalid movement should not be allowed to finish an in-flight
      // repetition. This makes the HUD show valid reps only.
      _repCounter.reset();

      ws.send(fault);
      notifyListeners();
      return;
    }

    if (_repCounter.checkRepPattern(kp)) {
      _repCount++;
    }

    notifyListeners();
  }

  void _onServerFrame(CoachingReply reply) {
    switch (reply.kind) {
      case ReplyKind.audio:
        if (reply.audioBytes != null) {
          unawaited(audio.feed(reply.audioBytes!));
        }
      case ReplyKind.caption:
        _lastCaption = reply.captionText;
        unawaited(audio.seal());
        notifyListeners();
      case ReplyKind.summary:
        break;
    }
  }
}
