import 'offline_status.dart';

Future<OfflineStatus> readOfflineStatus() async =>
    const OfflineStatus(state: 'installed', ready: true);
Future<bool> applyOfflineUpdate() async => false;
