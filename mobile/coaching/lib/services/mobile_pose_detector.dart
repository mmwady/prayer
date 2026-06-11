// ─────────────────────────────────────────────────────────────────────────────
// mobile_pose_detector.dart
//
// Android/iOS specific implementation of the PoseDetector using Google ML Kit.
// It owns the real CameraController so the UI can render CameraPreview while the
// same stream is used for pose inference.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../models/keypoint.dart' as custom;
import 'pose_detector.dart' as base_detector;

class MobilePoseDetector implements base_detector.PoseDetector {
  MobilePoseDetector({this.fps = 30});

  final int fps;

  final StreamController<List<custom.Keypoint>> _controller =
      StreamController<List<custom.Keypoint>>.broadcast();

  CameraController? _cameraController;
  final PoseDetector _mlKitPoseDetector = PoseDetector(
    options: PoseDetectorOptions(
      mode: PoseDetectionMode.stream,
      model: PoseDetectionModel.base,
    ),
  );

  bool _isProcessingFrame = false;
  Timer? _fpsLimiterTimer;
  bool _canProcessNextFrame = true;

  @override
  Stream<List<custom.Keypoint>> get stream => _controller.stream;

  @override
  Widget buildPreview() {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Text(
            'Camera is starting...',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  @override
  Future<void> start() async {
    late final List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } on MissingPluginException catch (e) {
      debugPrint('MobilePoseDetector camera plugin unavailable: $e');
      return;
    } on CameraException catch (e) {
      debugPrint('MobilePoseDetector camera discovery failed: $e');
      return;
    }

    if (cameras.isEmpty) {
      debugPrint('MobilePoseDetector found no available cameras.');
      return;
    }

    final frontCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    _cameraController = CameraController(
      frontCamera,
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup:
          Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );

    try {
      await _cameraController!.initialize();
    } on CameraException catch (e) {
      debugPrint('MobilePoseDetector camera initialization failed: $e');
      await _cameraController?.dispose();
      _cameraController = null;
      return;
    }

    _fpsLimiterTimer?.cancel();
    _fpsLimiterTimer = Timer.periodic(
      Duration(milliseconds: (1000 / fps).round()),
      (_) => _canProcessNextFrame = true,
    );

    try {
      await _cameraController!.startImageStream((CameraImage image) async {
        if (_isProcessingFrame || !_canProcessNextFrame) return;

        _isProcessingFrame = true;
        _canProcessNextFrame = false;

        try {
          final inputImage = _inputImageFromCameraImage(image, frontCamera);
          if (inputImage == null) return;

          final poses = await _mlKitPoseDetector.processImage(inputImage);
          if (poses.isNotEmpty) {
            final mappedKeypoints = _mapKeypoints(poses.first.landmarks);
            if (!_controller.isClosed) {
              _controller.add(mappedKeypoints);
            }
          }
        } catch (e) {
          debugPrint('MobilePoseDetector inference error: $e');
        } finally {
          _isProcessingFrame = false;
        }
      });
    } on CameraException catch (e) {
      debugPrint('MobilePoseDetector camera stream failed: $e');
      _fpsLimiterTimer?.cancel();
      _fpsLimiterTimer = null;
      await _cameraController?.dispose();
      _cameraController = null;
    }
  }

  @override
  Future<void> stop() async {
    _fpsLimiterTimer?.cancel();
    _fpsLimiterTimer = null;

    if (_cameraController != null && _cameraController!.value.isStreamingImages) {
      await _cameraController!.stopImageStream();
    }
    await _cameraController?.dispose();
    _cameraController = null;
  }

  void dispose() {
    stop();
    _mlKitPoseDetector.close();
    _controller.close();
  }

  InputImage? _inputImageFromCameraImage(
    CameraImage image,
    CameraDescription camera,
  ) {
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
        InputImageRotation.rotation270deg;
    final format = InputImageFormatValue.fromRawValue(image.format.raw) ??
        (Platform.isAndroid ? InputImageFormat.nv21 : InputImageFormat.bgra8888);

    if (image.planes.isEmpty) return null;

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: imageSize,
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  List<custom.Keypoint> _mapKeypoints(
    Map<PoseLandmarkType, PoseLandmark> landmarks,
  ) {
    final w = _cameraController!.value.previewSize?.width ?? 480;
    final h = _cameraController!.value.previewSize?.height ?? 640;

    custom.Keypoint? createKeypoint(
      PoseLandmarkType mlkitType,
      custom.KeypointId customId,
    ) {
      final landmark = landmarks[mlkitType];
      if (landmark != null && landmark.likelihood > 0.5) {
        return custom.Keypoint(
          id: customId,
          x: landmark.x / w,
          y: landmark.y / h,
          confidence: landmark.likelihood,
        );
      }
      return null;
    }

    final keypoints = <custom.Keypoint>[];

    _addIfNotNull(keypoints, createKeypoint(PoseLandmarkType.nose, custom.KeypointId.nose));
    _addIfNotNull(keypoints, createKeypoint(PoseLandmarkType.leftEye, custom.KeypointId.leftEye));
    _addIfNotNull(keypoints, createKeypoint(PoseLandmarkType.rightEye, custom.KeypointId.rightEye));
    _addIfNotNull(keypoints, createKeypoint(PoseLandmarkType.leftEar, custom.KeypointId.leftEar));
    _addIfNotNull(keypoints, createKeypoint(PoseLandmarkType.rightEar, custom.KeypointId.rightEar));

    final leftShoulder =
        createKeypoint(PoseLandmarkType.leftShoulder, custom.KeypointId.leftShoulder);
    final rightShoulder =
        createKeypoint(PoseLandmarkType.rightShoulder, custom.KeypointId.rightShoulder);
    final leftHip = createKeypoint(PoseLandmarkType.leftHip, custom.KeypointId.leftHip);
    final rightHip = createKeypoint(PoseLandmarkType.rightHip, custom.KeypointId.rightHip);

    _addIfNotNull(keypoints, leftShoulder);
    _addIfNotNull(keypoints, rightShoulder);
    _addIfNotNull(keypoints, leftHip);
    _addIfNotNull(keypoints, rightHip);

    _addIfNotNull(keypoints, createKeypoint(PoseLandmarkType.leftElbow, custom.KeypointId.leftElbow));
    _addIfNotNull(keypoints, createKeypoint(PoseLandmarkType.rightElbow, custom.KeypointId.rightElbow));
    _addIfNotNull(keypoints, createKeypoint(PoseLandmarkType.leftWrist, custom.KeypointId.leftWrist));
    _addIfNotNull(keypoints, createKeypoint(PoseLandmarkType.rightWrist, custom.KeypointId.rightWrist));

    _addIfNotNull(keypoints, createKeypoint(PoseLandmarkType.leftKnee, custom.KeypointId.leftKnee));
    _addIfNotNull(keypoints, createKeypoint(PoseLandmarkType.rightKnee, custom.KeypointId.rightKnee));
    _addIfNotNull(keypoints, createKeypoint(PoseLandmarkType.leftAnkle, custom.KeypointId.leftAnkle));
    _addIfNotNull(keypoints, createKeypoint(PoseLandmarkType.rightAnkle, custom.KeypointId.rightAnkle));

    if (leftShoulder != null && rightShoulder != null && leftHip != null && rightHip != null) {
      final midShoulderY = (leftShoulder.y + rightShoulder.y) / 2;
      final midHipY = (leftHip.y + rightHip.y) / 2;
      final midShoulderX = (leftShoulder.x + rightShoulder.x) / 2;
      final midHipX = (leftHip.x + rightHip.x) / 2;

      keypoints.add(custom.Keypoint(
        id: custom.KeypointId.spineMid,
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
  }

  void _addIfNotNull(List<custom.Keypoint> list, custom.Keypoint? k) {
    if (k != null) list.add(k);
  }
}
