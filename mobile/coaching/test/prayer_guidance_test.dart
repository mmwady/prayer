import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:coaching/prayer/prayer_definition.dart';
import 'package:coaching/services/prayer_guidance_client.dart';

/// JSON responses must be declared UTF-8, otherwise `http.Response(String)`
/// encodes Arabic as latin1 and the client's utf8 decode would mangle it.
http.Response jsonResponse(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

PrayerGuidanceRequest sample() => PrayerGuidanceRequest(
      prayer: wirePrayer(PrayerType.dhuhr),
      station: wireStation(PrayerStation.sujood1),
      event: 'retry',
      rakah: 2,
      stationIndex: 3,
      totalStations: 6,
      retries: 2,
      coreMovementsDone: 8,
    );

void main() {
  test('every prayer and station maps to a distinct backend wire id', () {
    final prayers = PrayerType.values.map(wirePrayer).toList();
    final stations = PrayerStation.values.map(wireStation).toList();

    expect(prayers.toSet().length, PrayerType.values.length);
    expect(stations.toSet().length, PrayerStation.values.length);
    expect(prayers, isNot(contains('')));
    expect(stations, isNot(contains('')));
    // Spot-check the ids the backend validates against.
    expect(wirePrayer(PrayerType.demo), 'demo');
    expect(wireStation(PrayerStation.sittingBetweenSujood), 'sitting');
    expect(wireStation(PrayerStation.intermediateSitting), 'intermediate_sitting');
  });

  test('posts structured facts only and parses the model reply', () async {
    late http.Request captured;
    final client = PrayerGuidanceClient(
      baseUrl: 'http://10.0.0.5:8000/',
      client: MockClient((request) async {
        captured = request;
        return jsonResponse({
          'text': 'ارفع رأسك قليلًا وثبّت الوضعية',
          'model': 'deepseek-flash',
          'degraded': false,
        });
      }),
    );

    final result = await client.request(sample());

    expect(captured.method, 'POST');
    expect(captured.url.toString(),
        'http://10.0.0.5:8000/api/v1/prayer-guidance');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['prayer'], 'dhuhr');
    expect(body['station'], 'sujood_first');
    expect(body['event'], 'retry');
    expect(body['rakah'], 2);
    expect(body['core_movements_done'], 8);
    // Privacy guardrail: no pixels, keypoints, frames or identity may leave.
    for (final forbidden in [
      'keypoints', 'frames', 'image', 'video', 'user', 'name',
    ]) {
      expect(body.keys, isNot(contains(forbidden)));
    }

    expect(result!.text, 'ارفع رأسك قليلًا وثبّت الوضعية');
    expect(result.model, 'deepseek-flash');
    expect(result.degraded, isFalse);
    client.close();
  });

  test('surfaces the degraded flag from the static fallback', () async {
    final client = PrayerGuidanceClient(
      baseUrl: 'http://127.0.0.1:8000',
      client: MockClient((_) async => jsonResponse({
            'text': 'نص احتياطي',
            'model': 'static',
            'degraded': true,
          })),
    );

    final result = await client.request(sample());

    expect(result!.degraded, isTrue);
    expect(result.model, 'static');
    client.close();
  });

  test('returns null instead of throwing on any failure', () async {
    Future<PrayerGuidance?> withClient(MockClient mock) async {
      final client = PrayerGuidanceClient(
          baseUrl: 'http://127.0.0.1:8000', client: mock);
      final result = await client.request(sample());
      client.close();
      return result;
    }

    // Upstream error status.
    expect(
      await withClient(MockClient((_) async => jsonResponse({}, status: 503))),
      isNull,
    );
    // Malformed JSON body.
    expect(
      await withClient(MockClient((_) async => http.Response('not json', 200))),
      isNull,
    );
    // Well-formed but empty content.
    expect(
      await withClient(MockClient((_) async => jsonResponse({
            'text': '   ',
            'model': 'deepseek-flash',
            'degraded': false,
          }))),
      isNull,
    );
    // Offline / DNS failure.
    expect(
      await withClient(MockClient((_) async => throw const SocketFailure())),
      isNull,
    );
  });
}

class SocketFailure implements Exception {
  const SocketFailure();
}
