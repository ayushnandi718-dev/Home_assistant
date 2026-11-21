import 'package:aura_hub/core/platform/io_compat.dart';

import 'package:aura_hub/core/utilities/local_paths.dart';
import 'package:aura_hub/features/memory/data/memory_cipher.dart';
import 'package:aura_hub/features/memory/data/secure_memory_file.dart';
import 'package:aura_hub/features/security/domain/ayush_security_settings.dart';

/// Storage boundary for AYUSH-only security preferences.
abstract interface class AyushSecuritySettingsStorage {
  Future<AyushSecuritySettings> load();
  Future<void> save(AyushSecuritySettings settings);
}

/// Encrypted AYUSH security settings.
///
/// Uses the same [SecureMemoryFile] guarantees as private memory: validated
/// legacy plaintext is migrated once, ciphertext is verified after decryption,
/// writes are atomically replaced, and any integrity failure throws instead of
/// returning an empty or insecure payload. There is intentionally no plaintext
/// fallback implementation.
class EncryptedAyushSecuritySettingsStore
    implements AyushSecuritySettingsStorage {
  EncryptedAyushSecuritySettingsStore({
    Directory? directory,
    required MemoryCipher cipher,
  }) : _file = SecureMemoryFile(
          file: File(
            '${(directory ?? LocalPaths.appData()).path}${Platform.pathSeparator}'
            'ayush_security_settings.json',
          ),
          scope: 'ayush',
          cipher: cipher,
          validatePayload: AyushSecuritySettings.isValidPayload,
        );

  final SecureMemoryFile _file;

  @override
  Future<AyushSecuritySettings> load() async {
    final Object? payload = await _file.read();
    if (payload == null) return AyushSecuritySettings.defaults;
    return AyushSecuritySettings.fromJson(payload);
  }

  @override
  Future<void> save(AyushSecuritySettings settings) async {
    await _file.write(settings.toJson());
  }
}
