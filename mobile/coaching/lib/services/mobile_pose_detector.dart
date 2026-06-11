// ─────────────────────────────────────────────────────────────────────────────
// mobile_pose_detector.dart
//
// Android/iOS specific implementation of the PoseDetector using Google ML Kit.
// Connects to the native device camera, converts the frames to ML Kit format,
// performs inference, and streams mapped keypoints.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../models/keypoint.dart' as custom;
import 'pose_detector.dart' as base_detector;

/// A [PoseDetector] designed explicitly for native Android/iOS using ML Kit.
///
/// It instantiates a camera feed using the first available front-facing camera,
/// listens to the image stream, converts `CameraImage` formats to ML Kit's
/// `InputImage`, and continuously broadcasts detected [custom.Keypoint]s.
class MobilePoseDetector implements base_detector.PoseDetector {
  MobilePoseDetector({this.fps = 30});

  final int fps;

  final StreamController<List<custom.Keypoint>> _controller =
      StreamController<List<custom.Keypoint>>.broadcast();

  CameraController? _cameraController;
  final PoseDetector _mlKitPoseDetector = PoseDetector(
    options: PoseDetectorOptions(
      mode: PoseDetectionMode.stream,
      model: PoseDetectionModel.base, // Uses the bundled base model
    ),
  );

  bool _isProcessingFrame = false;

  // Timer used to limit frames to the requested FPS if the camera streams faster
  Timer? _fpsLimiterTimer;
  bool _canProcessNextFrame = true;

  @override
  Stream<List<custom.Keypoint>> get stream => _controller.stream;

  @override
  Future<void> start() async {
    // 1. Discover available cameras on the device.
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

    // Prioritize the front-facing camera for fitness apps.
    final frontCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    // 2. Initialize the camera controller with a low resolution preset to
    //    maintain high framerates for inference.
    _cameraController = CameraController(
      frontCamera,
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    try {
      await _cameraController!.initialize();
    } on CameraException catch (e) {
      debugPrint('MobilePoseDetector camera initialization failed: $e');
      await _cameraController?.dispose();
      _cameraController = null;
      return;
    }

    // Set up FPS limiter. ML Kit can sometimes process faster/slower than our tick rate.
    _fpsLimiterTimer?.cancel();
    _fpsLimiterTimer = Timer.periodic(
      Duration(milliseconds: (1000 / fps).round()),
      (_) => _canProcessNextFrame = true,
    );

    // 3. Hook into the live camera stream. Each frame received invokes this callback.
    try {
      await _cameraController!.startImageStream((CameraImage image) async {
      // Prevent pipeline queuing if the model inference cannot keep up, or if
      // we are exceeding the target FPS limit.
      if (_isProcessingFrame || !_canProcessNextFrame) return;

      _isProcessingFrame = true;
      _canProcessNextFrame = false;

      try {
        // Convert CameraImage to the InputImage format expected by ML Kit.
        final inputImage = _inputImageFromCameraImage(image, frontCamera);
        if (inputImage == null) return;

        // 4. Perform pose detection asynchronous inference.
        final List<Pose> poses =
            await _mlKitPoseDetector.processImage(inputImage);

        if (poses.isNotEmpty) {
          // We only care about the primary detected subject.
          final Pose primaryPose = poses.first;
          final mappedKeypoints = _mapKeypoints(primaryPose.landmarks);

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

    if (_cameraController != null &&
        _cameraController!.value.isStreamingImages) {
      await _cameraController!.stopImageStream();
    }
    await _cameraController?.dispose();
    _cameraController = null;
  }

  /// Automatically handles resource deallocation when garbage collected or removed.
  void dispose() {
    stop();
    _mlKitPoseDetector.close();
    _controller.close();
  }

  /// Creates ML Kit's [InputImage] from the raw [CameraImage] buffer.
  /// Standard boilerplate handling Android's nv21 and iOS's bgra8888 plane structures.
  InputImage? _inputImageFromCameraImage(
      CameraImage image, CameraDescription camera) {
    // Collect bytes according to native platform planes.
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final Size imageSize =
        Size(image.width.toDouble(), image.height.toDouble());

    // Front facing cameras typically have a default rotation of 270 on Android.
    // Replace with standard rotation mapping logic based on your platform channel
    // if dynamic orientation support is strictly needed.
    final InputImageRotation rotation =
        InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
            InputImageRotation.rotation270deg;

    final InputImageFormat format =
        InputImageFormatValue.fromRawValue(image.format.raw)
            // Fallback guess based on OS if raw value parsing fails
            ??
            (Platform.isAndroid
                ? InputImageFormat.nv21
                : InputImageFormat.bgra8888);

    // Skip frame if platform doesn't map to a supported format.
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

  /// Translates ML Kit's [PoseLandmark] map into our app-standard [custom.Keypoint]s.
  /// Coordinates extracted from ML Kit are actual pixels; we normalize them to `0.0 - 1.0`
  /// so UI Overlays scale them cleanly.
  List<custom.Keypoint> _mapKeypoints(
      Map<PoseLandmarkType, PoseLandmark> landmarks) {
    // Safely retrieves coordinates and normalizes them across the incoming camera image size.
    // The camera image size is defined by the `ResolutionPreset`.
    // Warning: Android width/height orientations can be flipped (e.g. width is height in portrait).
    // Using a generalized normalization for this example.
    final w = _cameraController!.value.previewSize?.width ?? 480;
    final h = _cameraController!.value.previewSize?.height ?? 640;

    // Helper closure to create a keypoint if confidence meets ML kit's existence probability.
    custom.Keypoint? createKeypoint(
        PoseLandmarkType mlkitType, custom.KeypointId customId) {
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

    // Map Facial landmarks
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

    // Map Torso
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

    // Map Arms
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

    // Map Legs
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

    // Calculate synthetic spineMid point as required by our local bone graph,
    // located halfway between shoulders and hips.
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
