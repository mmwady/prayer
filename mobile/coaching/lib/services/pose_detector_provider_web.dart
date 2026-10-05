// ─────────────────────────────────────────────────────────────────────────────
// pose_detector_provider_web.dart
//
// Web-specific factory for PoseDetector.
// ─────────────────────────────────────────────────────────────────────────────

import '../models/keypoint.dart';
import 'pose_detector.dart';
import 'web_video_pose_detector.dart';
import 'package:flutter/foundation.dart';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Returns the WebVideoPoseDetector for Flutter Web targets.
PoseDetector getPlatformPoseDetector() {
  return WebVideoPoseDetector(
    inferenceCallback: _mediaPipeInference,
    fps: 30,
  );
}

@JS('estimatePose')
external JSPromise _estimatePose(JSAny videoElement);

/// Executes MediaPipe Pose inference via our JS Wrapper.
Future<List<Keypoint>> _mediaPipeInference(dynamic videoContext) async {
  if (videoContext is html.VideoElement) {
    try {
      // Calls window.estimatePose(videoElement) resolving the Promise
      final promise = _estimatePose(videoContext as JSAny);
      final jsArrayAny = await promise.toDart;
      final results = jsArrayAny as JSArray<JSObject>;

      final keypoints = <Keypoint>[];

      // Helper to map index
      Keypoint? createKeypoint(int index, KeypointId customId) {
        if (index <
            (results.getProperty('length'.toJS) as JSNumber).toDartInt) {
          final jsObject =
              results.getProperty(index.toString().toJS) as JSObject;
          final x = (jsObject.getProperty('x'.toJS) as JSNumber).toDartDouble;
          final y = (jsObject.getProperty('y'.toJS) as JSNumber).toDartDouble;
          final visibility =
              (jsObject.getProperty('visibility'.toJS) as JSNumber)
                  .toDartDouble;

          if (visibility > 0.5) {
            PosePoint3d? world;
            if (jsObject.hasProperty('worldX'.toJS).toDart) {
              world = PosePoint3d(
                  (jsObject.getProperty('worldX'.toJS) as JSNumber)
                      .toDartDouble,
                  (jsObject.getProperty('worldY'.toJS) as JSNumber)
                      .toDartDouble,
                  (jsObject.getProperty('worldZ'.toJS) as JSNumber)
                      .toDartDouble,
                  Pose3dSpace.mediapipeWorldMeters);
            }
            return Keypoint(
              id: customId,
              x: x,
              y: y,
              confidence: visibility,
              position3d: world,
            );
          }
        }
        return null;
      }

      void addIfNotNull(Keypoint? k) {
        if (k != null) keypoints.add(k);
      }

      // Map facial
      addIfNotNull(createKeypoint(0, KeypointId.nose));
      addIfNotNull(createKeypoint(2, KeypointId.leftEye));
      addIfNotNull(createKeypoint(5, KeypointId.rightEye));
      addIfNotNull(createKeypoint(7, KeypointId.leftEar));
      addIfNotNull(createKeypoint(8, KeypointId.rightEar));

      // Map torso
      final leftShoulder = createKeypoint(11, KeypointId.leftShoulder);
      final rightShoulder = createKeypoint(12, KeypointId.rightShoulder);
      final leftHip = createKeypoint(23, KeypointId.leftHip);
      final rightHip = createKeypoint(24, KeypointId.rightHip);

      addIfNotNull(leftShoulder);
      addIfNotNull(rightShoulder);
      addIfNotNull(leftHip);
      addIfNotNull(rightHip);

      // Map arms
      addIfNotNull(createKeypoint(13, KeypointId.leftElbow));
      addIfNotNull(createKeypoint(14, KeypointId.rightElbow));
      addIfNotNull(createKeypoint(15, KeypointId.leftWrist));
      addIfNotNull(createKeypoint(16, KeypointId.rightWrist));

      // Map legs
      addIfNotNull(createKeypoint(25, KeypointId.leftKnee));
      addIfNotNull(createKeypoint(26, KeypointId.rightKnee));
      addIfNotNull(createKeypoint(27, KeypointId.leftAnkle));
      addIfNotNull(createKeypoint(28, KeypointId.rightAnkle));

      // Compute synthetic spineMid
      if (leftShoulder != null &&
          rightShoulder != null &&
          leftHip != null &&
          rightHip != null) {
        final midShoulderX = (leftShoulder.x + rightShoulder.x) / 2;
        final midShoulderY = (leftShoulder.y + rightShoulder.y) / 2;

        final midHipX = (leftHip.x + rightHip.x) / 2;
        final midHipY = (leftHip.y + rightHip.y) / 2;

        keypoints.add(Keypoint(
          id: KeypointId.spineMid,
          x: (midShoulderX + midHipX) / 2,
          y: (midShoulderY + midHipY) / 2,
          confidence: (leftShoulder.confidence +
                  rightShoulder.confidence +
                  leftHip.confidence +
                  rightHip.confidence) /
              4,
        ));
      }

      return keypoints;
    } catch (e) {
      debugPrint('MediaPipe Inference Error: $e');
    }
  }

  return [];
}
