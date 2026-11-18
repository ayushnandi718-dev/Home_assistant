import 'dart:convert';

import 'package:aura_hub/features/ai/domain/ai_exceptions.dart';

/// Parses OpenAI-compatible chat-completion SSE chunks into text deltas.
///
/// A malformed `data:` payload is an error, never an excuse to invent content.
/// The parser ignores comments, keep-alive lines and metadata-only chunks.
Stream<String> parseOpenAiSse(Stream<String> source) async* {
  String buffer = '';
  bool sawDone = false;

  await for (final String chunk in source) {
    buffer = '$buffer$chunk'.replaceAll('\r\n', '\n');
    while (true) {
      final int boundary = buffer.indexOf('\n\n');
      if (boundary < 0) break;
      final String event = buffer.substring(0, boundary);
      buffer = buffer.substring(boundary + 2);
      final String? payload = _dataPayload(event);
      if (payload == null) continue;
      if (payload == '[DONE]') {
        sawDone = true;
        return;
      }
      final String? delta = _contentDelta(payload);
      if (delta != null && delta.isNotEmpty) yield delta;
    }
  }

  buffer = buffer.replaceAll('\r\n', '\n');
  if (buffer.trim().isNotEmpty) {
    final String? payload = _dataPayload(buffer);
    if (payload != null) {
      if (payload == '[DONE]') {
        sawDone = true;
      } else {
        final String? delta = _contentDelta(payload);
        if (delta != null && delta.isNotEmpty) yield delta;
      }
    }
  }

  // A clean TCP close without the SSE sentinel is not a completed answer.
  // The controller labels already-received text as interrupted.
  if (!sawDone) {
    throw const AiException(
      AiFailureKind.streamInterrupted,
      'The provider stream ended before the response was complete.',
      stage: AiRequestStage.stream,
    );
  }
}

String? _dataPayload(String event) {
  final StringBuffer data = StringBuffer();
  for (final String line in event.split('\n')) {
    if (!line.startsWith('data:')) continue;
    if (data.isNotEmpty) data.writeln();
    data.write(line.substring(5).trimLeft());
  }
  if (data.isEmpty) return null;
  final String value = data.toString().trim();
  return value.isEmpty ? null : value;
}

String? _contentDelta(String payload) {
  final Object? decoded;
  try {
    decoded = jsonDecode(payload);
  } on FormatException {
    throw const AiException(
      AiFailureKind.malformedResponse,
      'The provider returned an unreadable streaming response.',
    );
  }

  if (decoded is! Map<String, dynamic>) {
    throw const AiException(
      AiFailureKind.malformedResponse,
      'The provider returned an unexpected streaming response.',
    );
  }

  final Object? choices = decoded['choices'];
  if (choices is! List<dynamic> || choices.isEmpty) {
    // Usage-only and metadata events are valid and contain no text.
    return null;
  }
  final Object? first = choices.first;
  if (first is! Map<String, dynamic>) {
    throw const AiException(
      AiFailureKind.malformedResponse,
      'The provider returned an unexpected response choice.',
    );
  }

  final Object? delta = first['delta'] ?? first['message'];
  if (delta is! Map<String, dynamic>) return null;
  final Object? content = delta['content'];
  return content is String ? content : null;
}
