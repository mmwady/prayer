import 'provider_stub.dart'
    if (dart.library.io) 'provider_native.dart'
    if (dart.library.js_interop) 'provider_web.dart' as platform;
import 'contracts.dart';

LocalInference createLocalInference() => platform.createLocalInference();
LocalSessionRepository createLocalRepository() =>
    platform.createLocalRepository();
Future<String> exportLocalSnapshot(Map<String, dynamic> data) =>
    platform.exportSnapshot(data);
