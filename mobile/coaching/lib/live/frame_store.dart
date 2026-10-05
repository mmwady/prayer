import 'dart:typed_data';

/// Session-scoped bounded temporary JPEG storage.
abstract class LiveFrameStore {
  Future<void> open();
  Future<void> put(int index, Uint8List bytes);
  Future<Uint8List> read(int index);
  Future<void> remove(int index);
  Future<void> clear();
}

/// Local adaptive mode has exactly one in-flight frame; no disk round trip.
class MemoryLiveFrameStore implements LiveFrameStore {
  MemoryLiveFrameStore({required this.maxBytes});
  final int maxBytes;
  final Map<int, Uint8List> _frames = {};
  @override
  Future<void> open() => clear();
  @override
  Future<void> put(int index, Uint8List bytes) async {
    if (bytes.length > maxBytes ||
        (_frames.isNotEmpty && !_frames.containsKey(index))) {
      throw StateError('Local adaptive frame storage bound exceeded');
    }
    _frames[index] = Uint8List.fromList(bytes);
  }

  @override
  Future<Uint8List> read(int index) async {
    final frame = _frames[index];
    if (frame == null) throw StateError('Local frame is no longer available');
    return frame;
  }

  @override
  Future<void> remove(int index) async {
    _frames.remove(index);
  }

  @override
  Future<void> clear() async {
    _frames.clear();
  }
}
