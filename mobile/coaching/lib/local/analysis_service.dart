import 'dart:typed_data';
import '../video/analysis_client.dart';
import '../video/analysis_report.dart';
import '../video/video_source.dart';
import '../live/live_client.dart';
import 'session.dart';
import 'contracts.dart';

abstract interface class LocalResultsService implements AnalysisService {
  Future<void> deleteSaved();
  Future<String> export();
}

class LocalAnalysisService
    implements
        AnalysisService,
        LocalResultsService,
        AnalysisPreparationProgress {
  LocalAnalysisService({LocalSession? session})
      : session = session ?? LocalSession();
  final LocalSession session;
  @override
  Map<String, dynamic> get initializationProgress {
    final inference = session.inference;
    return inference is InitializationProgressSource
        ? (inference as InitializationProgressSource).initializationProgress
        : const {};
  }

  @override
  bool get isLocal => true;
  @override
  String? get jobId => session.id;
  @override
  Future<Map<String, dynamic>> configuration() => session.initialize();
  @override
  Future<void> create(String p, LocalVideo v, double f, String? s) =>
      session.create(p);
  @override
  Future<void> upload(int b, List<SampledFrame> frames) async {
    for (final f in frames) {
      await session.add(f);
    }
  }

  @override
  Future<void> complete() => session.complete();
  @override
  Future<Map<String, dynamic>> status() async => session.status();
  @override
  Future<AnalysisReport> report() async => session.report;
  @override
  Future<Uint8List> evidence(String id) => session.evidence(id);
  @override
  Future<void> delete() => session.discard();
  @override
  Future<void> deleteSaved() => session.deleteSaved();
  @override
  Future<String> export() => session.export();
  @override
  void close() => session.close();
}

class LocalLiveAnalysisService extends LocalAnalysisService
    implements LiveAnalysisService {
  LocalLiveAnalysisService({super.session});
  @override
  bool connected = false;
  @override
  Map<String, dynamic>? get latestPrediction => session.latest;
  @override
  List<Map<String, dynamic>> get captures => session.captures;
  @override
  Future<void> createLive(String p, double fps, String? scenario,
          {String mode = 'adaptive'}) =>
      session.create(p);
  @override
  Future<void> connect() async {
    connected = true;
  }

  @override
  Future<Map<String, dynamic>> sendFrame(SampledFrame f) async {
    await session.add(f, live: true);
    return {'type': 'ack', 'frame_id': 'live_${f.index}', ...session.status()};
  }

  @override
  Future<Map<String, dynamic>> finishLive(int duration) async {
    await session.complete();
    return session.status();
  }

  @override
  Future<void> disconnect() async {
    connected = false;
  }
}
