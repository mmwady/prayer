// ─────────────────────────────────────────────────────────────────────────────
// coaching_reply.dart
//
// Typed decoding of downstream WebSocket frames.
//
// Wire format (must match backend/app/schemas.py::FrameKind):
//   first byte = kind → { 0x01: caption, 0x02: audio, 0x03: summary }
//   remaining bytes = payload (JSON for kind 0x01 / 0x03, raw audio for 0x02).
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';

/// Kind tag of a downstream frame. Value must match [FrameKind] in schemas.py.
enum ReplyKind {
  caption, // 0x01
  audio,   // 0x02
  summary, // 0x03
}

/// Decoded WebSocket frame. Exactly one of [captionText] / [audioBytes] /
/// [summary] is populated based on [kind].
class CoachingReply {
  const CoachingReply._({
    required this.kind,
    this.captionText,
    this.audioBytes,
    this.summary,
  });

  final ReplyKind kind;
  final String? captionText;
  final Uint8List? audioBytes;
  final SessionSummary? summary;

  /// Parse a binary frame as received from the WebSocket.
  ///
  /// Returns `null` for an unrecognized kind byte rather than throwing —
  /// forward-compatibility with future server frame kinds we don't yet
  /// handle shouldn't kill the session.
  static CoachingReply? decode(Uint8List frame) {
    if (frame.isEmpty) return null;
    final kindByte = frame[0];
    final body = Uint8List.sublistView(frame, 1);
    switch (kindByte) {
      case 0x01:
        // Caption: UTF-8 JSON with a `text` field.
        final obj = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
        return CoachingReply._(
          kind: ReplyKind.caption,
          captionText: obj['text'] as String?,
        );
      case 0x02:
        // Audio: raw bytes, format depends on TTS provider (MP3 today).
        return CoachingReply._(kind: ReplyKind.audio, audioBytes: body);
      case 0x03:
        // Summary: UTF-8 JSON matching [SessionSummary] on the backend.
        final obj = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
        return CoachingReply._(
          kind: ReplyKind.summary,
          summary: SessionSummary.fromJson(obj),
        );
      default:
        return null;
    }
  }
}

/// End-of-session aggregate mirroring backend `SessionSummary`.
class SessionSummary {
  const SessionSummary({
    required this.totalReps,
    required this.perfectReps,
    required this.errors,
    required this.durationS,
  });

  final int totalReps;
  final int perfectReps;
  final Map<String, int> errors;
  final double durationS;

  factory SessionSummary.fromJson(Map<String, dynamic> json) {
    // `cast<>` on maps is safer than `as` — coerces values that came in as
    // `num` into `int` where needed.
    final errs = (json['errors'] as Map).map<String, int>(
      (k, v) => MapEntry(k as String, (v as num).toInt()),
    );
    return SessionSummary(
      totalReps: (json['total_reps'] as num).toInt(),
      perfectReps: (json['perfect_reps'] as num).toInt(),
      errors: errs,
      durationS: (json['duration_s'] as num).toDouble(),
    );
  }
}
