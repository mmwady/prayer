import 'dart:typed_data';

abstract class LiveSocket {
  Future<void> connect(Uri url, String token);
  Future<Map<String, dynamic>> send(Uint8List packet);
  Future<void> close();
}
