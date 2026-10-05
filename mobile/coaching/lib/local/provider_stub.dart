import 'dart:typed_data';
import 'contracts.dart';

LocalInference createLocalInference() => UnsupportedInference();
LocalSessionRepository createLocalRepository() => UnsupportedRepository();
Future<String> exportSnapshot(Map<String, dynamic> data) async =>
    throw UnsupportedError('التصدير غير متاح على هذه المنصة');

class UnsupportedInference implements LocalInference {
  Never fail() => throw UnsupportedError(
      'المحرك المحلي غير متاح لهذه المنصة؛ استخدم نسخة الويب أو Android.');
  @override
  Future<Map<String, dynamic>> initialize() async => fail();
  @override
  Future<LocalFrameResult> analyze(Uint8List jpeg) async => fail();
  @override
  Future<Map<String, dynamic>> report(String p, List<Map<String, dynamic>> s,
          Map<String, dynamic> o) async =>
      fail();
  @override
  Future<void> close() async {}
}

class UnsupportedRepository implements LocalSessionRepository {
  @override
  Future<void> save(Map<String, dynamic> m, Map<String, Uint8List> e) async =>
      throw UnsupportedError('التخزين المحلي غير متاح');
  @override
  Future<List<Map<String, dynamic>>> list() async => [];
  @override
  Future<Map<String, dynamic>?> load(String id) async => null;
  @override
  Future<Uint8List> evidence(String s, String e) async =>
      throw StateError('الصورة غير متاحة');
  @override
  Future<void> delete(String id) async {}
  @override
  Future<String> export(String id) async =>
      throw StateError('التقرير غير متاح');
}
