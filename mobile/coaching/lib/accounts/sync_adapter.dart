/// Only scalar final results cross this boundary. Never pass the raw report.
class PrayerSyncAdapter {
  static String? binding;
  static Future<void> Function(String binding, Map<String, dynamic> result)?
      sink;

  static Future<void> completed(
      String? owner, Map<String, dynamic> result) async {
    if (owner == null || sink == null) return;
    await sink!(owner, result);
  }
}
