import 'dart:async';
import 'package:aura_hub/core/platform/io_compat.dart';

import 'package:aura_hub/features/ai/domain/ai_exceptions.dart';

/// Converts raw transport errors into safe, classified [AiException]s.
///
/// This is the only place that inspects concrete `dart:io` exception types.
/// Raw messages are deliberately discarded; only a stable runtime type name is
/// retained for redacted diagnostics.
AiException classifyAiTransportError(
  Object error, {
  required AiRequestStage stage,
  required int? durationMs,
  bool cancelled = false,
  String? fallbackMessage,
}) {
  final String type = error.runtimeType.toString();
  if (cancelled) {
    return AiException(
      AiFailureKind.cancelled,
      'Generation was cancelled.',
      stage: stage,
      exceptionType: type,
      durationMs: durationMs,
    );
  }
  if (error is TimeoutException) {
    final bool streaming =
        stage == AiRequestStage.stream || stage == AiRequestStage.parse;
    return AiException(
      streaming
          ? AiFailureKind.streamingTimeout
          : AiFailureKind.connectionTimeout,
      streaming
          ? 'The provider stopped responding while streaming.'
          : 'The provider did not respond in time.',
      stage: stage,
      exceptionType: type,
      durationMs: durationMs,
    );
  }
  if (error is HandshakeException) {
    return AiException(
      AiFailureKind.tlsFailure,
      'A secure connection to the provider could not be established.',
      stage: stage,
      exceptionType: type,
      durationMs: durationMs,
    );
  }
  if (error is TlsException) {
    return AiException(
      AiFailureKind.tlsFailure,
      'The secure provider connection failed. Check the endpoint certificate.',
      stage: stage,
      exceptionType: type,
      durationMs: durationMs,
    );
  }
  if (error is SocketException) {
    final String message = error.message.toLowerCase();
    final bool dns = message.contains('failed host lookup') ||
        message.contains('name or service not known') ||
        message.contains('nodename nor servname');
    return AiException(
      dns ? AiFailureKind.dnsFailure : AiFailureKind.networkFailure,
      dns
          ? 'The provider host could not be resolved. Check the base URL and your connection.'
          : 'The provider could not be reached. Check your network connection.',
      stage: stage,
      exceptionType: type,
      durationMs: durationMs,
    );
  }
  if (error is HttpException) {
    return AiException(
      AiFailureKind.networkFailure,
      'The provider response was incomplete. Try again.',
      stage: stage,
      exceptionType: type,
      durationMs: durationMs,
    );
  }
  return AiException(
    AiFailureKind.unknown,
    fallbackMessage ?? 'The provider request could not be completed.',
    stage: stage,
    exceptionType: type,
    durationMs: durationMs,
  );
}
