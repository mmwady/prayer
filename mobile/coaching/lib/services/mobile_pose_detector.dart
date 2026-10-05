// ─────────────────────────────────────────────────────────────────────────────
// mobile_pose_detector.dart
//
// Android/iOS specific implementation of the PoseDetector using Google ML Kit.
// It owns the real CameraController so the UI can render CameraPreview while the
// same stream is used for pose inference.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../models/keypoint.dart' as custom;
import 'pose_detector.dart' as base_detector;
import 'camera_pose_geometry.dart';

class MobilePoseDetector
    implements base_detector.PoseDetector, base_detector.PosePreviewGeometry {
  MobilePoseDetector({this.fps = 30});

  final int fps;

  final StreamController<List<custom.Keypoint>> _controller =
      StreamController<List<custom.Keypoint>>.broadcast();

  CameraController? _cameraController;
  final PoseDetector _mlKitPoseDetector = PoseDetector(
    options: PoseDetectorOptions(
      mode: PoseDetectionMode.stream,
      model: PoseDetectionModel.accurate,
    ),
  );

  bool _isProcessingFrame = false;
  Timer? _fpsLimiterTimer;
  bool _canProcessNextFrame = true;
  bool _stopping = false;
  Completer<void>? _frameDone;
  Future<void>? _stopOperation;
  Size _imageSize = const Size(640, 480);
  int _rotation = 90;
  bool _front = true;

  @override
  double get previewAspectRatio => _rotation == 90 || _rotation == 270
      ? _imageSize.height / _imageSize.width
      : _imageSize.width / _imageSize.height;
  @override
  bool get previewMirrored => _front;

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
            'جارٍ تشغيل الكاميرا…',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: previewAspectRatio,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  @override
  Future<void> start() async {
    _stopping = false;
    _stopOperation = null;
    late final List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } on MissingPluginException catch (e) {
      debugPrint('MobilePoseDetector camera plugin unavailable: $e');
      rethrow;
    } on CameraException catch (e) {
      debugPrint('MobilePoseDetector camera discovery failed: $e');
      rethrow;
    }

    if (cameras.isEmpty) {
      debugPrint('MobilePoseDetector found no available cameras.');
      throw StateError('No camera available');
    }

    final frontCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    _front = frontCamera.lensDirection == CameraLensDirection.front;
    _rotation = frontCamera.sensorOrientation;

    _cameraController = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    try {
      await _cameraController!.initialize();
      await _cameraController!
          .lockCaptureOrientation(DeviceOrientation.portraitUp);
      _imageSize = _cameraController!.value.previewSize ?? _imageSize;
    } on CameraException catch (e) {
      debugPrint('MobilePoseDetector camera initialization failed: $e');
      await _cameraController?.dispose();
      _cameraController = null;
      rethrow;
    }

    _fpsLimiterTimer?.cancel();
    _fpsLimiterTimer = Timer.periodic(
      Duration(milliseconds: (1000 / fps).round()),
      (_) => _canProcessNextFrame = true,
    );

    try {
      await _cameraController!.startImageStream((CameraImage image) async {
        if (_stopping || _isProcessingFrame || !_canProcessNextFrame) return;

        _isProcessingFrame = true;
        _frameDone = Completer<void>();
        _canProcessNextFrame = false;

        try {
          final inputImage = _inputImageFromCameraImage(image, frontCamera);
          if (inputImage == null) {
            throw StateError('Unsupported camera image format');
          }

          final poses = await _mlKitPoseDetector.processImage(inputImage);
          if (_stopping || _cameraController == null) return;
          if (poses.length == 1) {
            final mappedKeypoints = _mapKeypoints(poses.first.landmarks);
            if (!_controller.isClosed) {
              _controller.add(mappedKeypoints);
            }
          } else if (!_controller.isClosed) {
            _controller.add(const <custom.Keypoint>[]);
          }
        } catch (e) {
          debugPrint('MobilePoseDetector inference error: $e');
          if (!_stopping && !_controller.isClosed) _controller.addError(e);
        } finally {
          _isProcessingFrame = false;
          _frameDone?.complete();
        }
      });
    } on CameraException catch (e) {
      debugPrint('MobilePoseDetector camera stream failed: $e');
      _fpsLimiterTimer?.cancel();
      _fpsLimiterTimer = null;
      await _cameraController?.dispose();
      _cameraController = null;
      rethrow;
    }
  }

  @override
  Future<void> stop() => _stopOperation ??= _stop();

  Future<void> _stop() async {
    _stopping = true;
    _fpsLimiterTimer?.cancel();
    _fpsLimiterTimer = null;

    if (_cameraController != null &&
        _cameraController!.value.isStreamingImages) {
      await _cameraController!.stopImageStream();
    }
    await _frameDone?.future;
    await _cameraController?.dispose();
    _cameraController = null;
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _mlKitPoseDetector.close();
    await _controller.close();
  }

  InputImage? _inputImageFromCameraImage(
    CameraImage image,
    CameraDescription camera,
  ) {
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    _imageSize = imageSize;
    final rotation =
        InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (rotation == null ||
        format == null ||
        image.planes.length != 1 ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }
    _rotation = camera.sensorOrientation;

    return InputImage.fromBytes(
      bytes: image.planes.first.bytes,
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
    final w = _imageSize.width;
    final h = _imageSize.height;

    custom.Keypoint? createKeypoint(
      PoseLandmarkType mlkitType,
      custom.KeypointId customId,
    ) {
      final landmark = landmarks[mlkitType];
      if (landmark != null && landmark.likelihood > 0.5) {
        final point = uprightCameraPoint(
            landmark.x, landmark.y, w, h, _rotation,
            alreadyRotated: Platform.isAndroid);
        return custom.Keypoint(
          id: customId,
          x: point.$1,
          y: point.$2,
          confidence: landmark.likelihood,
          position3d: custom.PosePoint3d(
              point.$1 * ((_rotation == 90 || _rotation == 270) ? h : w),
              point.$2 * ((_rotation == 90 || _rotation == 270) ? w : h),
              landmark.z,
              custom.Pose3dSpace.mlkitImagePixels),
        );
      }
      return null;
    }

    final keypoints = <custom.Keypoint>[];

    _addIfNotNull(keypoints,
        createKeypoint(PoseLandmarkType.nose, custom.KeypointId.nose));
    _addIfNotNull(keypoints,
        createKeypoint(PoseLandmarkType.leftEye, custom.KeypointId.leftEye));
    _addIfNotNull(keypoints,
        createKeypoint(PoseLandmarkType.rightEye, custom.KeypointId.rightEye));
    _addIfNotNull(keypoints,
        createKeypoint(PoseLandmarkType.leftEar, custom.KeypointId.leftEar));
    _addIfNotNull(keypoints,
        createKeypoint(PoseLandmarkType.rightEar, custom.KeypointId.rightEar));

    final leftShoulder = createKeypoint(
        PoseLandmarkType.leftShoulder, custom.KeypointId.leftShoulder);
    final rightShoulder = createKeypoint(
        PoseLandmarkType.rightShoulder, custom.KeypointId.rightShoulder);
    final leftHip =
        createKeypoint(PoseLandmarkType.leftHip, custom.KeypointId.leftHip);
    final rightHip =
        createKeypoint(PoseLandmarkType.rightHip, custom.KeypointId.rightHip);

    _addIfNotNull(keypoints, leftShoulder);
    _addIfNotNull(keypoints, rightShoulder);
    _addIfNotNull(keypoints, leftHip);
    _addIfNotNull(keypoints, rightHip);

    _addIfNotNull(
        keypoints,
        createKeypoint(
            PoseLandmarkType.leftElbow, custom.KeypointId.leftElbow));
    _addIfNotNull(
        keypoints,
        createKeypoint(
            PoseLandmarkType.rightElbow, custom.KeypointId.rightElbow));
    _addIfNotNull(
        keypoints,
        createKeypoint(
            PoseLandmarkType.leftWrist, custom.KeypointId.leftWrist));
    _addIfNotNull(
        keypoints,
        createKeypoint(
            PoseLandmarkType.rightWrist, custom.KeypointId.rightWrist));

    _addIfNotNull(keypoints,
        createKeypoint(PoseLandmarkType.leftKnee, custom.KeypointId.leftKnee));
    _addIfNotNull(
        keypoints,
        createKeypoint(
            PoseLandmarkType.rightKnee, custom.KeypointId.rightKnee));
    _addIfNotNull(
        keypoints,
        createKeypoint(
            PoseLandmarkType.leftAnkle, custom.KeypointId.leftAnkle));
    _addIfNotNull(
        keypoints,
        createKeypoint(
            PoseLandmarkType.rightAnkle, custom.KeypointId.rightAnkle));

    if (leftShoulder != null &&
        rightShoulder != null &&
        leftHip != null &&
        rightHip != null) {
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
