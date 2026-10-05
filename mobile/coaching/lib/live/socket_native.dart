import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../video/analysis_client.dart';
import 'socket.dart';

LiveSocket createLiveSocket() => NativeLiveSocket();

class NativeLiveSocket implements LiveSocket {
  WebSocket? _socket;
  StreamIterator<dynamic>? _messages;
  @override
  Future<void> connect(Uri url, String token) async {
    await close();
    final socket = await WebSocket.connect(url.toString())
        .timeout(const Duration(seconds: 15));
    socket.pingInterval = const Duration(seconds: 20);
    _socket = socket;
    _messages = StreamIterator(socket);
    socket.add(jsonEncode({'token': token}));
    final ready = await _next(timeout: const Duration(seconds: 90));
    if (ready['type'] != 'ready') throw StateError('LIVE_NOT_READY');
  }

  Future<Map<String, dynamic>> _next(
      {Duration timeout = const Duration(seconds: 30)}) async {
    if (!await _messages!.moveNext().timeout(timeout)) {
      throw StateError('LIVE_DISCONNECTED');
    }
    final data =
        jsonDecode(_messages!.current as String) as Map<String, dynamic>;
    if (data['type'] == 'error') throw AnalysisApiError(data['code'] as String);
    return data;
  }

  @override
  Future<Map<String, dynamic>> send(Uint8List packet) async {
    _socket!.add(packet);
    return _next();
  }

  @override
  Future<void> close() async {
    final socket = _socket;
    _socket = null;
    await _messages?.cancel();
    _messages = null;
    await socket?.close();
  }
}
