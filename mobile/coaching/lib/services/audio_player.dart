// ─────────────────────────────────────────────────────────────────────────────
// audio_player.dart
//
// Streaming MP3 playback for incoming TTS chunks.
//
// Core idea
// ---------
// `just_audio` can play from a [StreamAudioSource] — a custom source that
// serves byte ranges from arbitrary data. We keep a growing in-memory buffer
// of MP3 bytes; the player reads from it as if it were a file. Feeding new
// bytes into the buffer while it's already playing keeps audio continuous
// across multiple TTS cue deliveries.
//
// Why this beats "save each chunk as a file and queue them":
//   • No filesystem I/O on the hot path.
//   • No audible gaps between chunks — MP3 frames concatenate cleanly.
//   • The player can start playback after the very first chunk arrives.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

class CoachingAudioPlayer {
  CoachingAudioPlayer() {
    _prime();
  }

  final AudioPlayer _player = AudioPlayer();
  _StreamingMp3Source? _source;

  /// Feed a new MP3 chunk from the WebSocket into the playback buffer.
  ///
  /// If this is the first chunk of a reply, we also tell `just_audio` to
  /// start playing — subsequent chunks just extend the buffer the player is
  /// already reading from.
  Future<void> feed(Uint8List chunk) async {
    final source = _source;
    if (source == null) return;
    source.append(chunk);

    // `playing` is false both before the first chunk AND after the previous
    // reply finished; in both cases we want to (re)start playback.
    if (!_player.playing) {
      await _player.play();
    }
  }

  /// Reset the buffer between replies so a new TTS segment starts clean.
  ///
  /// Called by the workout controller when a [ReplyKind.caption] frame
  /// arrives — that marks the end of the current coaching cue.
  Future<void> seal() async {
    _source?.seal();
    // Wait for playback to finish draining the current buffer before
    // swapping in a fresh source — avoids clipping the tail of the reply.
    await _player.playerStateStream.firstWhere(
      (s) => s.processingState == ProcessingState.completed,
      orElse: () => _player.playerState,
    );
    await _prime();
  }

  Future<void> dispose() async {
    await _player.dispose();
  }

  Future<void> _prime() async {
    _source = _StreamingMp3Source();
    // Setting the source eagerly is fine — `just_audio` won't start playback
    // until there are bytes AND we call `play()`.
    await _player.setAudioSource(_source!, preload: false);
  }
}

/// Custom audio source that lets us append bytes over time.
///
/// [just_audio]'s native players fetch byte ranges via HTTP Range-style
/// requests; our override serves them from an in-memory buffer. When the
/// player asks for a range that isn't yet in the buffer, we wait on a
/// `Completer` until the next `append` call wakes us.
class _StreamingMp3Source extends StreamAudioSource {
  _StreamingMp3Source() : super(tag: 'coaching-tts');

  final List<int> _buffer = <int>[];
  Completer<void>? _waiter;
  bool _sealed = false;

  /// Add MP3 bytes to the buffer and wake any pending reader.
  void append(Uint8List chunk) {
    _buffer.addAll(chunk);
    _waiter?.complete();
    _waiter = null;
  }

  /// Mark the buffer final — subsequent reads past EOF return empty instead
  /// of blocking forever.
  void seal() {
    _sealed = true;
    _waiter?.complete();
    _waiter = null;
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;

    // If the player is asking for data we don't yet have, wait for more.
    while (!_sealed && (end == null || end > _buffer.length)) {
      _waiter ??= Completer<void>();
      await _waiter!.future;
    }

    final effectiveEnd = end ?? _buffer.length;
    final bytes = Uint8List.fromList(_buffer.sublist(start, effectiveEnd));

    return StreamAudioResponse(
      // Content length is "unknown" while the stream grows; that's fine —
      // just_audio supports indeterminate-length streaming sources.
      sourceLength: _sealed ? _buffer.length : null,
      contentLength: bytes.length,
      offset: start,
      contentType: 'audio/mpeg',
      stream: Stream.value(bytes),
    );
  }
}
