import 'dart:async';

import 'package:aura_hub/features/ai/domain/ai_exceptions.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/integrations/data/credential_vault.dart';
import 'package:aura_hub/features/integrations/data/windows_credential_vault.dart';

/// OS-backed storage for AI provider API keys.
///
/// This is the only AURA AI component allowed to obtain a raw key, and only so
/// it can hand it to the provider adapter for the lifetime of one request. Keys
/// are never written to JSON, logs, diagnostics, Riverpod state or UI models.
/// The Windows implementation uses Credential Manager through the existing
/// [CredentialVault] boundary; other platforms can inject another vault later.
class AiCredentialStore {
  AiCredentialStore({CredentialVault? vault})
      : _vault = vault ?? WindowsCredentialVault();

  /// Fail-closed store used when the platform has no supported OS vault.
  AiCredentialStore.unavailable() : _vault = const UnavailableCredentialVault();

  static const String _readFailureMessage =
      'Stored credentials could not be read. Try again.';
  static const String _writeFailureMessage =
      'The API key could not be saved. Try again.';
  static const String _deleteFailureMessage =
      'The API key could not be removed. It may still be stored on this device.';

  final CredentialVault _vault;

  /// Serialises operations for one OS target so repeated or concurrent saves,
  /// reads and deletes cannot interleave around the same credential.
  final Map<String, Future<void>> _operationTails = <String, Future<void>>{};

  /// False only for the explicit unavailable platform store.
  bool get isAvailable => _vault is! UnavailableCredentialVault;

  String targetFor({
    required String profileScope,
    required String providerId,
  }) {
    return aiCredentialTarget(
      profileScope: profileScope,
      providerId: providerId,
    );
  }

  AuraProfile _profileFor(String profileScope) => AuraProfile.values.firstWhere(
        (AuraProfile profile) => profile.storageScope == profileScope,
        orElse: () => AuraProfile.ayush,
      );

  Future<T> _serialized<T>(
      String target, Future<T> Function() operation) async {
    final Future<void> previous =
        _operationTails[target] ?? Future<void>.value();
    final Completer<void> done = Completer<void>();
    _operationTails[target] = done.future;
    try {
      await previous;
      return await operation();
    } finally {
      if (identical(_operationTails[target], done.future)) {
        _operationTails.remove(target);
      }
      if (!done.isCompleted) done.complete();
    }
  }

  AiException _credentialFailure(Object error, String fallbackMessage) {
    if (error is CredentialVaultError) {
      return AiException(
        AiFailureKind.credentialStorage,
        error.safeMessage,
        stage: AiRequestStage.prepare,
        exceptionType: error.runtimeType.toString(),
      );
    }
    return AiException(
      AiFailureKind.credentialStorage,
      fallbackMessage,
      stage: AiRequestStage.prepare,
      exceptionType: error.runtimeType.toString(),
    );
  }

  /// Reads one target and returns `null` only for a genuinely absent secret.
  ///
  /// An empty or malformed stored value is corrupt data, never a missing key.
  Future<String?> _readTarget(String target) async {
    try {
      final String? stored = await _vault.read(target: target);
      if (stored == null) return null;
      final String trimmed = stored.trim();
      if (trimmed.isEmpty) {
        throw const CredentialVaultException(
          CredentialVaultFailure.corruptData,
        );
      }
      return trimmed;
    } on CredentialStorageUnavailable {
      // Preserve the existing fail-closed platform exception contract.
      rethrow;
    } on CredentialVaultError catch (error) {
      throw _credentialFailure(error, _readFailureMessage);
    } on AiException {
      rethrow;
    } catch (error) {
      throw _credentialFailure(error, _readFailureMessage);
    }
  }

  void _requireOwner({
    required bool Function()? isWriteAllowed,
    required AuraProfile profile,
  }) {
    if (isWriteAllowed != null && !isWriteAllowed()) {
      throw AuraProfileAccessDenied(profile);
    }
  }

  /// Builds the final, synchronous boundary check handed to the vault.
  ///
  /// The vault calls this immediately before its native mutation. Returning
  /// `true` or throwing are both intentional: a throw prevents the mutation and
  /// propagates the exact access-denied error to the caller.
  bool Function() _commitGuard({
    required bool Function()? isWriteAllowed,
    required AuraProfile profile,
  }) =>
      () {
        _requireOwner(isWriteAllowed: isWriteAllowed, profile: profile);
        return true;
      };

  Future<bool> has({
    required String profileScope,
    required String providerId,
  }) async {
    final String target =
        targetFor(profileScope: profileScope, providerId: providerId);
    return _serialized(target, () async {
      final String? stored = await _readTarget(target);
      return stored != null;
    });
  }

  /// Replaces any existing key for this profile/provider pair.
  ///
  /// Ownership is checked before queueing, after the queue completes, and one
  /// final time synchronously inside the vault immediately before the native
  /// write. Once that native call starts it cannot interleave with a lock or
  /// profile switch, so a stale operation cannot commit. The post-write check
  /// below is defence-in-depth against a non-conforming injected vault; it
  /// prevents stale publication but cannot undo a commit that already happened.
  ///
  /// Credential Manager writes are atomic at the OS boundary: a failed write
  /// leaves the previous credential untouched. The returned value is an opaque
  /// target name suitable for diagnostics; it is not the key.
  Future<String> save({
    required String profileScope,
    required String providerId,
    required String apiKey,
    bool Function()? isWriteAllowed,
  }) async {
    final String secret = apiKey.trim();
    if (secret.isEmpty) {
      throw ArgumentError('API key must not be empty.');
    }
    final AuraProfile profile = _profileFor(profileScope);
    final String target =
        targetFor(profileScope: profileScope, providerId: providerId);
    _requireOwner(isWriteAllowed: isWriteAllowed, profile: profile);

    return _serialized(target, () async {
      // Revalidate inside the serialised section: the session can change while
      // an earlier vault operation for this target is still in flight.
      _requireOwner(isWriteAllowed: isWriteAllowed, profile: profile);
      try {
        await _vault.write(
          target: target,
          secret: secret,
          isCommitAllowed: _commitGuard(
            isWriteAllowed: isWriteAllowed,
            profile: profile,
          ),
        );
      } on CredentialStorageUnavailable {
        rethrow;
      } on CredentialVaultError catch (error) {
        throw _credentialFailure(error, _writeFailureMessage);
      } on AiException {
        rethrow;
      } on AuraProfileAccessDenied {
        // The commit guard rejected a stale owner. Keep the authorization
        // error intact so controllers cannot mistake it for a vault failure.
        rethrow;
      } catch (error) {
        throw _credentialFailure(error, _writeFailureMessage);
      }
      _requireOwner(isWriteAllowed: isWriteAllowed, profile: profile);
      // Return the target only: callers must never echo the secret.
      return target;
    });
  }

  /// Internal request-time secret resolution.
  ///
  /// Callers MUST keep the result transient and MUST NOT log, persist or expose
  /// it through Riverpod state or error messages.
  Future<String?> readSecret({
    required String profileScope,
    required String providerId,
  }) async {
    final String target =
        targetFor(profileScope: profileScope, providerId: providerId);
    return _serialized(target, () => _readTarget(target));
  }

  /// Removes the key for one profile/provider pair.
  ///
  /// Like [save], this passes a synchronous ownership guard to the vault at the
  /// native delete boundary so a stale private delete cannot remove a newer
  /// credential. A `false` result from the vault is surfaced as a typed
  /// credential-storage failure instead of being reported as a successful
  /// removal.
  Future<void> delete({
    required String profileScope,
    required String providerId,
    bool Function()? isWriteAllowed,
  }) async {
    final AuraProfile profile = _profileFor(profileScope);
    final String target =
        targetFor(profileScope: profileScope, providerId: providerId);
    _requireOwner(isWriteAllowed: isWriteAllowed, profile: profile);

    await _serialized(target, () async {
      _requireOwner(isWriteAllowed: isWriteAllowed, profile: profile);
      final bool deleted;
      try {
        deleted = await _vault.delete(
          target: target,
          isCommitAllowed: _commitGuard(
            isWriteAllowed: isWriteAllowed,
            profile: profile,
          ),
        );
      } on CredentialStorageUnavailable {
        rethrow;
      } on CredentialVaultError catch (error) {
        throw _credentialFailure(error, _deleteFailureMessage);
      } on AiException {
        rethrow;
      } on AuraProfileAccessDenied {
        rethrow;
      } catch (error) {
        throw _credentialFailure(error, _deleteFailureMessage);
      }
      if (!deleted) {
        throw const AiException(
          AiFailureKind.credentialStorage,
          _deleteFailureMessage,
          stage: AiRequestStage.prepare,
        );
      }
      _requireOwner(isWriteAllowed: isWriteAllowed, profile: profile);
    });
  }
}
