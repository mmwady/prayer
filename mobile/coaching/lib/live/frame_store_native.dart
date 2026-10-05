import 'dart:io';
import 'dart:typed_data';
import 'frame_store.dart';

LiveFrameStore createLiveFrameStore() => NativeFrameStore();

class NativeFrameStore implements LiveFrameStore {
  Directory? _directory;
  @override
  Future<void> open() async {
    await clear();
    // Session restart is not supported; remove expired leftovers from a crash.
    await for (final entry in Directory.systemTemp.list(followLinks: false)) {
      if (entry is Directory &&
          entry.path
              .split(Platform.pathSeparator)
              .last
              .startsWith('iqtadi-live-')) {
        try {
          final modified = (await entry.stat()).modified;
          if (DateTime.now().difference(modified) > const Duration(hours: 1)) {
            await entry.delete(recursive: true);
          }
        } on FileSystemException {
          // A concurrent session/OS cleanup may have already removed it.
        }
      }
    }
    _directory = await Directory.systemTemp.createTemp('iqtadi-live-');
  }

  File _file(int index) => File('${_directory!.path}/$index.jpg');
  @override
  Future<void> put(int index, Uint8List bytes) =>
      _file(index).writeAsBytes(bytes, flush: true);
  @override
  Future<Uint8List> read(int index) => _file(index).readAsBytes();
  @override
  Future<void> remove(int index) async {
    final file = _file(index);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> clear() async {
    final directory = _directory;
    _directory = null;
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}
