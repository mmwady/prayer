import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'offline_status.dart';

@JS('window.iqtadiOffline')
external JSObject? get _offline;

Future<OfflineStatus> readOfflineStatus() async {
  try {
    final source = _offline;
    if (source == null) return const OfflineStatus(state: 'unavailable');
    final raw = source.callMethod<JSObject>('status'.toJS).dartify();
    if (raw is! Map) return const OfflineStatus(state: 'unavailable');
    return OfflineStatus.fromJson(Map<String, dynamic>.from(raw));
  } catch (_) {
    return const OfflineStatus(state: 'unavailable');
  }
}

Future<bool> applyOfflineUpdate() async {
  final source = _offline;
  if (source == null) return false;
  // The JS helper waits for worker activation and then reloads only following
  // this explicit user action. Polling status never initiates an update.
  final promise = source.callMethod<JSPromise<JSBoolean>>('applyUpdate'.toJS);
  return (await promise.toDart).toDart;
}
