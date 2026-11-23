import 'package:aura_hub/core/config/aura_runtime_config.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation.dart';
import 'package:aura_hub/features/ai/domain/ai_preferences.dart';
import 'package:aura_hub/features/ai/presentation/ai_page.dart';
import 'package:aura_hub/features/ai/presentation/ai_providers.dart';
import 'package:aura_hub/features/memory/data/memory_repository.dart';
import 'package:aura_hub/features/memory/domain/memory_category.dart';
import 'package:aura_hub/features/memory/domain/memory_record.dart';
import 'package:aura_hub/features/memory/domain/memory_settings.dart';
import 'package:aura_hub/features/memory/presentation/memory_providers.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const String _messageContent =
    'I prefer short answers with practical examples.';

class _RecordingMemoryRepository implements MemoryRepository {
  @override
  AuraProfile get profile => AuraProfile.family;

  MemorySettings _settings = const MemorySettings(suggestionsEnabled: true);
  int suggestCalls = 0;
  String? content;
  MemoryCategory? category;
  String? sourceConversationId;
  String? sourceMessageId;

  @override
  Future<List<MemoryRecord>> load() async => const <MemoryRecord>[];

  @override
  Future<MemorySettings> loadSettings() async => _settings;

  @override
  Future<MemoryWriteResult> saveSettings(MemorySettings settings) async {
    _settings = settings;
    return MemoryWriteResult.ok;
  }

  @override
  Future<MemoryWriteResult> createApproved({
    required String content,
    required MemoryCategory category,
    List<String> tags = const <String>[],
    DateTime? expiresAt,
    String? sourceConversationId,
    String? sourceMessageId,
  }) async =>
      MemoryWriteResult.ok;

  @override
  Future<MemoryWriteResult> suggest({
    required String content,
    required MemoryCategory category,
    List<String> tags = const <String>[],
    DateTime? expiresAt,
    String? sourceConversationId,
    String? sourceMessageId,
  }) async {
    suggestCalls++;
    this.content = content;
    this.category = category;
    this.sourceConversationId = sourceConversationId;
    this.sourceMessageId = sourceMessageId;
    return MemoryWriteResult.ok;
  }

  @override
  Future<MemoryWriteResult> approve(String id) async => MemoryWriteResult.ok;

  @override
  Future<MemoryWriteResult> reject(String id) async => MemoryWriteResult.ok;

  @override
  Future<MemoryWriteResult> update({
    required String id,
    required String content,
    required MemoryCategory category,
    List<String> tags = const <String>[],
    DateTime? expiresAt,
  }) async =>
      MemoryWriteResult.ok;

  @override
  Future<MemoryWriteResult> delete(String id) async => MemoryWriteResult.ok;

  @override
  Future<MemoryWriteResult> clear() async => MemoryWriteResult.ok;

  @override
  Future<List<MemoryRecord>> retrieve({
    required String query,
    required DateTime now,
    int limit = AuraRuntimeConfig.maxMemoryContextItems,
  }) async =>
      const <MemoryRecord>[];

  @override
  Future<void> markAccessed(List<String> ids) async {}

  @override
  void discardForLock() {}
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required _RecordingMemoryRepository repository,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final MemoryController controller = MemoryController(
    repository,
    accessReader: () => ProfileAccess(ProfileSession.initial),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        activeProfileProvider.overrideWithValue(AuraProfile.family),
        activeAiPreferencesProvider.overrideWithValue(
          const AiPreferences(
            consentGranted: true,
            activeConversationId: 'chat-1',
          ),
        ),
        activeAiConversationsProvider.overrideWithValue(<AiConversation>[
          AiConversation(
            id: 'chat-1',
            messages: <AiMessage>[
              AiMessage(
                role: AiMessageRole.assistant,
                content: _messageContent,
                timestamp: DateTime(2026),
              ),
            ],
          ),
        ]),
        activeMemoryControllerProvider.overrideWithValue(controller),
        activeMemoryStateProvider.overrideWithValue(const MemoryState()),
      ],
      child: const MaterialApp(
        home: Scaffold(body: AiPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _memoryFieldFinder() => find.byWidgetPredicate(
      (Widget widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Information to remember',
    );

void main() {
  testWidgets('Remember uses the whole message and saves a pending suggestion',
      (WidgetTester tester) async {
    final _RecordingMemoryRepository repository = _RecordingMemoryRepository();
    await _pumpPage(tester, repository: repository);

    expect(find.byTooltip('Remember this message'), findsOneWidget);
    await tester.tap(find.byTooltip('Remember this message'));
    await tester.pumpAndSettle();

    expect(find.text('Save to AURA Memory'), findsOneWidget);
    expect(
      tester.widget<TextField>(_memoryFieldFinder()).controller!.text,
      _messageContent,
    );

    await tester.enterText(_memoryFieldFinder(), 'I prefer short answers.');
    await tester.tap(find.widgetWithText(FilledButton, 'Save as pending'));
    await tester.pumpAndSettle();

    expect(repository.suggestCalls, 1);
    expect(repository.content, 'I prefer short answers.');
    expect(repository.category, MemoryCategory.preference);
    expect(repository.sourceConversationId, 'chat-1');
    expect(repository.sourceMessageId, isNotNull);
    expect(find.textContaining('pending memory'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Remember prefills editable content from selected chat text',
      (WidgetTester tester) async {
    final _RecordingMemoryRepository repository = _RecordingMemoryRepository();
    await _pumpPage(tester, repository: repository);

    final SelectionArea selectionArea =
        tester.widget<SelectionArea>(find.byType(SelectionArea).first);
    selectionArea.onSelectionChanged!(
      const SelectedContent(plainText: 'short answers'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Remember this message'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(_memoryFieldFinder()).controller!.text,
      'short answers',
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Save as pending'));
    await tester.pumpAndSettle();

    expect(repository.suggestCalls, 1);
    expect(repository.content, 'short answers');
    expect(tester.takeException(), isNull);
  });
}
