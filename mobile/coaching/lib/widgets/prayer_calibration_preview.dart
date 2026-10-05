import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/keypoint.dart';
import '../prayer/prayer_reference.dart';
import '../services/pose_detector.dart';
import '../ui/app_theme.dart';
import '../ui/ui_kit.dart';

/// Reference-vs-body preview used while calibrating the camera.
///
/// The frame border mirrors the calibration state (accent when the hold is
/// locked, hairline otherwise) and a pill appears while no body is detected, so
/// a black viewport never looks like a frozen app.
class PrayerCalibrationPreview extends StatelessWidget {
  const PrayerCalibrationPreview(
      {super.key,
      required this.detector,
      required this.reference,
      required this.points,
      required this.aspectRatio,
      required this.mirrored,
      required this.ready,
      this.guideSegment});
  final PoseDetector detector;
  final PrayerReference reference;
  final List<Keypoint> points;
  final double aspectRatio;
  final bool mirrored, ready;
  final ReferenceSegment? guideSegment;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: AppRadius.card,
          border: Border.all(
            color: ready
                ? AppColors.accent.withValues(alpha: .85)
                : AppColors.border,
            width: ready ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(fit: StackFit.expand, children: [
          Center(
              child: AspectRatio(
                  aspectRatio:
                      aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 1,
                  child: Stack(fit: StackFit.expand, children: [
                    detector.buildPreview(),
                    IgnorePointer(
                        child: CustomPaint(
                            painter: _GuidePainter(
                                guideSegment ?? reference.standing,
                                points,
                                mirrored,
                                ready))),
                  ]))),
          if (points.isEmpty)
            const Positioned(
              top: AppSpacing.md,
              left: 0,
              right: 0,
              child: Center(
                child: PillTag('بانتظار رصد الجسم',
                    icon: Icons.person_search, tone: Tone.attention),
              ),
            ),
        ]),
      );
}

class _GuidePainter extends CustomPainter {
  _GuidePainter(this.reference, this.points, this.mirrored, this.ready);
  final ReferenceSegment reference;
  final List<Keypoint> points;
  final bool mirrored, ready;

  @override
  void paint(Canvas canvas, Size size) {
    final target = reference.preview.where((p) => p.confidence >= .65).toList();
    if (target.isEmpty) return;
    final top = target.map((p) => p.y).reduce(math.min),
        bottom = target.map((p) => p.y).reduce(math.max);
    final hip = target
        .where((p) => p.id == KeypointId.leftHip || p.id == KeypointId.rightHip)
        .toList();
    if (bottom - top < .05 || hip.length != 2) return;
    final centerX = (hip[0].x + hip[1].x) / 2;
    // Preserve reference pixel geometry and fit it inside the camera viewport.
    var scale = size.height * .72 / (bottom - top);
    final width = (target.map((p) => p.x).reduce(math.max) -
            target.map((p) => p.x).reduce(math.min)) *
        reference.aspectRatio;
    if (width * scale > size.width * .85) scale = size.width * .85 / width;
    Offset referencePoint(Keypoint p) {
      final dx =
          (p.x - centerX) * reference.aspectRatio * scale * (mirrored ? -1 : 1);
      return Offset(
          size.width / 2 + dx, size.height * .14 + (p.y - top) * scale);
    }

    Offset livePoint(Keypoint p) =>
        Offset((mirrored ? 1 - p.x : p.x) * size.width, p.y * size.height);
    void skeleton(List<Keypoint> joints, Offset Function(Keypoint) position,
        Color color, double stroke) {
      final map = {
        for (final p in joints)
          if (p.confidence >= .65 && p.x.isFinite && p.y.isFinite) p.id: p
      };
      final paint = Paint()
        ..color = color
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      for (final bone in skeletonBones) {
        final a = map[bone.$1], b = map[bone.$2];
        if (a != null && b != null) {
          canvas.drawLine(position(a), position(b), paint);
        }
      }
      for (final p in map.values) {
        canvas.drawCircle(position(p), stroke, paint);
      }
    }

    skeleton(target, referencePoint, const Color(0x80FFFFFF), 5);
    skeleton(points, livePoint,
        ready ? Colors.greenAccent : Colors.orangeAccent, 2.5);
  }

  @override
  bool shouldRepaint(covariant _GuidePainter old) =>
      old.points != points ||
      old.mirrored != mirrored ||
      old.ready != ready ||
      old.reference != reference;
}
