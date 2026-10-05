class OfflineStatus {
  const OfflineStatus(
      {required this.state,
      this.ready = false,
      this.completed = 0,
      this.total = 0,
      this.version});

  final String state;
  final bool ready;
  final int completed, total;
  final String? version;

  factory OfflineStatus.fromJson(Map<String, dynamic> value) {
    int count(Object? item) =>
        item is num && item.isFinite && item >= 0 ? item.toInt() : 0;
    return OfflineStatus(
      state:
          value['state'] is String ? value['state'] as String : 'unavailable',
      ready: value['ready'] == true,
      completed: count(value['completed']),
      total: count(value['total']),
      version: value['version'] is String ? value['version'] as String : null,
    );
  }

  double? get progress => total == 0 ? null : (completed / total).clamp(0, 1);
  bool sameAs(OfflineStatus other) =>
      state == other.state &&
      ready == other.ready &&
      completed == other.completed &&
      total == other.total &&
      version == other.version;
}
