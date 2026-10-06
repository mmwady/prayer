import 'dart:js_interop';

import 'package:http/http.dart' as http;
import 'package:http/browser_client.dart';

import 'codes.dart';

@JS('window.history.replaceState')
external void _replaceState(JSAny? state, JSString title, JSString url);
@JS('window.location.href')
external JSString get _locationHref;

http.Client accountHttpClient() => BrowserClient()..withCredentials = true;
// Web session credentials live exclusively in HttpOnly backend cookies.
Future<String?> readAccountToken(String key) async => null;
Future<void> writeAccountToken(String key, String? value) async {}

String? initialAccountPairingCode() {
  final value = normalizeAccountCode(_locationHref.toDart);
  return detectAccountCodeKind(value) == 'DEVICE' ? value : null;
}

void clearAccountPairingLink() {
  final clean = Uri.parse(_locationHref.toDart)
      .replace(query: '', fragment: '')
      .toString();
  _replaceState(null, ''.toJS, clean.toJS);
}
