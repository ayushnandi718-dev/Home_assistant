import 'package:aura_hub/core/platform/io_compat.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runtime platform facts used to gate features without deleting their code.
///
/// Tests override [isAndroidPlatformProvider] so the Android policy can be
/// verified on a Windows host. No capability is inferred from a saved config.
final Provider<bool> isAndroidPlatformProvider =
    Provider<bool>((Ref ref) => Platform.isAndroid);

/// Local Ollama needs a loopback service on the host computer.
///
/// It remains in the shared codebase for desktop builds, but Android must not
/// offer it as a usable provider: a phone's `127.0.0.1` is the phone itself,
/// not the Windows laptop.
final Provider<bool> localOllamaAvailableProvider =
    Provider<bool>((Ref ref) => !ref.watch(isAndroidPlatformProvider));
