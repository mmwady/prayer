import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;
import 'package:flutter/widgets.dart';
import 'camera_source.dart';

@JS('iqtadiLive.open')
external JSPromise<JSNumber> _open();
@JS('iqtadiLive.video')
external JSObject _video(JSNumber id);
@JS('iqtadiLive.frame')
external JSPromise<JSString> _frame(JSNumber id, JSNumber dimension);
@JS('iqtadiLive.closeCamera')
external void _close(JSNumber id);
@JS('iqtadiLive.awake')
external JSPromise<JSBoolean> _awake(JSBoolean enabled);

LiveCamera createLiveCamera() => WebLiveCamera();

class WebLiveCamera implements LiveCamera {
  int? _id;
  String? _view;
  Timer? _timer;
  Future<void>? _conversion;
  @override
  bool get ready => _id != null;
  @override
  Future<void> open() async {
    await close();
    final id = (await _open().toDart).toDartInt;
    _id = id;
    _view = 'live-camera-$id';
    ui_web.platformViewRegistry
        .registerViewFactory(_view!, (_) => _video(id.toJS));
  }

  @override
  Widget preview() =>
      AspectRatio(aspectRatio: 3 / 4, child: HtmlElementView(viewType: _view!));
  @override
  Future<void> capture(double fps, int maxDimension,
      void Function(int, Uint8List) onFrame, void Function(Object) onError,
      {bool Function()? shouldCapture}) async {
    final watch = Stopwatch()..start();
    _timer = Timer.periodic(Duration(milliseconds: (1000 / fps).round()), (_) {
      if (_conversion != null) return;
      if (shouldCapture?.call() == false) return;
      final timestamp = watch.elapsedMilliseconds;
      _conversion = () async {
        try {
          final encoded =
              (await _frame(_id!.toJS, maxDimension.toJS).toDart).toDart;
          if (_timer != null) onFrame(timestamp, base64Decode(encoded));
        } catch (error) {
          if (_timer != null) onError(error);
        } finally {
          _conversion = null;
        }
      }();
    });
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _conversion;
  }

  @override
  Future<bool> keepAwake(bool enabled) async =>
      (await _awake(enabled.toJS).toDart).toDart;
  @override
  Future<void> close() async {
    await stop();
    if (_id != null) _close(_id!.toJS);
    _id = null;
  }
}
