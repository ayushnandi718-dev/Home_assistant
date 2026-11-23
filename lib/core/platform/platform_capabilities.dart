import 'package:aura_hub/core/platform/io_compat.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runtime platform facts used to gate features without deleting their code.
///
/// Tests override [isAndroidPlatformProvider] so the Android policy can be
/// verified on a Windows host. No capability is inferred from a saved config.
final Provider<bool> isAndroidPlatformProvider =
    Provider<bool>((Ref ref) => Platform.isAndroid);

/// The desktop platform that hosts the only currently implemented OS vault.
///
/// Tests override this so Windows-only storage behaviour can be verified on
/// any host without touching a real credential API.
final Provider<bool> isWindowsPlatformProvider =
    Provider<bool>((Ref ref) => Platform.isWindows);

/// Whether a supported OS-backed credential vault exists on this build.
///
/// Windows Credential Manager is the only implemented secure storage backend.
/// Android must report unavailable until its secure storage milestone lands,
/// and no web/other platform may silently fall back to plaintext.
final Provider<bool> credentialVaultAvailableProvider = Provider<bool>(
    (Ref ref) =>
        ref.watch(isWindowsPlatformProvider) &&
        !ref.watch(isAndroidPlatformProvider));

/// Local Ollama needs a loopback service on the host computer.
///
/// It remains in the shared codebase for desktop builds, but Android must not
/// offer it as a usable provider: a phone's `127.0.0.1` is the phone itself,
/// not the Windows laptop.
final Provider<bool> localOllamaAvailableProvider =
    Provider<bool>((Ref ref) => !ref.watch(isAndroidPlatformProvider));
