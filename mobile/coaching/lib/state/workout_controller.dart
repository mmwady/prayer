// ─────────────────────────────────────────────────────────────────────────────
// workout_controller.dart
//
// The "session brain" on the client side.
//
// Holds:
//   • The live keypoint stream from the [PoseDetector].
//   • The most-recent [PoseEvent] fault (drives the red-joint overlay).
//   • The rep counter and perfect-rep streak (drives the HUD + `perfect_set`).
//   • The WebSocket client and the audio player; wires incoming frames into
//     the audio player and exposes the latest caption to the UI.
//
// Using `ChangeNotifier` + `provider` keeps the dependency graph minimal —
// no need for Riverpod in a boilerplate scaffold. Swap later if the state
// tree grows.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:flutter/foundation.dart';

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
    // Initialize with an empty template sequence first.
    // We will dynamically override this in `start()` once the API response is fetched.
    _repCounter = DtwRepCounter(templateSequence: []);
  }

  final String exercise;
  final PoseDetector detector;
  final WsClient ws;
  final CoachingAudioPlayer audio;
  final FormAnalyzer analyzer;

  // Holds the specific Action Recognition strategy implementation.
  // Overridden once the templates JSON is loaded over HTTP.
  SequenceRepCounter _repCounter = DtwRepCounter(templateSequence: []);

  List<Keypoint> _keypoints = const <Keypoint>[];
  PoseEvent? _lastFault; // Drives the red pulsing joints.
  DateTime _faultUntil = DateTime.fromMillisecondsSinceEpoch(0);
  int _repCount = 0;
  int _perfectReps = 0;
  int _faultsThisSet = 0;
  String? _lastCaption;

  StreamSubscription<List<Keypoint>>? _poseSub;
  StreamSubscription<CoachingReply>? _wsSub;

  // ── Public read-only state ────────────────────────────────────────────
  List<Keypoint> get keypoints => _keypoints;
  int get repCount => _repCount;
  int get perfectReps => _perfectReps;
  String? get lastCaption => _lastCaption;

  /// Joints currently flagged as faulty. Empty list == everything green.
  /// The fault marker expires automatically after ~1.2s so a transient
  /// issue doesn't leave the skeleton red for the rest of the set.
  List<String> get faultyJoints {
    if (_lastFault == null) return const [];
    if (DateTime.now().isAfter(_faultUntil)) return const [];
    return _lastFault!.faultyJoints;
  }

  /// Phase 1: Connect WS and fetch templates. Safe to call from initState.
  /// Does NOT start the detector because on web that would trigger a file
  /// picker, which the browser only allows from a real user gesture.
  Future<void> startWithoutDetector() async {
    await ws.connect();

    try {
      // Dynamically load the exercise template from the FastAPI backend.
      // We map the WebSocket URL back to an HTTP URL for the REST endpoint.
      final uri = Uri.parse(ws.url);
      final httpUrl = '${uri.scheme == 'wss' ? 'https' : 'http'}://${uri.authority}';
      final apiUrl = Uri.parse('$httpUrl/api/v1/templates');

      // Use package:http for cross-platform compatibility (Web + Mobile)
      final response = await http.get(apiUrl);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        final templatesMap = data['templates'] as Map<String, dynamic>?;
        final targetExercise = exercise.toLowerCase();

        if (templatesMap != null && templatesMap.containsKey(targetExercise)) {
          final exerciseData = templatesMap[targetExercise] as List<dynamic>;

          final List<List<Keypoint>> parsedTemplate = [];
          for (var frameData in exerciseData) {
            final pointsData = frameData as List<dynamic>;
            final framePoints = <Keypoint>[];
            for (var pt in pointsData) {
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

          // Re-initialize with the full sequence
          _repCounter = DtwRepCounter(templateSequence: parsedTemplate);
          analyzer.setTemplate(parsedTemplate);
          debugPrint(
              'Successfully loaded custom DTW template for $targetExercise');
        } else {
          debugPrint(
              'No generated template found for $targetExercise, falling back to empty template');
        }
      }
    } catch (e) {
      debugPrint('Failed to load exercise templates API: $e');
    }

    _wsSub = ws.stream.listen(_onServerFrame);
    // Note: detector is NOT started here — call startDetector() separately.
  }

  /// Phase 2: Start the pose detector stream.
  /// Must be called from a user gesture on web so the browser allows the
  /// file picker. Also starts listening to the detector's keypoint stream.
  Future<void> startDetector() async {
    _poseSub = detector.stream.listen(_onPose);
    await detector.start();
  }

  /// Called by the UI when the user ends the set. Flushes counters to the
  /// server and, if the set was flawless, also sends a `perfect_set` event
  /// to trigger an enthusiastic reply.
  Future<void> finishSet() async {
    if (_faultsThisSet == 0 && _repCount > 0) {
      _perfectReps += _repCount;
      ws.send(PerfectSet(exercise: exercise, reps: _repCount));
    }
    _faultsThisSet = 0;
    _repCount = 0;
    notifyListeners();
  }

  /// Tear down. Safe to call more than once.
  @override
  Future<void> dispose() async {
    await _poseSub?.cancel();
    await _wsSub?.cancel();
    await detector.stop();
    await ws.close();
    await audio.dispose();
    super.dispose();
  }

  // ── Private ────────────────────────────────────────────────────────────

  void _onPose(List<Keypoint> kp) {
    _keypoints = kp;

    // Evaluate the incoming frame against our action recognition sliding window.
    // It returns true when the dynamic sequence aligns with a completed rep.
    if (_repCounter.checkRepPattern(kp)) {
      _repCount++;
      notifyListeners();
    }

    // Run the analyzer on every frame — cheap, and lets us flag faults the
    // moment they happen. The backend's cooldown takes care of rate-limiting
    // audio replies; here we just need the freshest signal for the overlay.
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final fault = analyzer.analyze(
      exercise: exercise,
      keypoints: kp,
      repCount: _repCount,
      now: now,
    );

    if (fault != null) {
      _lastFault = fault;
      // Show the red pulse for 1.2s; long enough to be noticed, short enough
      // that it fades before the next rep.
      _faultUntil = DateTime.now().add(const Duration(milliseconds: 1200));
      _faultsThisSet += 1;
      ws.send(fault);
    }

    notifyListeners();
  }

  void _onServerFrame(CoachingReply reply) {
    switch (reply.kind) {
      case ReplyKind.audio:
        // Pipe straight into the streaming player — it will start playback
        // on the first chunk.
        if (reply.audioBytes != null) {
          // Fire-and-forget: audio feed is async but we don't need to await
          // here. Failures are rare and self-correct on the next reply.
          unawaited(audio.feed(reply.audioBytes!));
        }
      case ReplyKind.caption:
        _lastCaption = reply.captionText;
        // Seal the buffer so the next TTS reply starts with a fresh source.
        unawaited(audio.seal());
        notifyListeners();
      case ReplyKind.summary:
        // The summary arrives just before the server closes. The UI can
        // navigate to a stats screen using `reply.summary` — wiring that
        // route is out of scope for this boilerplate.
        break;
    }
  }
}
