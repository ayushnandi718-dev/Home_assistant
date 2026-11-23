import 'dart:ffi';

import 'package:aura_hub/features/integrations/data/credential_vault.dart';
import 'package:aura_hub/features/integrations/data/windows_credential_token_store.dart';
import 'package:aura_hub/features/integrations/data/windows_credential_vault.dart';
import 'package:aura_hub/features/integrations/domain/integration_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory fake. No FFI, no real credential APIs, no real secrets.
class FakeCredentialVault implements CredentialVault {
  final Map<String, String> secrets = <String, String>{};

  @override
  Future<void> write({
    required String target,
    required String secret,
    bool Function()? isCommitAllowed,
  }) async {
    secrets[target] = secret;
  }

  @override
  Future<String?> read({required String target}) async => secrets[target];

  @override
  Future<bool> delete({
    required String target,
    bool Function()? isCommitAllowed,
  }) async =>
      secrets.remove(target) != null;
}

void main() {
  const String scope = 'family';
  const String fakeSecret = 'FAKE-TEST-VALUE-not-a-real-token';

  group('credentialTarget', () {
    test('is stable and contains no secret material', () {
      final String first = credentialTarget(IntegrationService.gmail, scope);
      final String second = credentialTarget(IntegrationService.gmail, scope);

      expect(first, second);
      expect(first, 'AURA_HUB/family/gmail');
      expect(first, isNot(contains(fakeSecret)));
    });

    test('sanitises separators, newlines and control characters', () {
      final String dirty = 'a/b\\c\nd\re${String.fromCharCode(0)}f';
      final String target = credentialTarget(IntegrationService.github, dirty);

      expect(target, startsWith('AURA_HUB/'));
      expect(target, endsWith('/github'));
      expect(target, isNot(contains('\n')));
      expect(target, isNot(contains('\r')));
      expect(target, isNot(contains(String.fromCharCode(0))));
      // Only a single scope segment remains between the prefix and service.
      expect(target.split('/').length, 3);
    });

    test('empty scopes fall back to a safe default', () {
      expect(
        credentialTarget(IntegrationService.weather, ''),
        'AURA_HUB/default/weather',
      );
    });
  });

  group('WindowsCredentialTokenStore (fake vault)', () {
    late FakeCredentialVault vault;
    late WindowsCredentialTokenStore store;

    setUp(() {
      vault = FakeCredentialVault();
      store = WindowsCredentialTokenStore(vault: vault);
    });

    test('storeToken returns the target name, never the secret', () async {
      final String handle = await store.storeToken(
        service: IntegrationService.gmail,
        storageScope: scope,
        tokenReference: fakeSecret,
      );

      expect(handle, credentialTarget(IntegrationService.gmail, scope));
      expect(handle, isNot(contains(fakeSecret)));
      expect(vault.secrets[handle], fakeSecret);
    });

    test('hasToken reflects writes and deletes', () async {
      expect(
        await store.hasToken(
          service: IntegrationService.spotify,
          storageScope: scope,
        ),
        isFalse,
      );

      await store.storeToken(
        service: IntegrationService.spotify,
        storageScope: scope,
        tokenReference: fakeSecret,
      );
      expect(
        await store.hasToken(
          service: IntegrationService.spotify,
          storageScope: scope,
        ),
        isTrue,
      );

      await store.deleteToken(
        service: IntegrationService.spotify,
        storageScope: scope,
      );
      expect(
        await store.hasToken(
          service: IntegrationService.spotify,
          storageScope: scope,
        ),
        isFalse,
      );
    });

    test('overwriting a target replaces the stored value', () async {
      const String replacement = 'FAKE-TEST-VALUE-replacement';
      final String handle = await store.storeToken(
        service: IntegrationService.github,
        storageScope: scope,
        tokenReference: fakeSecret,
      );
      await store.storeToken(
        service: IntegrationService.github,
        storageScope: scope,
        tokenReference: replacement,
      );

      expect(vault.secrets.length, 1);
      expect(vault.secrets[handle], replacement);
      expect(vault.secrets[handle], isNot(fakeSecret));
    });

    test('scopes with slashes and newlines are isolated', () async {
      final String first = await store.storeToken(
        service: IntegrationService.gmail,
        storageScope: 'team/a',
        tokenReference: fakeSecret,
      );
      final String second = await store.storeToken(
        service: IntegrationService.gmail,
        storageScope: 'team\na',
        tokenReference: 'FAKE-TEST-VALUE-other',
      );

      expect(first, second);
      expect(vault.secrets.length, 1);
      expect(vault.secrets[first], 'FAKE-TEST-VALUE-other');
    });
  });

  group('WindowsCredentialVault native layout', () {
    test('CREDENTIAL struct is 80 bytes on x64', () {
      expect(sizeOf<Credential>(), 80);
    });
  });
}
