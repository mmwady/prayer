// ─────────────────────────────────────────────────────────────────────────────
// web_video_pose_detector.dart
//
// Web-specific pose detector that processes a local video file. The selected
// HTML video element is also exposed as an HtmlElementView so the Flutter UI can
// show the real uploaded video beside the skeleton overlay.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: undefined_prefixed_name
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

import '../models/keypoint.dart';
import 'pose_detector.dart';

class WebVideoPoseDetector implements PoseDetector, PosePreviewGeometry {
  WebVideoPoseDetector({
    required this.inferenceCallback,
    this.fps = 30,
  }) : _viewType = 'web-video-preview-${DateTime.now().microsecondsSinceEpoch}';

  final Future<List<Keypoint>> Function(dynamic videoContext) inferenceCallback;
  final int fps;
  final String _viewType;

  final StreamController<List<Keypoint>> _controller =
      StreamController<List<Keypoint>>.broadcast();

  Timer? _timer;
  html.VideoElement? _videoElement;
  bool _isProcessingFrame = false;
  bool _viewRegistered = false;

  @override
  Stream<List<Keypoint>> get stream => _controller.stream;

  @override
  double get previewAspectRatio =>
      _videoElement != null && _videoElement!.videoHeight > 0
          ? _videoElement!.videoWidth / _videoElement!.videoHeight
          : 1;
  @override
  bool get previewMirrored => false;

  @override
  Widget buildPreview() {
    if (_videoElement == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Text(
            'لم يتم اختيار فيديو بعد',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return HtmlElementView(viewType: _viewType);
  }

  @override
  Future<void> start() async {
    final uploadInput = html.FileUploadInputElement();
    uploadInput.accept = 'video/*';

    uploadInput.onChange.listen((e) {
      final files = uploadInput.files;
      if (files != null && files.isNotEmpty) {
        _initVideoElement(files[0]);
      }
    });

    uploadInput.click();
  }

  void _initVideoElement(html.File file) {
    if (_controller.isClosed) return;
    final video = html.VideoElement()
      ..src = html.Url.createObjectUrlFromBlob(file)
      ..autoplay = true
      ..loop = false
      ..controls = true
      ..muted = true
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'contain'
      ..style.backgroundColor = 'black';

    _videoElement = video;

    if (!_viewRegistered) {
      ui_web.platformViewRegistry
          .registerViewFactory(_viewType, (int viewId) => video);
      _viewRegistered = true;
    }

    video.onPlay.listen((_) => _startInferenceLoop());
    video.onEnded.listen((_) => stop());

    video.play();
  }

  void _startInferenceLoop() {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(milliseconds: (1000 / fps).round()),
      (_) async {
        if (_videoElement == null ||
            _videoElement!.paused ||
            _videoElement!.ended) {
          return;
        }

        if (_isProcessingFrame) return;

        _isProcessingFrame = true;
        try {
          final keypoints = await inferenceCallback(_videoElement!);
          if (!_controller.isClosed) {
            _controller.add(keypoints);
          }
        } catch (e) {
          html.window.console.error('WebVideoPoseDetector inference error: $e');
        } finally {
          _isProcessingFrame = false;
        }
      },
    );
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;

    if (_videoElement != null) {
      _videoElement!.pause();
      if (_videoElement!.src.isNotEmpty) {
        html.Url.revokeObjectUrl(_videoElement!.src);
      }
      _videoElement = null;
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
