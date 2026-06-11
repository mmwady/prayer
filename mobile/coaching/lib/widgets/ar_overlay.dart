// ─────────────────────────────────────────────────────────────────────────────
// ar_overlay.dart
//
// Stick-figure AR overlay painted on top of the live camera preview.
//
// Two things here:
//   1. A [CustomPainter] that draws bones + joints from a list of normalized
//      keypoints, coloring any joint listed in `faultyJoints` red.
//   2. A widget that ties a pulse animation (via [AnimationController]) to
//      the faulty joints so they don't just turn red — they *breathe*, which
//      is what actually draws the user's eye mid-workout.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../models/keypoint.dart';

class ArOverlay extends StatefulWidget {
  const ArOverlay({
    super.key,
    required this.keypoints,
    required this.faultyJoints,
  });

  /// Current skeleton (normalized coordinates 0..1).
  final List<Keypoint> keypoints;

  /// Names of faulty joints — see [JointTag]. The painter maps these to
  /// [KeypointId]s internally.
  final List<String> faultyJoints;

  @override
  State<ArOverlay> createState() => _ArOverlayState();
}

class _ArOverlayState extends State<ArOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    // 600ms pulse period — slow enough to look deliberate, fast enough to
    // register as "attention needed" rather than "decorative".
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // `AnimatedBuilder` rebuilds only the painter each tick — cheap enough
    // to run at screen refresh rate. The painter itself is not const, since
    // it captures dynamic inputs, but it IS repaintable only via the Listen-
    // able pulse value, avoiding a full widget rebuild.
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        return CustomPaint(
          painter: _SkeletonPainter(
            keypoints: widget.keypoints,
            faultyIds: _tagsToIds(widget.faultyJoints),
            pulse: _pulse.value,
          ),
          // An empty `Size.infinite` child makes the painter fill its parent,
          // which is exactly the stacked camera preview.
          size: Size.infinite,
        );
      },
    );
  }

  /// Map string joint tags (sent over the wire) back to [KeypointId]s.
  /// A short, explicit table is clearer than `values.byName` because the
  /// wire tags use snake_case.
  static Set<KeypointId> _tagsToIds(List<String> tags) {
    const Map<String, KeypointId> mapping = {
      JointTag.spineMid: KeypointId.spineMid,
      JointTag.leftKnee: KeypointId.leftKnee,
      JointTag.rightKnee: KeypointId.rightKnee,
      JointTag.leftHip: KeypointId.leftHip,
      JointTag.rightHip: KeypointId.rightHip,
    };
    return {
      for (final t in tags)
        if (mapping[t] != null) mapping[t]!,
    };
  }
}

class _SkeletonPainter extends CustomPainter {
  _SkeletonPainter({
    required this.keypoints,
    required this.faultyIds,
    required this.pulse,
  });

  final List<Keypoint> keypoints;
  final Set<KeypointId> faultyIds;
  final double pulse; // 0..1, used to oscillate the faulty joint radius.

  static const Color _good = Color(0xFF00E676); // Material green A400.
  static const Color _bad = Color(0xFFFF1744);  // Material red A400.

  @override
  void paint(Canvas canvas, Size size) {
    if (keypoints.isEmpty) return;
    final index = <KeypointId, Keypoint>{for (final k in keypoints) k.id: k};

    // ── Bones ──────────────────────────────────────────────────────────
    final bonePaint = Paint()
      ..color = _good
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    for (final bone in skeletonBones) {
      final a = index[bone.$1];
      final b = index[bone.$2];
      if (a == null || b == null) continue;
      // Hide low-confidence bones — a flickery bone is worse than no bone.
      if (a.confidence < 0.3 || b.confidence < 0.3) continue;

      // A bone inherits "bad" color if EITHER endpoint is faulty. That's
      // what makes a bad spine light up both bones attached to it.
      final isBad = faultyIds.contains(a.id) || faultyIds.contains(b.id);
      bonePaint.color = isBad ? _bad : _good;

      canvas.drawLine(
        Offset(a.x * size.width, a.y * size.height),
        Offset(b.x * size.width, b.y * size.height),
        bonePaint,
      );
    }

    // ── Joints ─────────────────────────────────────────────────────────
    final jointPaint = Paint()..style = PaintingStyle.fill;
    for (final k in keypoints) {
      if (k.confidence < 0.3) continue;
      final bad = faultyIds.contains(k.id);
      jointPaint.color = bad ? _bad : _good;

      // Pulse: oscillate a faulty joint's radius between base and +60%.
      // Good joints stay at base radius — a steady-state skeleton reduces
      // visual noise so the user's eye catches the pulsing joint.
      final baseR = 6.0;
      final radius = bad ? baseR + baseR * 0.6 * pulse : baseR;

      canvas.drawCircle(
        Offset(k.x * size.width, k.y * size.height),
        radius,
        jointPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SkeletonPainter oldDelegate) {
    // Repaint on every pulse tick (cheap) OR whenever input changes.
    return true;
  }
}
