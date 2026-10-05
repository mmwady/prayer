import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import '../video/analysis_client.dart';
import 'socket.dart';

@JS('iqtadiLive.connect')
external JSPromise<JSString> _connect(JSString url, JSString token);
@JS('iqtadiLive.send')
external JSPromise<JSString> _send(JSNumber id, JSUint8Array bytes);
@JS('iqtadiLive.closeSocket')
external void _close(JSNumber id);
LiveSocket createLiveSocket() => WebLiveSocket();

class WebLiveSocket implements LiveSocket {
  int? _id;
  @override
  Future<void> connect(Uri url, String token) async {
    await close();
    final data = jsonDecode(
        (await _connect(url.toString().toJS, token.toJS).toDart).toDart);
    if (data['type'] == 'error') throw AnalysisApiError(data['code'] as String);
    _id = data['socket_id'] as int;
  }

  @override
  Future<Map<String, dynamic>> send(Uint8List packet) async {
    final data = jsonDecode((await _send(_id!.toJS, packet.toJS).toDart).toDart)
        as Map<String, dynamic>;
    if (data['type'] == 'error') throw AnalysisApiError(data['code'] as String);
    return data;
  }

  @override
  Future<void> close() async {
    if (_id != null) _close(_id!.toJS);
    _id = null;
  }
}
