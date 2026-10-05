import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

http.Client accountHttpClient() => http.Client();
const _vault = FlutterSecureStorage();
Future<String?> readAccountToken(String key) => _vault.read(key: key);
Future<void> writeAccountToken(String key, String? value) => value == null
    ? _vault.delete(key: key)
    : _vault.write(key: key, value: value);
