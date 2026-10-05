import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../prayer/prayer_definition.dart';
import '../prayer/prayer_content.dart';

/// One Arabic guidance cue returned by the backend.
class PrayerGuidance {
  const PrayerGuidance(
      {required this.text, required this.model, required this.degraded});

  final String text;

  /// Model that produced the text, or `static` for the bundled fallback.
  final String model;

  /// True when the backend could not reach the model and served static text.
  final bool degraded;
}

/// Structured session facts sent to the backend.
///
/// Deliberately narrow: it carries no keypoints, frames, images or identity.
/// Station progression stays on device — this payload only describes state so
/// the model can phrase a single cue.
class PrayerGuidanceRequest {
  const PrayerGuidanceRequest({
    required this.prayer,
    required this.station,
    required this.event,
    required this.rakah,
    required this.stationIndex,
    required this.totalStations,
    required this.retries,
    required this.coreMovementsDone,
  });

  final String prayer;
  final String station;
  final String event;
  final int rakah;
  final int stationIndex;
  final int totalStations;
  final int retries;
  final int coreMovementsDone;

  Map<String, Object> toJson() => {
        'prayer': prayer,
        'station': station,
        'event': event,
        'rakah': rakah,
        'station_index': stationIndex,
        'total_stations': totalStations,
        'retries': retries,
        'core_movements_done': coreMovementsDone,
      };
}

/// Injectable seam so the controller can run without any network in tests.
abstract class PrayerGuidanceSource {
  Future<PrayerGuidance?> request(PrayerGuidanceRequest request);

  void close();
}

/// Deterministic, bundled movement cues. No provider, HTTP request or queue.
/// Guidance never changes the sequence engine's decision or assesses validity.
class LocalPrayerGuidanceSource implements PrayerGuidanceSource {
  const LocalPrayerGuidanceSource();

  @override
  Future<PrayerGuidance?> request(PrayerGuidanceRequest request) async {
    final station = PrayerStation.values
        .where((station) => wireStation(station) == request.station);
    if (station.isEmpty ||
        !PrayerType.values
            .any((prayer) => wirePrayer(prayer) == request.prayer)) {
      return null;
    }
    final label = PrayerContent.labels[station.first]!;
    final text = switch (request.event) {
      'start' =>
        'ابدأ التدريب واتبع الحركة الموضحة: $label. ${PrayerContent.purpose}',
      'retry' => '${PrayerContent.unexpected} الحركة التالية: $label.',
      'uncertain' => '${PrayerContent.unclear}. ${PrayerContent.adjust}.',
      'completed' => 'اكتمل تدريب تسلسل الحركات. ${PrayerContent.purpose}',
      'stopped' =>
        'تم إيقاف التدريب؛ يمكنك مراجعة الحركات المرصودة والمحاولة مجددًا.',
      _ => null,
    };
    return text == null
        ? null
        : PrayerGuidance(
            text: text,
            model: 'local:${PrayerContent.version}',
            degraded: false);
  }

  @override
  void close() {}
}

/// Wire station id. Must stay identical to `STATIONS` in
/// `backend/app/prayer/guidance.py`.
String wireStation(PrayerStation station) => switch (station) {
      PrayerStation.standing => 'standing',
      PrayerStation.ruku => 'ruku',
      PrayerStation.standingAfterRuku => 'standing_after_ruku',
      PrayerStation.sujood1 => 'sujood_first',
      PrayerStation.sittingBetweenSujood => 'sitting',
      PrayerStation.sujood2 => 'sujood_second',
      PrayerStation.intermediateSitting => 'intermediate_sitting',
      PrayerStation.finalSitting => 'final_sitting',
    };

/// Wire prayer id. Must stay identical to `PRAYERS` in
/// `backend/app/prayer/guidance.py`.
String wirePrayer(PrayerType prayer) => switch (prayer) {
      PrayerType.fajr => 'fajr',
      PrayerType.dhuhr => 'dhuhr',
      PrayerType.asr => 'asr',
      PrayerType.maghrib => 'maghrib',
      PrayerType.isha => 'isha',
      PrayerType.demo => 'demo',
    };

/// Talks to `POST /api/v1/prayer-guidance`.
///
/// Guidance is advisory only: every failure returns `null` so the on-device
/// session continues untouched. There is no retry loop and no offline queue
/// because a stale cue is worse than no cue.
class PrayerGuidanceClient implements PrayerGuidanceSource {
  PrayerGuidanceClient({
    required String baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 12),
  })  : _base = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final String _base;
  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;

  Uri get endpoint => Uri.parse('$_base/api/v1/prayer-guidance');

  @override
  Future<PrayerGuidance?> request(PrayerGuidanceRequest request) async {
    try {
      final response = await _client
          .post(
            endpoint,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(request.toJson()),
          )
          .timeout(timeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) return null;
      final text = decoded['text'];
      if (text is! String || text.trim().isEmpty) return null;
      final model = decoded['model'];
      return PrayerGuidance(
        text: text.trim(),
        model: model is String ? model : 'unknown',
        degraded: decoded['degraded'] == true,
      );
    } catch (_) {
      // Offline, timeout, DNS failure or malformed JSON. The prayer session
      // must not be affected by an unavailable advisory service.
      return null;
    }
  }

  @override
  void close() {
    if (_ownsClient) _client.close();
  }
}
