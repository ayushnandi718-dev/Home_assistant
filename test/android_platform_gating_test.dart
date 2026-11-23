import 'package:aura_hub/core/platform/platform_capabilities.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_config.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_registry.dart';
import 'package:aura_hub/features/ai/presentation/ai_page.dart';
import 'package:aura_hub/features/ai/presentation/ai_providers.dart';
import 'package:aura_hub/features/integrations/data/credential_vault.dart';
import 'package:aura_hub/features/integrations/presentation/integration_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android registry omits Ollama without deleting the adapter code', () {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        isAndroidPlatformProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);

    final AiProviderRegistry registry =
        container.read(aiProviderRegistryProvider);
    const AiProviderConfig local = AiProviderConfig(
      id: 'ollama',
      label: 'Local Ollama',
      kind: AiProviderKind.localOllama,
      baseUrl: 'http://127.0.0.1:11434',
      model: 'qwen2.5:3b',
    );
    const AiProviderConfig cloud = AiProviderConfig(
      id: 'groq',
      label: 'Groq',
      kind: AiProviderKind.openAiCompatible,
      baseUrl: 'https://api.groq.com/openai/v1',
      model: 'openai/gpt-oss-120b',
    );

    expect(registry.supports(local), isFalse);
    expect(
      registry.descriptors.map((AiProviderDescriptor item) => item.kind),
      isNot(contains(AiProviderKind.localOllama)),
    );
    expect(registry.supports(cloud), isTrue);
  });

  test('unsupported platforms gate vault-backed providers and fail closed',
      () async {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        isAndroidPlatformProvider.overrideWithValue(true),
        isWindowsPlatformProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(credentialVaultAvailableProvider), isFalse);

    final store = container.read(aiCredentialStoreProvider);
    expect(store.isAvailable, isFalse);
    expect(
      await store.has(
        profileScope: 'family',
        providerId: 'groq',
      ),
      isFalse,
    );
    expect(
      await store.readSecret(
        profileScope: 'family',
        providerId: 'groq',
      ),
      isNull,
    );
    await expectLater(
      store.save(
        profileScope: 'family',
        providerId: 'groq',
        apiKey: 'MUST-NOT-BE-STORED',
      ),
      throwsA(isA<CredentialStorageUnavailable>()),
    );
    expect(container.read(integrationTokenStoreProvider), isNull);
  });

  testWidgets('Android blocks Ollama selection but keeps Groq visible',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          isAndroidPlatformProvider.overrideWithValue(true),
          isWindowsPlatformProvider.overrideWithValue(false),
        ],
        child: const MaterialApp(
          home: Scaffold(body: AiPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Provider'));
    await tester.pumpAndSettle();

    expect(find.text('Provider configuration'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Cloud'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Local'), findsNothing);
    expect(find.text('Local models are desktop-only'), findsWidgets);
    expect(
        find.text('Secure credential storage is unavailable'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Use Groq endpoint'),
        findsOneWidget);
    expect(find.text('Groq'), findsWidgets);

    final TextField apiKeyField = tester.widget<TextField>(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is TextField && widget.decoration?.labelText == 'API key',
      ),
    );
    expect(apiKeyField.enabled, isFalse);

    final OutlinedButton ollamaButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Use local Ollama'),
    );
    expect(ollamaButton.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
