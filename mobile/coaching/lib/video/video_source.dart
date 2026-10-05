import 'dart:typed_data';

class LocalVideo {
  const LocalVideo({required this.name, required this.durationMs});
  final String name;
  final int durationMs;
}

class SampledFrame {
  const SampledFrame(this.index, this.timestampMs, this.jpeg);
  final int index;
  final int timestampMs;
  final Uint8List jpeg;
}

abstract class VideoSource {
  Future<LocalVideo?> pick();
  Future<SampledFrame> frame(int index, int timestampMs, int maxDimension);
  Future<void> close();
}
