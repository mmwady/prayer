// ─────────────────────────────────────────────────────────────────────────────
// pose_event.dart
//
// Dart mirror of the backend's `PoseEvent` / `PerfectSet` / `SessionEnd`
// discriminated union (see backend/app/schemas.py). Keeping the shape in
// sync by hand is acceptable given how narrow this contract is — and the
// backend's `test_ws_contract.py` will flag drift if a name changes.
// ─────────────────────────────────────────────────────────────────────────────

/// Fault signal sent upstream when the [FormAnalyzer] detects a bad rep.
class PoseEvent {
  const PoseEvent({
    required this.exercise,
    required this.error,
    required this.faultyJoints,
    required this.repCount,
    required this.t,
  });

  final String exercise;
  final String error;
  final List<String> faultyJoints;
  final int repCount;
  final double t; // Unix seconds — used by the server cooldown logic.

  /// JSON form of the event — keys match the backend exactly.
  Map<String, dynamic> toJson() => {
        'type': 'pose_event',
        'exercise': exercise,
        'error': error,
        'faulty_joints': faultyJoints,
        'rep_count': repCount,
        't': t,
      };
}

/// Sent when the user finishes a set with zero detected faults. Triggers a
/// celebratory reply on the backend.
class PerfectSet {
  const PerfectSet({required this.exercise, required this.reps});
  final String exercise;
  final int reps;

  Map<String, dynamic> toJson() => {
        'type': 'perfect_set',
        'exercise': exercise,
        'reps': reps,
      };
}

/// Sent when the user ends the workout — prompts the server to flush the
/// final summary frame and close the socket.
class SessionEnd {
  const SessionEnd();
  Map<String, dynamic> toJson() => const {'type': 'session_end'};
}
