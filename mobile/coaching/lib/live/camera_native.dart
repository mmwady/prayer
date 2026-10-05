import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'camera_source.dart';

LiveCamera createLiveCamera() => NativeLiveCamera();

class NativeLiveCamera implements LiveCamera {
  static const bridge = MethodChannel('iqtadi/live_camera');
  CameraController? _camera;
  Future<void>? _conversion;
  Future<void>? _stopping;
  bool _capturing = false;
  @override
  bool get ready => _camera?.value.isInitialized ?? false;

  @override
  Future<void> open({bool front = true, bool requireDirection = false}) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
          'الكاميرا المباشرة متاحة حاليًا على Android والويب.');
    }
    final cameras = await availableCameras();
    if (cameras.isEmpty) throw StateError('لا توجد كاميرا متاحة.');
    final direction =
        front ? CameraLensDirection.front : CameraLensDirection.back;
    if (requireDirection && !cameras.any((c) => c.lensDirection == direction)) {
      throw StateError('الكاميرا ${front ? 'الأمامية' : 'الخلفية'} غير متاحة.');
    }
    final description = cameras.firstWhere((c) => c.lensDirection == direction,
        orElse: () => cameras.first);
    await close();
    final camera = CameraController(description, ResolutionPreset.medium,
        enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
    _camera = camera;
    try {
      await camera.initialize();
      await camera.lockCaptureOrientation(DeviceOrientation.portraitUp);
    } catch (_) {
      await close();
      rethrow;
    }
  }

  @override
  Widget preview() => !ready
      ? const SizedBox()
      : AspectRatio(
          aspectRatio: 1 / _camera!.value.aspectRatio,
          child: CameraPreview(_camera!));

  @override
  Future<void> capture(double fps, int maxDimension,
      void Function(int, Uint8List) onFrame, void Function(Object) onError,
      {bool Function()? shouldCapture}) async {
    final camera = _camera!;
    final watch = Stopwatch()..start();
    final interval = (1000 / fps).round();
    var last = -interval;
    _capturing = true;
    await camera.startImageStream((image) {
      final timestamp = watch.elapsedMilliseconds;
      if (!_capturing || _conversion != null || timestamp - last < interval) {
        return;
      }
      if (shouldCapture?.call() == false) return;
      last = timestamp;
      _conversion = () async {
        try {
          final jpeg = await bridge.invokeMethod<Uint8List>('encode', {
            'width': image.width, 'height': image.height,
            'format': image.format.raw,
            'planes': [
              for (final plane in image.planes)
                {
                  'bytes': plane.bytes,
                  'row_stride': plane.bytesPerRow,
                  'pixel_stride': plane.bytesPerPixel ?? 1,
                }
            ],
            // Locked portrait; pixels are not mirrored even for the front lens.
            'rotation': camera.description.sensorOrientation,
            'max_dimension': maxDimension,
          });
          if (_capturing && jpeg != null) onFrame(timestamp, jpeg);
        } catch (error) {
          if (_capturing) onError(error);
        } finally {
          _conversion = null;
        }
      }();
    });
  }

  @override
  Future<void> stop() =>
      _stopping ??= _stop().whenComplete(() => _stopping = null);

  Future<void> _stop() async {
    _capturing = false;
    if (_camera?.value.isStreamingImages ?? false) {
      await _camera!.stopImageStream();
    }
    await _conversion;
  }

  @override
  Future<bool> keepAwake(bool enabled) async => !Platform.isAndroid
      ? false
      : await bridge.invokeMethod<bool>('awake', enabled) ?? false;

  @override
  Future<void> close() async {
    await stop();
    final camera = _camera;
    _camera = null;
    await camera?.dispose();
  }
}
