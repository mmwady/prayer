import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../config/env.dart';
import 'analysis_report.dart';
import 'video_source.dart';

class AnalysisApiError implements Exception {
  const AnalysisApiError(this.code);
  final String code;
  @override
  String toString() {
    final explanation = switch (code) {
      'MODEL_NOT_CONFIGURED' => 'النموذجان الحقيقيان غير مهيّأين على الخادم.',
      'VIDEO_TOO_LONG' => 'الفيديو يتجاوز حدود المدة أو عدد الإطارات.',
      'INVALID_JPEG' => 'تعذر قراءة صورة مرفوعة بصيغة JPEG.',
      'FRAME_TOO_LARGE' => 'حجم إطار الفيديو أكبر من الحد المسموح.',
      'LIVE_STORAGE_LIMIT' ||
      'TEMPORARY_STORAGE_FAILED' =>
        'تعذر حفظ صور إضافية على الخادم بسبب حد التخزين أو عدم توفر مساحة. لم تُحذف الصور المحفوظة.',
      'ANALYSIS_PROCESSING_FAILED' =>
        'تعذر تحليل الصور على الخادم. لم يكتمل التقرير.',
      'ANALYSIS_TIMEOUT' => 'انتهت مهلة انتظار التحليل؛ يمكنك إعادة المحاولة.',
      'ANALYSIS_NOT_FOUND' ||
      'ANALYSIS_EXPIRED' =>
        'انتهت الوظيفة أو لم يعد رمز الوصول صالحًا.',
      _ => 'تعذر إكمال طلب التحليل. تحقق من اتصال الخادم وحاول مجددًا.',
    };
    return '$explanation ($code)';
  }
}

/// Processing/evidence contract. The application's prayer routes use a local
/// implementation; the HTTP implementation remains an explicit compatibility tool.
abstract interface class AnalysisPreparationProgress {
  Map<String, dynamic> get initializationProgress;
}

abstract interface class AnalysisService {
  bool get isLocal;
  String? get jobId;
  Future<Map<String, dynamic>> configuration();
  Future<void> create(
      String prayer, LocalVideo video, double fps, String? scenario);
  Future<void> upload(int batchIndex, List<SampledFrame> frames);
  Future<void> complete();
  Future<Map<String, dynamic>> status();
  Future<AnalysisReport> report();
  Future<Uint8List> evidence(String id);
  Future<void> delete();
  void close();
}

class AnalysisClient implements AnalysisService {
  AnalysisClient({http.Client? client, String? baseUrl})
      : _http = client ?? http.Client(),
        baseUrl = (baseUrl ?? Env.backendUrl).replaceFirst(RegExp(r'/$'), '');
  final http.Client _http;
  final String baseUrl;
  @override
  String? jobId;
  String? token;
  @override
  bool get isLocal => false;

  Uri _uri(String suffix) =>
      Uri.parse('$baseUrl/api/v1/prayer-analyses$suffix');
  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> request(String method, String suffix,
      [Object? body]) async {
    final request = http.Request(method, _uri(suffix))
      ..headers.addAll(_headers);
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
            await _http.send(request).timeout(const Duration(seconds: 30)))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 204) return {};
    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw AnalysisApiError(data['detail'].toString());
    }
    return data;
  }

  @override
  Future<Map<String, dynamic>> configuration() => request('GET', '/config');
  @override
  Future<void> create(
      String prayer, LocalVideo video, double fps, String? scenario) async {
    final data = await request('POST', '', {
      'prayer': prayer,
      'duration_ms': video.durationMs,
      'sample_fps': fps,
      'upload_consent': true,
      'scenario': scenario,
    });
    jobId = data['job_id'] as String;
    token = data['access_token'] as String;
  }

  @override
  Future<void> upload(int batchIndex, List<SampledFrame> frames) async {
    final body = {
      'batch_id': 'batch_$batchIndex',
      'frames': [
        for (final f in frames)
          {
            'frame_id': 'frame_${f.index}',
            'timestamp_ms': f.timestampMs,
            'sequence_index': f.index,
            'jpeg_base64': base64Encode(f.jpeg),
          }
      ]
    };
    // Retrying is explicit and keeps batch ID/content identical.
    await request('POST', '/$jobId/frames', body);
  }

  @override
  Future<void> complete() async => request('POST', '/$jobId/complete');
  @override
  Future<Map<String, dynamic>> status() => request('GET', '/$jobId');
  @override
  Future<AnalysisReport> report() async =>
      AnalysisReport.fromJson(await request('GET', '/$jobId/report'));
  @override
  Future<Uint8List> evidence(String id) async {
    final response = await _http
        .get(_uri('/$jobId/evidence/$id'), headers: _headers)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw const AnalysisApiError('EVIDENCE_UNAVAILABLE');
    }
    return response.bodyBytes;
  }

  @override
  Future<void> delete() async {
    if (jobId != null) {
      await request('DELETE', '/$jobId');
      jobId = token = null;
    }
  }

  @override
  void close() => _http.close();
}
