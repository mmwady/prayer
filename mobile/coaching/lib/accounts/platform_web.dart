import 'package:http/http.dart' as http;
import 'package:http/browser_client.dart';

http.Client accountHttpClient() => BrowserClient()..withCredentials = true;
// Web session credentials live exclusively in HttpOnly backend cookies.
Future<String?> readAccountToken(String key) async => null;
Future<void> writeAccountToken(String key, String? value) async {}
