import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aura_hub/features/ai/data/ai_conversation_store.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation_query.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation_repository.dart';
import 'package:aura_hub/features/ai/presentation/ai_providers.dart';
import 'package:aura_hub/features/ai/presentation/conversation_history_panel.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Directory _tempDir() => Directory.systemTemp.createTempSync('aura_phase5a_');

String _familyFile(Directory directory) =>
    '${directory.path}${Platform.pathSeparator}ai_conversations_family.json';

ProfileAccessReader _accessReader(
  AuraProfile profile, {
  bool authenticated = true,
}) =>
    () => ProfileAccess(
          ProfileSession(
            profile: profile,
            startedAt: DateTime(2026, 1, 1),
            authenticated: authenticated,
          ),
        );

Future<void> _waitUntil(bool Function() ready, String message) async {
  for (int attempt = 0; attempt < 400; attempt++) {
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail(message);
}

Future<void> _drainWrites() =>
    Future<void>.delayed(const Duration(milliseconds: 40));

class _GatedStorage implements AiConversationStorage {
  _GatedStorage({required this.inner, required this.gate});

  final AiConversationStorage inner;
  final Future<void> gate;

  @override
  Future<AiConversationLoadResult> read() async {
    await gate;
    return inner.read();
  }

  @override
  Future<void> write(List<AiConversation> conversations) =>
      inner.write(conversations);

  @override
  Future<void> clear() => inner.clear();
}

void main() {
  group('Phase 5A conversation persistence', () {
    late Directory directory;

    setUp(() {
      directory = _tempDir();
    });

    tearDown(() async {
      await _drainWrites();
      for (int attempt = 0; attempt < 10; attempt++) {
        if (!directory.existsSync()) return;
        try {
          directory.deleteSync(recursive: true);
          return;
        } on PathAccessException {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }
    });

    test('FAMILY create, message persistence, rename and restart restoration',
        () async {
      final DateTime now = DateTime(2026, 1, 15, 10, 30);
      final AiConversationLibraryController library =
          AiConversationLibraryController(
        profile: AuraProfile.family,
        storage: AiConversationStore(
            directory: directory, profile: AuraProfile.family),
        accessReader: _accessReader(AuraProfile.family),
        now: () => now,
      );
      await library.load();
      addTearDown(library.dispose);

      final String id = library.create();
      library.appendMessage(
        id,
        AiMessage(
          role: AiMessageRole.user,
          content: 'Explain local conversation storage',
          timestamp: now,
        ),
      );
      await _waitUntil(() {
        final File file = File(_familyFile(directory));
        if (!file.existsSync()) return false;
        try {
          return file
              .readAsStringSync()
              .contains('Explain local conversation storage');
        } on PathNotFoundException {
          // The atomic replace can briefly remove the path while the next
          // write is being installed. Treat that as not-ready, not a failure.
          return false;
        }
      }, 'FAMILY conversation was not persisted.');
      await library.rename(id, 'Storage notes');

      final AiConversationLibraryController restarted =
          AiConversationLibraryController(
        profile: AuraProfile.family,
        storage: AiConversationStore(
            directory: directory, profile: AuraProfile.family),
        accessReader: _accessReader(AuraProfile.family),
      );
      await restarted.load();
      addTearDown(restarted.dispose);

      expect(restarted.state, hasLength(1));
      final AiConversation restored = restarted.state.single;
      expect(restored.id, id);
      expect(restored.profileScope, 'family');
      expect(restored.title, 'Storage notes');
      expect(restored.messageCount, 1);
      expect(restored.preview, 'Explain local conversation storage');
      expect(restored.list().single.id, isNotEmpty);
      expect(restored.list().single.conversationId, id);
    });

    test('delete removes the conversation from state and storage', () async {
      final AiConversationLibraryController library =
          AiConversationLibraryController(
        profile: AuraProfile.family,
        storage: AiConversationStore(
            directory: directory, profile: AuraProfile.family),
        accessReader: _accessReader(AuraProfile.family),
      );
      await library.load();
      addTearDown(library.dispose);

      final String id = library.create();
      await _waitUntil(
        () => File(_familyFile(directory)).existsSync(),
        'FAMILY file was not created.',
      );
      await library.delete(id);

      expect(library.state, isEmpty);
      final AiConversationStore store = AiConversationStore(
          directory: directory, profile: AuraProfile.family);
      expect((await store.read()).conversations, isEmpty);
      await store.clear();
      expect(File(_familyFile(directory)).existsSync(), isFalse);
    });

    test('messages are ordered by timestamp and duplicates are ignored',
        () async {
      final AiConversationLibraryController library =
          AiConversationLibraryController(
        profile: AuraProfile.family,
        storage: InMemoryAiConversationStorage(),
        accessReader: _accessReader(AuraProfile.family),
        now: () => DateTime(2026, 1, 15),
      );
      await library.load();
      addTearDown(library.dispose);
      final String id = library.create();

      library.appendMessage(
        id,
        AiMessage(
          id: 'm2',
          role: AiMessageRole.assistant,
          content: 'second',
          timestamp: DateTime(2026, 1, 15, 10, 2),
        ),
      );
      library.appendMessage(
        id,
        AiMessage(
          id: 'm1',
          role: AiMessageRole.user,
          content: 'first',
          timestamp: DateTime(2026, 1, 15, 10, 1),
        ),
      );
      library.appendMessage(
        id,
        AiMessage(
          id: 'm1',
          role: AiMessageRole.user,
          content: 'first',
          timestamp: DateTime(2026, 1, 15, 10, 1),
        ),
      );

      final AiConversation conversation = library.state.single;
      expect(
        conversation.list().map((AiMessage message) => message.id).toList(),
        <String>['m1', 'm2'],
      );
      expect(conversation.list().first.content, 'first');
      expect(conversation.createdAt, DateTime(2026, 1, 15));
      expect(conversation.updatedAt, DateTime(2026, 1, 15, 10, 2));
    });

    test('search and date grouping use titles, messages and injected now', () {
      final DateTime now = DateTime(2026, 1, 15, 12);
      final List<AiConversation> conversations = <AiConversation>[
        AiConversation(
          id: 'today',
          profileScope: 'family',
          title: 'Groq setup',
          updatedAt: now,
          messages: <AiMessage>[
            AiMessage(
              role: AiMessageRole.user,
              content: 'plain text',
              timestamp: now,
            ),
          ],
        ),
        AiConversation(
          id: 'yesterday',
          profileScope: 'family',
          updatedAt: now.subtract(const Duration(days: 1)),
          messages: <AiMessage>[
            AiMessage(
              role: AiMessageRole.user,
              content: 'crumbling code',
              timestamp: now.subtract(const Duration(days: 1)),
            ),
          ],
        ),
        AiConversation(
          id: 'week',
          profileScope: 'family',
          updatedAt: now.subtract(const Duration(days: 4)),
        ),
        AiConversation(
          id: 'old',
          profileScope: 'family',
          updatedAt: now.subtract(const Duration(days: 30)),
        ),
      ];

      final List<AiConversationGroup> groups = groupAiConversationsByDate(
        conversations,
        now: now,
      );
      expect(
        groups.map((AiConversationGroup group) => group.label).toList(),
        <String>['Today', 'Yesterday', 'Previous 7 days', 'Older'],
      );

      expect(searchAiConversations(conversations, query: 'GROQ'), hasLength(1));
      expect(
        searchAiConversations(conversations, query: 'crumb').single.id,
        'yesterday',
      );
      expect(searchAiConversations(conversations, query: 'missing'), isEmpty);
    });

    test('profile-bound repository rejects foreign ownership', () async {
      final ProfileBoundAiConversationRepository family =
          ProfileBoundAiConversationRepository(
        profile: AuraProfile.family,
        storage: AiConversationStore(
            directory: directory, profile: AuraProfile.family),
        accessReader: _accessReader(AuraProfile.family),
      );

      expect(
        () => family.save(<AiConversation>[
          AiConversation(id: 'private', profileScope: 'ayush'),
        ]),
        throwsArgumentError,
      );
      expect((await family.load()).conversations, isEmpty);
    });

    test('AYUSH history stays in memory and is cleared on lock', () async {
      final InMemoryAiConversationStorage storage =
          InMemoryAiConversationStorage();
      ProfileSession session = ProfileSession(
        profile: AuraProfile.ayush,
        startedAt: DateTime(2026, 1, 2),
        authenticated: true,
      );
      ProfileAccess reader() => ProfileAccess(session);
      final ProfileBoundAiConversationRepository repository =
          ProfileBoundAiConversationRepository(
        profile: AuraProfile.ayush,
        storage: storage,
        accessReader: reader,
      );
      final AiConversationLibraryController library =
          AiConversationLibraryController(
        profile: AuraProfile.ayush,
        repository: repository,
        accessReader: reader,
        now: () => DateTime(2026, 1, 2),
      );
      await library.load();
      addTearDown(library.dispose);

      final String id = library.create();
      library.appendMessage(
        id,
        AiMessage(
          role: AiMessageRole.user,
          content: 'private-only-AYUSH-text',
          timestamp: DateTime(2026, 1, 2),
        ),
      );
      expect(library.state.single.list().single.content,
          'private-only-AYUSH-text');
      expect((await repository.load()).conversations, hasLength(1));

      session = ProfileSession(
        profile: AuraProfile.family,
        startedAt: DateTime(2026, 1, 2, 1),
      );
      library.discardForLock();

      expect(library.state, isEmpty);
      expect((await storage.read()).conversations, isEmpty);
      expect(() => repository.load(), throwsA(isA<AuraProfileAccessDenied>()));
      expect(
        File(
          '${directory.path}${Platform.pathSeparator}ai_conversations_ayush.json',
        ).existsSync(),
        isFalse,
      );
      for (final FileSystemEntity entity in directory.listSync()) {
        if (entity is! File) continue;
        expect(entity.readAsStringSync(),
            isNot(contains('private-only-AYUSH-text')));
      }
    });

    test('stale async loads cannot repopulate state after a lock', () async {
      final Completer<void> gate = Completer<void>();
      final InMemoryAiConversationStorage inner =
          InMemoryAiConversationStorage();
      await inner.write(<AiConversation>[
        AiConversation(id: 'old-private', profileScope: 'ayush'),
      ]);
      ProfileSession session = ProfileSession(
        profile: AuraProfile.ayush,
        startedAt: DateTime(2026, 1, 3),
        authenticated: true,
      );
      final ProfileBoundAiConversationRepository repository =
          ProfileBoundAiConversationRepository(
        profile: AuraProfile.ayush,
        storage: _GatedStorage(inner: inner, gate: gate.future),
        accessReader: () => ProfileAccess(session),
      );
      final AiConversationLibraryController library =
          AiConversationLibraryController(
        profile: AuraProfile.ayush,
        repository: repository,
        accessReader: () => ProfileAccess(session),
      );
      final Future<void> pending = library.load();
      addTearDown(library.dispose);

      session = ProfileSession(
        profile: AuraProfile.family,
        startedAt: DateTime(2026, 1, 3, 1),
      );
      library.discardForLock();
      gate.complete();
      await pending;
      await Future<void>.delayed(Duration.zero);

      expect(library.state, isEmpty);
      expect(library.recovery.phase, AiConversationLoadPhase.idle);
    });

    test('rapid profile switching keeps active histories isolated', () async {
      ProfileSession familySession = ProfileSession(
        profile: AuraProfile.family,
        startedAt: DateTime(2026, 1, 4),
      );
      ProfileSession privateSession = ProfileSession(
        profile: AuraProfile.ayush,
        startedAt: DateTime(2026, 1, 4),
        authenticated: true,
      );
      final AiConversationStore familyStore = AiConversationStore(
        directory: directory,
        profile: AuraProfile.family,
      );
      final AiConversationLibraryController family =
          AiConversationLibraryController(
        profile: AuraProfile.family,
        storage: familyStore,
        accessReader: () => ProfileAccess(familySession),
      );
      final AiConversationLibraryController private =
          AiConversationLibraryController(
        profile: AuraProfile.ayush,
        storage: InMemoryAiConversationStorage(),
        accessReader: () => ProfileAccess(privateSession),
      );
      await family.load();
      await private.load();
      addTearDown(family.dispose);
      addTearDown(private.dispose);

      family.create();
      private.create();
      expect(family.state.single.profileScope, 'family');
      expect(private.state.single.profileScope, 'ayush');

      // `create()` deliberately fire-and-forgets persistence. The store
      // serializes writes, so queueing this explicit write drains the pending
      // FAMILY commit before the switch loop; the teardown must not race it.
      await familyStore.write(family.state);

      for (int index = 0; index < 4; index++) {
        privateSession = ProfileSession(
          profile: index.isEven ? AuraProfile.ayush : AuraProfile.family,
          startedAt: DateTime(2026, 1, 4, index + 1),
          authenticated: index.isEven,
        );
        if (index.isOdd) private.discardForLock();
        await Future<void>.delayed(Duration.zero);
      }

      expect(family.state, hasLength(1));
      expect(family.state.single.profileScope, 'family');
      expect(private.state, isEmpty);
    });

    test('corrupt and legacy FAMILY history reports a recovery state',
        () async {
      final AiConversationStore store = AiConversationStore(
          directory: directory, profile: AuraProfile.family);
      final File file = store.file;

      await file.writeAsString('{not json');
      AiConversationLoadResult invalid = await store.read();
      expect(invalid.outcome, AiConversationLoadOutcome.failed);
      expect(invalid.detail, isNotNull);
      expect(invalid.conversations, isEmpty);

      await file.writeAsString(
        jsonEncode(<Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'legacy',
            'messages': <Map<String, dynamic>>[
              <String, dynamic>{
                'role': 'user',
                'content': 'from v1',
                'timestamp': DateTime(2026, 1, 1).toIso8601String(),
              },
            ],
          },
        ]),
      );
      AiConversationLoadResult migrated = await store.read();
      expect(migrated.outcome, AiConversationLoadOutcome.recovered);
      expect(migrated.detail, contains('migrated'));
      expect(migrated.conversations.single.id, 'legacy');
      expect(
          migrated.conversations.single.list().single.conversationId, 'legacy');

      await store.write(migrated.conversations);
      final Object? envelope = jsonDecode(file.readAsStringSync());
      expect(envelope, isA<Map<String, dynamic>>());
      expect((envelope as Map<String, dynamic>)['schemaVersion'], 2);
      expect(envelope['profile'], 'family');
    });

    test('streaming, secret and diagnostic metadata are normalised on write',
        () async {
      final AiConversationStore store = AiConversationStore(
          directory: directory, profile: AuraProfile.family);
      await store.write(<AiConversation>[
        AiConversation(
          id: 'metadata',
          profileScope: 'family',
          messages: <AiMessage>[
            AiMessage(
              id: 'streaming',
              role: AiMessageRole.assistant,
              content: 'partial answer',
              timestamp: DateTime(2026, 1, 5),
              delivery: AiMessageDelivery.streaming,
              metadata: <String, String>{
                'api_key': 'DO-NOT-PERSIST',
                'diagnostics': 'RAW-DIAGNOSTICS',
                'request_id': 'REQUEST-TRACE',
                'ui.note': 'safe',
              },
            ),
          ],
        ),
      ]);

      final String raw = store.file.readAsStringSync();
      expect(raw, isNot(contains('DO-NOT-PERSIST')));
      expect(raw, isNot(contains('RAW-DIAGNOSTICS')));
      expect(raw, isNot(contains('REQUEST-TRACE')));
      final AiMessage loaded =
          (await store.read()).conversations.single.list().single;
      expect(loaded.delivery, AiMessageDelivery.interrupted);
      expect(loaded.metadata.containsKey('api_key'), isFalse);
      expect(loaded.metadata.containsKey('diagnostics'), isFalse);
      expect(loaded.metadata.containsKey('request_id'), isFalse);
      expect(loaded.metadata['ui.note'], 'safe');
    });

    testWidgets('history panel groups, searches and marks AYUSH session-only',
        (WidgetTester tester) async {
      final DateTime now = DateTime(2026, 1, 15, 12);
      final ValueNotifier<AiConversationRecoveryState> recovery =
          ValueNotifier<AiConversationRecoveryState>(
        const AiConversationRecoveryState(
          phase: AiConversationLoadPhase.ready,
        ),
      );
      addTearDown(recovery.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 272,
              height: 520,
              child: ConversationHistoryPanel(
                profile: AuraProfile.ayush,
                conversations: <AiConversation>[
                  AiConversation(
                    id: 'c1',
                    profileScope: 'ayush',
                    title: 'Private Groq notes',
                    updatedAt: now,
                  ),
                  AiConversation(
                    id: 'c2',
                    profileScope: 'ayush',
                    title: 'Other chat',
                    updatedAt: now.subtract(const Duration(days: 2)),
                  ),
                ],
                activeId: 'c1',
                recovery: recovery,
                now: () => now,
                onNew: () async {},
                onOpen: (String _) async {},
                onRename: (AiConversation _) async {},
                onDelete: (AiConversation _) async {},
                onRetry: () async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Conversations'), findsOneWidget);
      expect(find.textContaining('Encrypted locally'), findsOneWidget);
      expect(find.textContaining('encrypted on this device'), findsOneWidget);
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('Private Groq notes'), findsOneWidget);

      await tester.enterText(
        find.byType(TextField),
        'groq',
      );
      await tester.pump(const Duration(milliseconds: 220));
      await tester.pumpAndSettle();
      expect(find.text('Private Groq notes'), findsOneWidget);
      expect(find.text('Other chat'), findsNothing);
    });
  });
}
