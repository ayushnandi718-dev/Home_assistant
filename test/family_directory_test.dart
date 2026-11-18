import 'dart:convert';
import 'dart:io';

import 'package:aura_hub/features/family/data/family_directory_repository.dart';
import 'package:aura_hub/features/family/data/family_directory_store.dart';
import 'package:aura_hub/features/family/domain/family_birthday.dart';
import 'package:aura_hub/features/family/domain/family_directory_service.dart';
import 'package:aura_hub/features/family/domain/family_member.dart';
import 'package:aura_hub/features/family/domain/family_relationship.dart';
import 'package:aura_hub/features/family/presentation/family_directory_page.dart';
import 'package:aura_hub/features/family/presentation/family_member_card.dart';
import 'package:aura_hub/features/family/presentation/family_providers.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

FamilyMember _member(
  String fullName, {
  String id = 'id-1',
  FamilyRelationship relationship = FamilyRelationship.mother,
  String? nickname,
  DateTime? dateOfBirth,
  String? phone,
  String? email,
  String? notes,
  DateTime? createdAt,
  DateTime? updatedAt,
  bool emergencyContact = false,
  List<String> interests = const <String>[],
}) {
  final DateTime now = DateTime(2024, 1, 1);
  return FamilyMember(
    id: id,
    fullName: fullName,
    relationship: relationship,
    nickname: nickname,
    dateOfBirth: dateOfBirth,
    phone: phone,
    email: email,
    notes: notes,
    emergencyContact: emergencyContact,
    interests: interests,
    createdAt: createdAt ?? now,
    updatedAt: updatedAt ?? now,
  );
}

class MemoryFamilyRepository implements FamilyDirectoryRepository {
  final List<FamilyMember> _members = <FamilyMember>[];

  @override
  Future<List<FamilyMember>> load() async =>
      List<FamilyMember>.unmodifiable(_members);

  @override
  Future<List<FamilyMember>> upsert(FamilyMember member) async {
    _members.removeWhere((FamilyMember item) => item.id == member.id);
    _members.insert(0, member);
    return load();
  }

  @override
  Future<List<FamilyMember>> remove(String id) async {
    _members.removeWhere((FamilyMember item) => item.id == id);
    return load();
  }

  @override
  Future<List<FamilyMember>> replaceAll(List<FamilyMember> members) async {
    _members
      ..clear()
      ..addAll(members);
    return load();
  }
}

void main() {
  group('FamilyMember domain', () {
    test('only the required fields are required', () {
      final FamilyMember member = _member('Anjali Devi');

      expect(member.validationError, isNull);
      expect(member.dateOfBirth, isNull);
      expect(member.phone, isNull);
      expect(member.email, isNull);
      expect(member.photoPath, isNull);
      expect(member.notes, isNull);

      final Map<String, dynamic> json = member.toJson();
      expect(json.containsKey('dateOfBirth'), isFalse);
      expect(json.containsKey('phone'), isFalse);
      expect(json.containsKey('email'), isFalse);
      expect(json.containsKey('photoPath'), isFalse);
      expect(json.containsKey('notes'), isFalse);

      final FamilyMember? restored = FamilyMember.tryFromJson(json);
      expect(restored, isNotNull);
      expect(restored!.fullName, 'Anjali Devi');
      expect(restored.relationship, FamilyRelationship.mother);
    });

    test('rejects unusable records instead of inventing data', () {
      expect(_member('  ').validationError, 'Enter a full name.');
      expect(
        FamilyMember(
          id: 'x',
          fullName: 'Someone',
          relationship: FamilyRelationship.other,
          createdAt: DateTime(2024),
          updatedAt: DateTime(2024),
        ).validationError,
        'Enter a custom relationship label.',
      );
      expect(
        _member('Someone', email: 'not-an-email').validationError,
        contains('valid email'),
      );
      expect(
          FamilyMember.tryFromJson(<String, dynamic>{'fullName': 'X'}), isNull);
    });

    test('duplicate detection needs a name plus one stable identifier', () {
      final FamilyMember original = _member(
        'Anjali Devi',
        dateOfBirth: DateTime(1980, 5, 4),
      );

      expect(
        original.looksLikeDuplicate(
          _member(
            ' anjali   devi ',
            id: 'different',
            dateOfBirth: DateTime(1980, 5, 4),
          ),
        ),
        isTrue,
      );
      expect(original.looksLikeDuplicate(_member('Anjali Devi', id: 'x')),
          isFalse);
      expect(
        _member('Anjali Devi', id: 'x')
            .looksLikeDuplicate(_member('Anjali Devi', id: 'y')),
        isFalse,
      );
      expect(
        _member('Anjali Devi', phone: '+91 98765 43210').looksLikeDuplicate(
            _member('Anjali Devi', phone: '+91-98765-43210')),
        isTrue,
      );
    });
  });

  group('Birthday logic', () {
    test('February 29 is celebrated on February 28 in non-leap years', () {
      final DateTime born = DateTime(2000, 2, 29);
      final DateTime now = DateTime(2023, 2, 28);
      final DateTime next =
          FamilyBirthdayService.nextOccurrence(born, now: now)!;

      expect(next, DateTime(2023, 2, 28));
      expect(FamilyBirthdayService.daysBetween(now, next), 0);
      expect(FamilyBirthdayService.ageOn(born, next), 23);
      expect(
        FamilyBirthdayService.nextOccurrence(born, now: DateTime(2024, 2, 28)),
        DateTime(2024, 2, 29),
      );

      final FamilyMember member =
          _member('Leap Person', dateOfBirth: born, nickname: 'Leapy');
      final FamilyBirthday birthday =
          FamilyBirthdayService.upcoming(<FamilyMember>[member], now: now)
              .single;
      expect(birthday.isToday, isTrue);
      expect(birthday.description, contains('Today'));
      expect(member.dateOfBirth, born);
    });

    test('upcoming birthdays are sorted and omit missing dates', () {
      final DateTime now = DateTime(2024, 1, 1);
      final List<FamilyBirthday> birthdays = FamilyBirthdayService.upcoming(
        <FamilyMember>[
          _member('Zoya', id: 'z', dateOfBirth: DateTime(1990, 12, 20)),
          _member('Aman', id: 'a', dateOfBirth: DateTime(1992, 1, 10)),
          _member('No Date', id: 'n'),
        ],
        now: now,
      );

      expect(birthdays.map((FamilyBirthday item) => item.member.fullName),
          <String>['Aman', 'Zoya']);
      expect(birthdays.first.daysAway, 9);
    });
  });

  group('Directory service', () {
    late FamilyMember aman;
    late FamilyMember zoya;
    late FamilyMember raghu;

    setUp(() {
      aman = _member(
        'Aman Kumar',
        id: 'a',
        nickname: 'Amu',
        relationship: FamilyRelationship.brother,
        dateOfBirth: DateTime(1992, 1, 10),
        updatedAt: DateTime(2024, 3, 1),
      );
      zoya = _member(
        'Zoya Khan',
        id: 'z',
        relationship: FamilyRelationship.cousin,
        dateOfBirth: DateTime(1990, 12, 20),
        updatedAt: DateTime(2024, 2, 1),
      );
      raghu = _member(
        'Raghu Nair',
        id: 'r',
        nickname: 'Ragu',
        relationship: FamilyRelationship.uncle,
        updatedAt: DateTime(2024, 5, 1),
      );
    });

    test('search, relationship filter and sort are independent', () {
      final List<FamilyMember> all = <FamilyMember>[zoya, aman, raghu];

      expect(
        FamilyDirectoryService.query(all, search: 'amu')
            .map((FamilyMember item) => item.id),
        <String>['a'],
      );
      expect(
        FamilyDirectoryService.query(all, search: 'cousin')
            .map((FamilyMember item) => item.id),
        <String>['z'],
      );
      expect(
        FamilyDirectoryService.query(
          all,
          relationship: FamilyRelationship.brother,
        ).map((FamilyMember item) => item.id),
        <String>['a'],
      );
      expect(
        FamilyDirectoryService.query(
          all,
          sort: FamilySortMode.recentlyUpdated,
        ).map((FamilyMember item) => item.id),
        <String>['r', 'a', 'z'],
      );
      expect(
        FamilyDirectoryService.query(
          all,
          sort: FamilySortMode.upcomingBirthday,
          now: DateTime(2024, 1, 1),
        ).map((FamilyMember item) => item.id),
        <String>['a', 'z', 'r'],
      );
    });

    test('JSON and CSV exports round-trip without losing optional data', () {
      final FamilyMember quoted = _member(
        'Doe, Jane "JD"',
        notes: 'Call after 5, avoid weekends',
        interests: <String>['music', 'chess'],
      );

      final List<FamilyMember> fromJson = FamilyDirectoryService.parseImport(
        FamilyDirectoryService.exportJson(<FamilyMember>[quoted]),
      );
      expect(fromJson.single.fullName, quoted.fullName);
      expect(fromJson.single.notes, quoted.notes);
      expect(fromJson.single.interests, quoted.interests);

      final List<FamilyMember> fromCsv = FamilyDirectoryService.parseImport(
        FamilyDirectoryService.exportCsv(<FamilyMember>[quoted]),
      );
      expect(fromCsv.single.fullName, quoted.fullName);
      expect(fromCsv.single.notes, quoted.notes);
      expect(fromCsv.single.interests, quoted.interests);
    });

    test('imports skip duplicates unless overwrite is requested', () {
      final FamilyMember duplicate = _member(
        'Aman Kumar',
        id: 'imported',
        nickname: 'Amanji',
        dateOfBirth: DateTime(1992, 1, 10),
      );
      final FamilyImportResult skipped =
          FamilyDirectoryService.importMembers(<FamilyMember>[
        aman
      ], <FamilyMember>[
        duplicate,
        raghu,
      ]);

      expect(skipped.added, 1);
      expect(skipped.skipped, 1);
      expect(skipped.members.first.id, 'a');
      expect(skipped.members.first.nickname, 'Amu');

      final FamilyImportResult overwritten =
          FamilyDirectoryService.importMembers(
        <FamilyMember>[aman],
        <FamilyMember>[duplicate],
        overwriteDuplicates: true,
      );
      expect(overwritten.updated, 1);
      expect(overwritten.members.single.id, 'a');
      expect(overwritten.members.single.nickname, 'Amanji');
    });
  });

  group('Family directory persistence', () {
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('aura_family_test_');
    });

    tearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    test('writes versioned JSON and reads it back through the repository',
        () async {
      final FamilyDirectoryStore store = FamilyDirectoryStore(
        directory: directory,
        profile: AuraProfile.family,
      );
      final LocalFamilyDirectoryRepository repository =
          LocalFamilyDirectoryRepository(store: store);
      final FamilyMember member = _member(
        'Meera Iyer',
        id: 'm1',
        relationship: FamilyRelationship.aunt,
        phone: '9876543210',
        emergencyContact: true,
      );

      await repository.upsert(member);
      final File file = File(
        '${directory.path}${Platform.pathSeparator}'
        'family_directory_family.json',
      );
      final Map<String, dynamic> saved =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(saved['schema'], 1);
      expect(saved['members'] as List<dynamic>, hasLength(1));

      final LocalFamilyDirectoryRepository reloaded =
          LocalFamilyDirectoryRepository(store: store);
      final List<FamilyMember> loaded = await reloaded.load();
      expect(loaded.single.fullName, 'Meera Iyer');
      expect(loaded.single.phone, '9876543210');
      expect(loaded.single.emergencyContact, isTrue);

      await reloaded.remove('m1');
      expect(await reloaded.load(), isEmpty);
      expect((await repository.load()), isEmpty);
    });

    test('tolerates corrupt files and accepts a bare-list migration fallback',
        () async {
      final FamilyDirectoryStore store = FamilyDirectoryStore(
        directory: directory,
        profile: AuraProfile.family,
      );
      final File file = File(
        '${directory.path}${Platform.pathSeparator}'
        'family_directory_family.json',
      );

      await file.writeAsString('{not json');
      expect(await store.load(), isEmpty);

      await file.writeAsString(jsonEncode(<Object?>[
        _member('Legacy Member', id: 'legacy').toJson(),
        <String, dynamic>{'fullName': 'malformed'},
      ]));
      final List<FamilyMember> loaded = await store.load();
      expect(loaded, hasLength(1));
      expect(loaded.single.fullName, 'Legacy Member');
    });

    test('AYUSH and FAMILY scopes stay isolated', () async {
      final FamilyDirectoryStore familyStore = FamilyDirectoryStore(
        directory: directory,
        profile: AuraProfile.family,
      );
      final FamilyDirectoryStore ayushStore = FamilyDirectoryStore(
        directory: directory,
        profile: AuraProfile.ayush,
      );

      await familyStore.save(<FamilyMember>[_member('Family Only', id: 'f')]);
      await ayushStore.save(<FamilyMember>[_member('Private Only', id: 'p')]);

      expect((await familyStore.load()).map((FamilyMember item) => item.id),
          <String>['f']);
      expect((await ayushStore.load()).map((FamilyMember item) => item.id),
          <String>['p']);
      expect(
        File('${directory.path}${Platform.pathSeparator}'
                'family_directory_ayush.json')
            .existsSync(),
        isTrue,
      );
    });
  });

  group('FamilyDirectoryController', () {
    test('adds, updates, removes and imports records', () async {
      final MemoryFamilyRepository repository = MemoryFamilyRepository();
      final FamilyDirectoryController controller =
          FamilyDirectoryController(repository);
      await controller.load();

      await controller.add(_member('Arjun', id: 'a'));
      expect(controller.state, hasLength(1));

      await controller.update(
        controller.state.single.copyWith(nickname: 'Arju'),
      );
      expect(controller.state.single.nickname, 'Arju');

      final FamilyImportResult result = await controller.importMembers(
        incoming: <FamilyMember>[_member('Kavya', id: 'k')],
      );
      expect(result.added, 1);
      expect(controller.state, hasLength(2));

      await controller.remove('a');
      expect(
          controller.state.map((FamilyMember item) => item.id), <String>['k']);
      expect(await repository.load(), hasLength(1));
    });
  });

  group('FamilyDirectoryPage', () {
    testWidgets('hides family records in the AYUSH workspace',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            activeProfileProvider.overrideWithValue(AuraProfile.ayush),
          ],
          child: const MaterialApp(home: FamilyDirectoryPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Family workspace required'), findsOneWidget);
      expect(find.text('Family Directory'), findsNothing);
      expect(find.text('Add member'), findsNothing);
    });

    testWidgets('shows directory data and applies search in FAMILY workspace',
        (WidgetTester tester) async {
      final MemoryFamilyRepository repository = MemoryFamilyRepository();
      await repository.replaceAll(<FamilyMember>[
        _member('Arjun Mehta', id: 'a', nickname: 'Arju'),
        _member('Kavya Mehta', id: 'k'),
      ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            activeProfileProvider.overrideWithValue(AuraProfile.family),
            familyDirectoryRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(home: FamilyDirectoryPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Family Directory'), findsOneWidget);
      expect(find.text('Shared by design'), findsOneWidget);
      expect(find.byType(FamilyMemberCard), findsNWidgets(2));

      final Finder search = find.byWidgetPredicate(
        (Widget widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Search name or relationship',
      );
      await tester.enterText(search, 'Arju');
      await tester.pumpAndSettle();

      expect(find.byType(FamilyMemberCard), findsOneWidget);
      expect(find.text('Arju'), findsWidgets);
    });
  });
}
