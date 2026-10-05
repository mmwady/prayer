import 'dart:typed_data';
import 'package:flutter/widgets.dart';

abstract class LiveCamera {
  bool get ready;
  Future<void> open();
  Widget preview();
  Future<void> capture(
      double fps,
      int maxDimension,
      void Function(int timestampMs, Uint8List jpeg) onFrame,
      void Function(Object error) onError,
      {bool Function()? shouldCapture});
  Future<void> stop();
  Future<bool> keepAwake(bool enabled);
  Future<void> close();
}
