import 'dart:convert';
import 'dart:js_interop';
import 'video_source.dart';

@JS('iqtadiVideoPick')
external JSPromise<JSString> _pick();
@JS('iqtadiVideoFrame')
external JSPromise<JSString> _frame(
    JSNumber time, JSNumber dimension, JSNumber sourceId);
@JS('iqtadiVideoClose')
external void _close(JSNumber sourceId);

VideoSource createVideoSource() => WebVideoSource();

class WebVideoSource implements VideoSource {
  int? _sourceId;
  @override
  Future<LocalVideo?> pick() async {
    final data = jsonDecode((await _pick().toDart).toDart);
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
    final encoded =
        (await _frame(timestampMs.toJS, maxDimension.toJS, _sourceId!.toJS)
                .toDart)
            .toDart;
    return SampledFrame(index, timestampMs, base64Decode(encoded));
  }

  @override
  Future<void> close() async {
    if (_sourceId != null) {
      _close(_sourceId!.toJS);
      _sourceId = null;
    }
  }
}
