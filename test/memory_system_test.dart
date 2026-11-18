import 'dart:convert';
import 'dart:io';

import 'package:aura_hub/features/memory/data/memory_repository.dart';
import 'package:aura_hub/features/memory/data/memory_settings_store.dart';
import 'package:aura_hub/features/memory/data/memory_store.dart';
import 'package:aura_hub/features/memory/domain/memory_category.dart';
import 'package:aura_hub/features/memory/domain/memory_record.dart';
import 'package:aura_hub/features/memory/domain/memory_retrieval.dart';
import 'package:aura_hub/features/memory/domain/memory_safety.dart';
import 'package:aura_hub/features/memory/domain/memory_settings.dart';
import 'package:aura_hub/features/memory/domain/memory_status.dart';
import 'package:aura_hub/features/memory/presentation/memory_page.dart';
import 'package:aura_hub/features/memory/presentation/memory_providers.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

MemoryRecord _record({
  required AuraProfile profile,
  String id = 'mem-test',
  String content = 'I prefer concise explanations with practical examples.',
  MemoryCategory category = MemoryCategory.preference,
  MemoryStatus status = MemoryStatus.approved,
  List<String> tags = const <String>[],
  DateTime? updatedAt,
  DateTime? expiresAt,
}) {
  final DateTime stamp = updatedAt ?? DateTime(2024, 1, 1);
  return MemoryRecord(
    id: id,
    profile: profile,
    content: content,
    category: category,
    status: status,
    createdAt: stamp,
    updatedAt: stamp,
    tags: tags,
    expiresAt: expiresAt,
  );
}

class _MemoryHarness {
  _MemoryHarness() {
    directory = Directory.systemTemp.createTempSync('aura_memory_system_');
    ayushStore = MemoryStore(directory: directory, profile: AuraProfile.ayush);
    familyStore =
        MemoryStore(directory: directory, profile: AuraProfile.family);
    ayushSettings =
        MemorySettingsStore(directory: directory, profile: AuraProfile.ayush);
    familySettings =
        MemorySettingsStore(directory: directory, profile: AuraProfile.family);
    ayush = LocalMemoryRepository(
      profile: AuraProfile.ayush,
      store: ayushStore,
      settingsStore: ayushSettings,
      accessReader: _access,
    );
    family = LocalMemoryRepository(
      profile: AuraProfile.family,
      store: familyStore,
      settingsStore: familySettings,
      accessReader: _access,
    );
  }

  ProfileAccess _access() => ProfileAccess(session);

  late final Directory directory;
  ProfileSession session = ProfileSession.initial;
  late final MemoryStore ayushStore;
  late final MemoryStore familyStore;
  late final MemorySettingsStore ayushSettings;
  late final MemorySettingsStore familySettings;
  late final MemoryRepository ayush;
  late final MemoryRepository family;

  void unlockAyush() {
    session = ProfileSession(
      profile: AuraProfile.ayush,
      startedAt: DateTime(2024),
      authenticated: true,
    );
  }

  void lock() => session = ProfileSession.initial;

  void dispose() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}

class _WidgetMemoryRepository implements MemoryRepository {
  _WidgetMemoryRepository(this.profile, this.records);

  @override
  final AuraProfile profile;
  final List<MemoryRecord> records;
  MemorySettings _settings = const MemorySettings(retrievalEnabled: true);

  @override
  Future<List<MemoryRecord>> load() async => records;

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
  }) async =>
      MemoryWriteResult.ok;

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
    int limit = 5,
  }) async =>
      records.where((MemoryRecord item) => item.isRetrievableAt(now)).toList();

  @override
  Future<void> markAccessed(List<String> ids) async {}

  @override
  void discardForLock() {}
}

void main() {
  group('MemoryRecord domain', () {
    test('round-trips a complete record with an explicit allowlist', () {
      final MemoryRecord record = _record(
        profile: AuraProfile.family,
        tags: const <String>['household', 'preferences'],
        expiresAt: DateTime(2027, 1, 1),
      );

      final Map<String, dynamic> json = record.toJson();
      expect(json['schema'], MemoryRecord.schemaVersion);
      expect(json['profile'], 'family');
      expect(json['status'], 'approved');
      expect(
        json.keys,
        isNot(anyOf(
          contains('password'),
          contains('apiKey'),
          contains('pin'),
          contains('token'),
        )),
      );

      final MemoryRecord? restored =
          MemoryRecord.tryFromJson(json, profile: AuraProfile.family);
      expect(restored, isNotNull);
      expect(restored!.id, record.id);
      expect(restored.content, record.content);
      expect(restored.tags, record.tags);
      expect(restored.expiresAt, record.expiresAt);
      expect(restored.isRetrievableAt(DateTime(2026)), isTrue);
    });

    test('rejects foreign-scope, future-schema and malformed records', () {
      final MemoryRecord record = _record(profile: AuraProfile.ayush);
      final Map<String, dynamic> json = record.toJson();

      expect(
        MemoryRecord.tryFromJson(json, profile: AuraProfile.family),
        isNull,
      );
      expect(
        MemoryRecord.tryFromJson(
          <String, dynamic>{...json, 'schema': 99},
          profile: AuraProfile.ayush,
        ),
        isNull,
      );
      expect(
        MemoryRecord.tryFromJson(
          <String, dynamic>{...json, 'content': ' '},
          profile: AuraProfile.ayush,
        ),
        isNull,
      );
      expect(
        MemoryRecord.tryFromJson('not a map', profile: AuraProfile.ayush),
        isNull,
      );
    });

    test('safety rejects credentials without echoing them', () {
      for (final String value in <String>[
        'My password is hunter2',
        'The API key is FAKE-KEY-4821',
        'PIN is 4821',
        'Use this OTP when asked',
        'Card number 4111111111111111',
      ]) {
        expect(MemorySafety.isSensitive(value), isTrue, reason: value);
        expect(MemorySafety.rejectionFor(value), MemorySafety.rejectedMessage);
        expect(MemorySafety.rejectedMessage, isNot(contains(value)));
      }
      expect(
        MemorySafety.isSensitive('I prefer explanations with examples.'),
        isFalse,
      );
    });

    test('deterministic ranking favours relevant approved records', () {
      final DateTime now = DateTime(2026, 1, 1);
      final List<MemoryRecord> candidates = <MemoryRecord>[
        _record(
          profile: AuraProfile.family,
          id: 'old',
          content: 'Unrelated household note',
          updatedAt: DateTime(2025, 1, 1),
        ),
        _record(
          profile: AuraProfile.family,
          id: 'match',
          content: 'I prefer concise explanations with practical examples.',
          updatedAt: DateTime(2025, 11, 1),
        ),
        _record(
          profile: AuraProfile.family,
          id: 'pending',
          status: MemoryStatus.pending,
          content: 'concise explanations',
          updatedAt: now,
        ),
        _record(
          profile: AuraProfile.family,
          id: 'expired',
          content: 'concise explanations',
          updatedAt: now,
          expiresAt: DateTime(2025, 6, 1),
        ),
      ];

      final List<MemoryRecord> ranked = MemoryRetrieval.rank(
        candidates: candidates,
        query: 'concise explanations',
        now: now,
      );

      expect(ranked.map((MemoryRecord item) => item.id), <String>['match']);
    });
  });

  group('MemoryStore persistence', () {
    test('persists across reloads and keeps profile files separate', () async {
      final _MemoryHarness harness = _MemoryHarness();
      addTearDown(harness.dispose);

      await harness.ayushStore.save(<MemoryRecord>[
        _record(profile: AuraProfile.ayush, content: 'Private preference'),
      ]);
      await harness.familyStore.save(<MemoryRecord>[
        _record(profile: AuraProfile.family, content: 'Shared preference'),
      ]);

      final MemoryStore reloadedAyush =
          MemoryStore(directory: harness.directory, profile: AuraProfile.ayush);
      final MemoryStore reloadedFamily = MemoryStore(
          directory: harness.directory, profile: AuraProfile.family);

      expect((await reloadedAyush.load()).single.content, 'Private preference');
      expect((await reloadedFamily.load()).single.content, 'Shared preference');
      expect(
        File('${harness.directory.path}${Platform.pathSeparator}'
                'memory_ayush.json')
            .existsSync(),
        isTrue,
      );
      expect(
        File('${harness.directory.path}${Platform.pathSeparator}'
                'memory_family.json')
            .existsSync(),
        isTrue,
      );
    });

    test('recovers valid records from a partly corrupt file', () async {
      final _MemoryHarness harness = _MemoryHarness();
      addTearDown(harness.dispose);

      final Map<String, dynamic> valid =
          _record(profile: AuraProfile.family, id: 'good').toJson();
      final Map<String, dynamic> future =
          _record(profile: AuraProfile.family, id: 'future').toJson()
            ..['schema'] = 99;
      final File file = File(
        '${harness.directory.path}${Platform.pathSeparator}memory_family.json',
      );
      await file.writeAsString(
        jsonEncode(<String, dynamic>{
          'schema': MemoryRecord.schemaVersion,
          'records': <dynamic>[
            <String, dynamic>{'bad': true},
            valid,
            future,
          ],
        }),
      );

      final List<MemoryRecord> restored = await harness.familyStore.load();
      expect(restored.map((MemoryRecord item) => item.id), <String>['good']);
    });

    test('a scoped store silently drops foreign-scope records', () async {
      final _MemoryHarness harness = _MemoryHarness();
      addTearDown(harness.dispose);

      final bool saved = await harness.familyStore.save(<MemoryRecord>[
        _record(profile: AuraProfile.ayush),
      ]);

      expect(saved, isTrue);
      expect(await harness.familyStore.load(), isEmpty);
    });
  });

  group('LocalMemoryRepository workflow', () {
    test('suggestions stay pending until approved or rejected', () async {
      final _MemoryHarness harness = _MemoryHarness();
      addTearDown(harness.dispose);
      harness.unlockAyush();

      expect(
        (await harness.ayush.createApproved(
          content: 'I prefer concise explanations with examples.',
          category: MemoryCategory.preference,
        ))
            .isSuccess,
        isTrue,
      );
      final MemoryWriteResult suggested = await harness.ayush.suggest(
        content: 'Consider a weekly review.',
        category: MemoryCategory.goal,
      );
      expect(suggested.isSuccess, isTrue);

      final List<MemoryRecord> records = await harness.ayush.load();
      expect(
          records.where(
              (MemoryRecord item) => item.status == MemoryStatus.approved),
          hasLength(1));
      expect(
          records.where(
              (MemoryRecord item) => item.status == MemoryStatus.pending),
          hasLength(1));

      await harness.ayush.saveSettings(
        const MemorySettings(retrievalEnabled: true),
      );
      expect(
        (await harness.ayush.retrieve(
          query: 'weekly review',
          now: DateTime(2026),
        )),
        isEmpty,
        reason: 'pending suggestions must never enter retrieval',
      );

      final String pendingId = records
          .firstWhere(
              (MemoryRecord item) => item.status == MemoryStatus.pending)
          .id;
      expect((await harness.ayush.approve(pendingId)).isSuccess, isTrue);
      expect(
        (await harness.ayush.retrieve(
          query: 'weekly review',
          now: DateTime(2026),
        )),
        hasLength(1),
      );

      final MemoryWriteResult rejected = await harness.ayush.suggest(
        content: 'A suggestion I will reject.',
        category: MemoryCategory.preference,
      );
      expect(rejected.isSuccess, isTrue);
      final String rejectId = (await harness.ayush.load())
          .firstWhere((MemoryRecord item) =>
              item.content == 'A suggestion I will reject.')
          .id;
      expect((await harness.ayush.reject(rejectId)).isSuccess, isTrue);
      expect(
        (await harness.ayush.retrieve(
          query: 'reject',
          now: DateTime(2026),
        )),
        isEmpty,
      );
    });

    test('edit and delete are explicit and durable', () async {
      final _MemoryHarness harness = _MemoryHarness();
      addTearDown(harness.dispose);
      harness.unlockAyush();

      final MemoryWriteResult created = await harness.ayush.createApproved(
        content: 'Old wording',
        category: MemoryCategory.preference,
      );
      expect(created.isSuccess, isTrue);
      final String id = (await harness.ayush.load()).single.id;

      expect(
        (await harness.ayush.update(
          id: id,
          content: 'New wording',
          category: MemoryCategory.preference,
          tags: const <String>['edited'],
        ))
            .isSuccess,
        isTrue,
      );
      expect((await harness.ayush.load()).single.content, 'New wording');

      expect((await harness.ayush.delete(id)).isSuccess, isTrue);
      final LocalMemoryRepository reloaded = LocalMemoryRepository(
        profile: AuraProfile.ayush,
        store: MemoryStore(
            directory: harness.directory, profile: AuraProfile.ayush),
        settingsStore: harness.ayushSettings,
        accessReader: () => ProfileAccess(harness.session),
      );
      expect(await reloaded.load(), isEmpty);
    });

    test('sensitive content is rejected before persistence', () async {
      final _MemoryHarness harness = _MemoryHarness();
      addTearDown(harness.dispose);
      harness.unlockAyush();

      const String secret = 'FAKE-SECRET-4821';
      final MemoryWriteResult result = await harness.ayush.createApproved(
        content: 'My API key is $secret',
        category: MemoryCategory.technicalContext,
      );

      expect(result.outcome, MemoryWriteOutcome.sensitiveContent);
      expect(result.userMessage, isNot(contains(secret)));
      expect(await harness.ayush.load(), isEmpty);
      final File file = File(
        '${harness.directory.path}${Platform.pathSeparator}memory_ayush.json',
      );
      if (file.existsSync()) {
        expect(file.readAsStringSync(), isNot(contains(secret)));
      }
    });

    test('disabled suggestions and disabled retrieval fail closed', () async {
      final _MemoryHarness harness = _MemoryHarness();
      addTearDown(harness.dispose);
      harness.unlockAyush();

      await harness.ayush.saveSettings(
        const MemorySettings(retrievalEnabled: true, suggestionsEnabled: false),
      );
      expect(
        (await harness.ayush.suggest(
          content: 'A harmless preference.',
          category: MemoryCategory.preference,
        ))
            .outcome,
        MemoryWriteOutcome.disabled,
      );

      await harness.ayush.createApproved(
        content: 'A harmless preference.',
        category: MemoryCategory.preference,
      );
      expect(
        await harness.ayush.retrieve(query: 'harmless', now: DateTime(2026)),
        hasLength(1),
      );

      await harness.ayush.saveSettings(
        const MemorySettings(retrievalEnabled: false, suggestionsEnabled: true),
      );
      expect(
        await harness.ayush.retrieve(query: 'harmless', now: DateTime(2026)),
        isEmpty,
      );
      expect(await harness.ayush.load(), hasLength(1),
          reason: 'disabling retrieval must not delete stored memories');
    });

    test('AYUSH access requires an active private session', () async {
      final _MemoryHarness harness = _MemoryHarness();
      addTearDown(harness.dispose);

      expect((await harness.ayush.load()), isEmpty);
      final MemoryWriteResult denied = await harness.ayush.createApproved(
        content: 'Private note',
        category: MemoryCategory.personalFact,
      );
      expect(denied.outcome, MemoryWriteOutcome.accessDenied);
      expect(
          await harness.ayush.retrieve(
            query: 'private',
            now: DateTime(2026),
          ),
          isEmpty);

      harness.unlockAyush();
      expect(
        (await harness.ayush.createApproved(
          content: 'Private note',
          category: MemoryCategory.personalFact,
        ))
            .isSuccess,
        isTrue,
      );
    });

    test('FAMILY cannot read AYUSH memory and lock discards state', () async {
      final _MemoryHarness harness = _MemoryHarness();
      addTearDown(harness.dispose);
      harness.unlockAyush();

      await harness.ayush.createApproved(
        content: 'AYUSH-SECRET-PREFERENCE',
        category: MemoryCategory.personalFact,
      );
      await harness.family.createApproved(
        content: 'FAMILY-SHARED-PREFERENCE',
        category: MemoryCategory.familyInformation,
      );
      await harness.family.saveSettings(
        const MemorySettings(retrievalEnabled: true),
      );

      final List<MemoryRecord> familyMatches = await harness.family.retrieve(
        query: 'AYUSH-SECRET-PREFERENCE FAMILY-SHARED-PREFERENCE',
        now: DateTime(2026),
      );
      expect(
        familyMatches.map((MemoryRecord item) => item.content),
        <String>['FAMILY-SHARED-PREFERENCE'],
      );

      harness.lock();
      expect(await harness.ayush.load(), isEmpty);
      expect(
        await harness.ayush.retrieve(query: 'SECRET', now: DateTime(2026)),
        isEmpty,
      );
      harness.ayush.discardForLock();
      expect(await harness.ayush.load(), isEmpty);
    });
  });

  group('Memory Riverpod lifecycle', () {
    test('locking clears the active AYUSH controller and repository', () async {
      final Directory directory =
          Directory.systemTemp.createTempSync('aura_memory_provider_');
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          memoryStoreForProvider.overrideWith(
            (Ref ref, AuraProfile profile) =>
                MemoryStore(directory: directory, profile: profile),
          ),
          memorySettingsStoreForProvider.overrideWith(
            (Ref ref, AuraProfile profile) =>
                MemorySettingsStore(directory: directory, profile: profile),
          ),
        ],
      );
      addTearDown(() {
        container.dispose();
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      });

      container.read(profileSessionProvider.notifier).state = ProfileSession(
        profile: AuraProfile.ayush,
        startedAt: DateTime(2024),
        authenticated: true,
      );
      final MemoryController ayushController = container
          .read(memoryControllerForProvider(AuraProfile.ayush).notifier);
      final MemoryRepository ayushRepository =
          container.read(memoryRepositoryForProvider(AuraProfile.ayush));

      expect(
        await ayushController.createApproved(
          content: 'Private provider preference',
          category: MemoryCategory.preference,
        ),
        isTrue,
      );
      expect(
        container.read(memoryControllerForProvider(AuraProfile.ayush)).records,
        hasLength(1),
      );

      container.read(profileSessionProvider.notifier).lock();
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(memoryControllerForProvider(AuraProfile.ayush)).records,
        isEmpty,
      );
      expect(await ayushRepository.load(), isEmpty);
    });
  });

  group('MemoryPage workspace isolation', () {
    testWidgets('FAMILY workspace never displays AYUSH memory',
        (WidgetTester tester) async {
      final MemoryRepository familyRepository = _WidgetMemoryRepository(
        AuraProfile.family,
        <MemoryRecord>[
          _record(
            profile: AuraProfile.family,
            id: 'family-1',
            content: 'FAMILY-SHARED-PREFERENCE',
          ),
        ],
      );
      final MemoryRepository ayushRepository = _WidgetMemoryRepository(
        AuraProfile.ayush,
        <MemoryRecord>[
          _record(
            profile: AuraProfile.ayush,
            id: 'ayush-1',
            content: 'AYUSH-SECRET-PREFERENCE',
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            activeProfileProvider.overrideWithValue(AuraProfile.family),
            memoryRepositoryForProvider.overrideWith(
              (Ref ref, AuraProfile profile) => profile == AuraProfile.family
                  ? familyRepository
                  : ayushRepository,
            ),
          ],
          child: const MaterialApp(home: MemoryPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('FAMILY memory workspace'), findsOneWidget);
      expect(find.text('FAMILY-SHARED-PREFERENCE'), findsOneWidget);
      expect(find.text('AYUSH-SECRET-PREFERENCE'), findsNothing);
      expect(find.textContaining('AYUSH memory workspace'), findsNothing);
    });
  });
}
