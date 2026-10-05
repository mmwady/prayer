import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'video_source.dart';

VideoSource createVideoSource() => NativeVideoSource();

class NativeVideoSource implements VideoSource {
  static const _channel = MethodChannel('iqtadi/recorded_video');
  int? _sourceId;
  @override
  Future<LocalVideo?> pick() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError(
          'اختيار واستخراج الفيديو متاح حاليًا على Android والويب فقط.');
    }
    final data = await _channel.invokeMapMethod<String, dynamic>('pick');
    if (data != null) _sourceId = data['source_id'] as int;
    return data == null
        ? null
        : LocalVideo(
            name: data['name'] as String,
            durationMs: data['duration_ms'] as int);
  }

  @override
  Future<SampledFrame> frame(
      int index, int timestampMs, int maxDimension) async {
    final bytes = await _channel.invokeMethod<Uint8List>('frame', {
      'timestamp_ms': timestampMs,
      'max_dimension': maxDimension,
      'source_id': _sourceId,
    });
    if (bytes == null) throw StateError('تعذر استخراج إطار الفيديو.');
    return SampledFrame(index, timestampMs, bytes);
  }

  @override
  Future<void> close() async {
    if (defaultTargetPlatform == TargetPlatform.android && _sourceId != null) {
      final id = _sourceId;
      _sourceId = null;
      await _channel.invokeMethod<void>('close', {'source_id': id});
    }
  }
}
