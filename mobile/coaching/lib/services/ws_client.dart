// ─────────────────────────────────────────────────────────────────────────────
// ws_client.dart
//
// WebSocket client wrapper.
//
// Responsibilities:
//   • Maintain a single persistent connection to the backend `/ws/coach`.
//   • Marshal outgoing `PoseEvent` / `PerfectSet` / `SessionEnd` as JSON text.
//   • Decode incoming binary frames via [CoachingReply.decode] and expose
//     them as a broadcast [Stream] any number of widgets can listen to.
//   • Reconnect on failure with exponential backoff, buffering outgoing
//     events during the gap so no fault reports are silently dropped.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/coaching_reply.dart';
import '../models/pose_event.dart';

class WsClient {
  WsClient(this.url);

  /// Backend WebSocket URL (e.g. `ws://10.0.2.2:8000/ws/coach`).
  final String url;

  WebSocketChannel? _channel;

  /// Broadcast so the audio player and the workout controller can both
  /// subscribe — single-subscription streams would force us to tee manually.
  final StreamController<CoachingReply> _incoming =
      StreamController<CoachingReply>.broadcast();

  /// Events queued while we're reconnecting. Bounded to avoid unbounded
  /// memory growth during a long outage; older events get dropped first
  /// because a fresh correction is more valuable than a stale one.
  final List<String> _outgoingBuffer = <String>[];
  static const int _bufferCapacity = 64;

  /// Current backoff delay. Doubles on each failure, capped at 10s.
  Duration _backoff = const Duration(milliseconds: 500);
  static const Duration _maxBackoff = Duration(seconds: 10);

  bool _disposed = false;

  /// Server → app frame stream.
  Stream<CoachingReply> get stream => _incoming.stream;

  /// Open the connection. Safe to call repeatedly — subsequent calls no-op
  /// while a channel is already open.
  Future<void> connect() async {
    if (_disposed) return;
    if (_channel != null) return;

    try {
      // `connect` is synchronous in this package — it returns a channel
      // whose stream may later error out if the URI is unreachable.
      final ch = WebSocketChannel.connect(Uri.parse(url));
      _channel = ch;

      // Successful connect → reset backoff so the next reconnect starts
      // responsive again.
      _backoff = const Duration(milliseconds: 500);

      ch.stream.listen(
        _onFrame,
        onDone: _onClosed,
        onError: (Object e, StackTrace _) => _onClosed(),
        cancelOnError: true,
      );

      // Drain any events buffered during the downtime.
      _flushBuffer();
    } catch (_) {
      _channel = null;
      _scheduleReconnect();
    }
  }

  /// Queue an event for send. Returns synchronously — actual delivery may
  /// be deferred if we're mid-reconnect.
  void send(Object event) {
    // Every event class we ship defines `toJson`, so this is generic.
    final dynamic dynEvent = event;
    final String payload = jsonEncode(dynEvent.toJson() as Map<String, dynamic>);

    final channel = _channel;
    if (channel != null) {
      channel.sink.add(payload);
      return;
    }

    // Not connected — enqueue, evicting the oldest entry if we overflow.
    if (_outgoingBuffer.length >= _bufferCapacity) {
      _outgoingBuffer.removeAt(0);
    }
    _outgoingBuffer.add(payload);
  }

  /// Politely close — sends [SessionEnd] so the server emits a summary
  /// before dropping us.
  Future<void> close() async {
    _disposed = true;
    try {
      send(const SessionEnd());
      await _channel?.sink.close();
    } catch (_) {
      // Swallow — the socket may already be gone.
    }
    await _incoming.close();
  }

  // ── private ─────────────────────────────────────────────────────────────

  void _onFrame(dynamic raw) {
    // Server frames are always binary (see schemas.py::FrameKind). Defensive
    // coercion because some WS backends wrap bytes in `List<int>`.
    if (raw is List<int>) {
      final reply = CoachingReply.decode(Uint8List.fromList(raw));
      if (reply != null) _incoming.add(reply);
    }
    // Text frames are unexpected; silently ignore to keep the stream alive.
  }

  void _onClosed() {
    _channel = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    final delay = _backoff;
    // Double with a hard ceiling.
    _backoff = Duration(
      milliseconds: (delay.inMilliseconds * 2).clamp(
        0,
        _maxBackoff.inMilliseconds,
      ),
    );
    Future<void>.delayed(delay, connect);
  }

  void _flushBuffer() {
    if (_outgoingBuffer.isEmpty) return;
    final sink = _channel?.sink;
    if (sink == null) return;
    for (final payload in _outgoingBuffer) {
      sink.add(payload);
    }
    _outgoingBuffer.clear();
  }
}
