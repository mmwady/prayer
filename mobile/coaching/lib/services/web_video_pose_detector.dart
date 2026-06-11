// ─────────────────────────────────────────────────────────────────────────────
// web_video_pose_detector.dart
//
// Web-specific pose detector that processes a local video file instead of a live
// camera stream. This allows testing the AI pipeline (UI, Form Analysis, etc.)
// by simulating camera input via video.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import '../models/keypoint.dart';
import 'pose_detector.dart';

/// A [PoseDetector] designed specifically for Flutter Web to test video processing.
/// 
/// It leverages the browser's native `<input type="file">` and `<video>` tags.
/// We use [dart:html] because we need direct access to DOM elements for web video,
/// enabling us to pass raw video frames (or the HTML video context) directly to 
/// JS-based or model-specific AI inferences.
class WebVideoPoseDetector implements PoseDetector {
  /// Constructor takes the inference callback mapping a frame (videoContext) to Keypoints.
  /// The [videoContext] in this case is the [html.VideoElement].
  WebVideoPoseDetector({
    required this.inferenceCallback,
    this.fps = 30,
  });

  /// The async callback that performs the actual AI model inference.
  final Future<List<Keypoint>> Function(dynamic videoContext) inferenceCallback;
  
  /// Target frames-per-second to process the video.
  final int fps;

  final StreamController<List<Keypoint>> _controller =
      StreamController<List<Keypoint>>.broadcast();

  Timer? _timer;
  html.VideoElement? _videoElement;
  bool _isProcessingFrame = false;

  @override
  Stream<List<Keypoint>> get stream => _controller.stream;

  @override
  Future<void> start() async {
    // 1. Create a hidden file input element to let the user select a video.
    // Why use raw HTML input instead of a Flutter plugin like file_picker?
    // Because typical plugins read the file into Dart memory (as bytes),
    // which is slow and memory-intensive for large videos on the web.
    // By creating a DOM file input and generating an ObjectURL, we can pipe the
    // file directly into a DOM <video> element with zero copy.
    final html.FileUploadInputElement uploadInput = html.FileUploadInputElement();
    uploadInput.accept = 'video/*';
    
    // Listen for file selection.
    uploadInput.onChange.listen((e) {
      final files = uploadInput.files;
      if (files != null && files.isNotEmpty) {
        final file = files[0];
        _initVideoElement(file);
      }
    });

    // Programmatically trigger the browser's file dialog.
    uploadInput.click();
  }

  void _initVideoElement(html.File file) {
    // 2. Set up the HTML <video> element.
    _videoElement = html.VideoElement()
      ..src = html.Url.createObjectUrlFromBlob(file)
      ..autoplay = true
      ..loop = false
      ..controls = false;
      
    // _videoElement isn't explicitly attached to the DOM unless we want to 
    // display it. Kept hidden, it still plays and decodes frames we can use.
    
    _videoElement!.onPlay.listen((_) {
      // 3. Start the extraction loop when the video actually starts playing.
      _startInferenceLoop();
    });

    _videoElement!.onEnded.listen((_) {
      // Video finished normally, stop inference.
      stop();
    });
  }

  void _startInferenceLoop() {
    _timer?.cancel();
    
    // We use a periodic timer to synchronize the inference rate with the desired FPS.
    _timer = Timer.periodic(
      Duration(milliseconds: (1000 / fps).round()),
      (_) async {
        // If the video doesn't exist, is paused, or ended, skip this tick.
        if (_videoElement == null || _videoElement!.paused || _videoElement!.ended) {
          return;
        }

        // 4. Ensure we don't overlap frames if model inference takes longer 
        // than our timer interval (prevent queue buildup).
        if (_isProcessingFrame) return;

        _isProcessingFrame = true;
        try {
          // 5. Pass the HTML video element to the callback.
          // Native JS ML APIs (like MediaPipe) can often ingest an HTMLVideoElement 
          // directly for GPU acceleration, avoiding manual canvas pixel extraction.
          final keypoints = await inferenceCallback(_videoElement!);
          
          // 6. Broadcast the detected keypoints to the UI stream.
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
    // 7. Clean up timer.
    _timer?.cancel();
    _timer = null;

    // Clean up DOM and memory footprint of the video object.
    if (_videoElement != null) {
      _videoElement!.pause();
      if (_videoElement!.src.isNotEmpty) {
        // Revoke the Object URL to avoid memory leaks.
        html.Url.revokeObjectUrl(_videoElement!.src);
      }
      _videoElement!.remove(); 
      _videoElement = null;
    }
  }

  /// Properly release the stream controller when navigating away or tearing down.
  void dispose() {
    stop();
    _controller.close();
  }
}
