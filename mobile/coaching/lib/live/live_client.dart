import 'dart:convert';
import 'dart:typed_data';
import '../video/analysis_client.dart';
import '../video/video_source.dart';
import 'socket.dart';
import 'socket_provider.dart';

abstract interface class LiveAnalysisService implements AnalysisService {
  bool get connected;
  Map<String, dynamic>? get latestPrediction;
  List<Map<String, dynamic>> get captures;
  Future<void> createLive(String prayer, double fps, String? scenario,
      {String mode = 'adaptive'});
  Future<void> connect();
  Future<Map<String, dynamic>> sendFrame(SampledFrame frame);
  Future<Map<String, dynamic>> finishLive(int durationMs);
  Future<void> disconnect();
}

class LiveAnalysisClient extends AnalysisClient implements LiveAnalysisService {
  LiveAnalysisClient({super.client, super.baseUrl, LiveSocket? socket})
      : socket = socket ?? createLiveSocket();
  final LiveSocket socket;
  @override
  bool connected = false;
  @override
  Map<String, dynamic>? get latestPrediction => null;
  @override
  List<Map<String, dynamic>> get captures => const [];
  @override
  Future<void> createLive(String prayer, double fps, String? scenario,
      {String mode = 'adaptive'}) async {
    final data = await request('POST', '/live', {
      'prayer': prayer,
      'sample_fps': fps,
      'upload_consent': true,
      'scenario': scenario,
      'mode': mode,
    });
    jobId = data['job_id'] as String;
    token = data['access_token'] as String;
  }

  @override
  Future<void> connect() async {
    final root = Uri.parse(baseUrl);
    await socket.connect(
        root.replace(
            scheme: root.scheme == 'https' ? 'wss' : 'ws',
            path: '${root.path}/api/v1/prayer-analyses/$jobId/live'),
        token!);
    connected = true;
  }

  static Uint8List packet(SampledFrame frame) {
    final header = utf8.encode(jsonEncode({
      'frame_id': 'live_${frame.index}',
      'sequence_index': frame.index,
      'timestamp_ms': frame.timestampMs,
    }));
    final data = Uint8List(4 + header.length + frame.jpeg.length);
    ByteData.sublistView(data).setUint32(0, header.length);
    data.setRange(4, 4 + header.length, header);
    data.setRange(4 + header.length, data.length, frame.jpeg);
    return data;
  }

  @override
  Future<Map<String, dynamic>> sendFrame(SampledFrame frame) async {
    if (!connected) await connect();
    try {
      final ack = await socket.send(packet(frame));
      if (ack['type'] != 'ack' || ack['frame_id'] != 'live_${frame.index}') {
        throw StateError('LIVE_ACK_MISMATCH');
      }
      return ack;
    } catch (_) {
      await disconnect();
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> finishLive(int durationMs) async {
    return request(
        'POST', '/$jobId/live/complete', {'duration_ms': durationMs});
  }

  @override
  Future<void> disconnect() async {
    connected = false;
    await socket.close();
  }
}
