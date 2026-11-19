import 'dart:convert';

/// Fixed, content-free messages for AYUSH conversation storage failures.
///
/// These strings never include transcript text, file contents, Windows errors,
/// provider output, or raw exception messages. They tell the user only which
/// recovery action is permitted.
abstract final class AiConversationStorageMessages {
  static const String decryption =
      'AYUSH conversation history could not be decrypted. AURA has not changed '
      'or replaced the stored file. Restore AURA Hub app data from a trusted '
      'backup, or contact support with the storage error code.';

  static const String unreadable =
      'AYUSH conversation storage is unreadable. AURA has not changed or '
      'replaced the stored file. Restore AURA Hub app data from a trusted '
      'backup.';

  static const String migration =
      'AYUSH conversation history could not be migrated to encrypted storage. '
      'The original file was preserved. Restore AURA Hub app data from a '
      'trusted backup or retry after freeing local storage space.';

  static const String write =
      'AYUSH conversation history could not be encrypted and saved. No '
      'unencrypted fallback was written. Try again, or restore from a trusted '
      'backup.';

  static const String unsupported =
      'Encrypted AYUSH conversation history is unavailable on this device. '
      'AURA will not store private conversations in plaintext.';

  static const String locked =
      'The private workspace is locked. AYUSH conversation history was not '
      'changed.';

  static const String stale =
      'The private workspace changed while a conversation write was pending. '
      'AYUSH conversation history was not changed.';
}

/// Versioned, purpose-bound envelope for the private AYUSH conversation file.
///
/// This deliberately mirrors the memory envelope pattern without reusing its
/// scope semantics. A memory envelope has no [purposeKey] and therefore fails
/// [decode] even if an attacker copies it into the conversation file. The
/// ciphertext is produced by the existing DPAPI cipher with app-specific
/// entropy that is distinct from AYUSH memory entropy.
///
/// DPAPI `CurrentUser` protection defends against other Windows users and
/// offline access to the file. It does not defend against malware running in
/// the unlocked AYUSH session under the same Windows account.
abstract final class AiConversationStorageEnvelope {
  static const int version = 1;
  static const String cipher = 'windows-dpapi-current-user';
  static const String purpose = 'ayush-conversation-history-v1';

  /// App-specific DPAPI entropy. Not a password; never stored in a vault.
  static const String dpapiEntropy = 'aura-hub-ayush-conversations-v1';

  /// Stable private filename. Never a plaintext JSON or SQLite database.
  static const String fileName = 'ai_conversations_ayush.secure';

  /// Pre-Phase-5B plaintext files. Read-only migration candidates.
  static const List<String> legacyFileNames = <String>[
    'ai_conversations_ayush.json',
    'ai_conversations_ayush.json.bak',
    'ai_conversations_ayush.json.legacy.backup',
    'ai_conversations_ayush.json.tmp',
  ];

  static const String versionKey = 'envelopeVersion';
  static const String cipherKey = 'cipher';
  static const String scopeKey = 'scope';
  static const String purposeKey = 'purpose';
  static const String payloadKey = 'payload';

  /// Upper bound on a single ciphertext payload (64 MiB). Conversations are
  /// bounded by [AuraRuntimeConfig.maxAiConversations]; this only prevents a
  /// hostile local file from consuming unbounded memory during base64 decode.
  static const int maxCiphertextBytes = 64 * 1024 * 1024;

  static bool isEnvelope(Object? decoded) =>
      decoded is Map<String, dynamic> && decoded.containsKey(versionKey);

  static String encode({
    required List<int> ciphertext,
    required String scope,
  }) {
    return jsonEncode(<String, dynamic>{
      versionKey: version,
      cipherKey: cipher,
      scopeKey: scope,
      purposeKey: purpose,
      payloadKey: base64.encode(ciphertext),
    });
  }

  static List<int> decode(Object? decoded, {required String scope}) {
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Conversation envelope is not an object.');
    }
    if (decoded[versionKey] != version) {
      throw const FormatException('Unsupported conversation envelope version.');
    }
    if (decoded[cipherKey] != cipher) {
      throw const FormatException('Unsupported conversation envelope cipher.');
    }
    if (decoded[scopeKey] != scope) {
      throw const FormatException('Conversation envelope profile mismatch.');
    }
    if (decoded[purposeKey] != purpose) {
      throw const FormatException('Conversation envelope purpose mismatch.');
    }
    final Object? payload = decoded[payloadKey];
    if (payload is! String || payload.isEmpty) {
      throw const FormatException('Missing conversation envelope payload.');
    }
    final List<int> ciphertext;
    try {
      ciphertext = base64.decode(payload);
    } catch (_) {
      throw const FormatException('Invalid conversation envelope payload.');
    }
    if (ciphertext.isEmpty || ciphertext.length > maxCiphertextBytes) {
      throw const FormatException('Invalid conversation envelope payload.');
    }
    return ciphertext;
  }
}
