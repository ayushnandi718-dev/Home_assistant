import 'dart:convert';
import 'package:aura_hub/core/platform/io_compat.dart';

import 'package:aura_hub/core/utilities/local_paths.dart';
import 'package:aura_hub/features/family/domain/family_member.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';

/// Versioned local JSON store for family records.
///
/// The default workspace is FAMILY: household directory data is never written
/// into the PIN-protected AYUSH scope by the application. The profile parameter
/// exists so tests can prove the two storage scopes stay isolated.
class FamilyDirectoryStore {
  FamilyDirectoryStore({
    Directory? directory,
    required AuraProfile profile,
  }) : _file = File(
          '${(directory ?? LocalPaths.appData()).path}${Platform.pathSeparator}'
          'family_directory_${profile.storageScope}.json',
        );

  final File _file;

  Future<List<FamilyMember>> load() async {
    try {
      if (!await _file.exists()) return const <FamilyMember>[];
      final Object? decoded = jsonDecode(await _file.readAsString());

      // v1 envelope. A bare list is accepted as a migration fallback for
      // hand-written imports or future format changes.
      final Object? rawMembers = decoded is Map<String, dynamic>
          ? decoded['members']
          : decoded is List<dynamic>
              ? decoded
              : null;
      if (rawMembers is! List<dynamic>) return const <FamilyMember>[];

      final List<FamilyMember> result = <FamilyMember>[];
      final Set<String> seenIds = <String>{};
      for (final Object? item in rawMembers) {
        final FamilyMember? member = FamilyMember.tryFromJson(item);
        if (member == null || !seenIds.add(member.id)) continue;
        result.add(member);
      }
      return List<FamilyMember>.unmodifiable(result);
    } catch (_) {
      return const <FamilyMember>[];
    }
  }

  Future<void> save(List<FamilyMember> members) async {
    try {
      await _file.parent.create(recursive: true);
      final Set<String> seenIds = <String>{};
      final List<Map<String, dynamic>> records = <Map<String, dynamic>>[];
      for (final FamilyMember member in members) {
        if (member.validationError != null || !seenIds.add(member.id)) continue;
        records.add(member.toJson());
      }
      await _file.writeAsString(
        jsonEncode(<String, dynamic>{
          'schema': FamilyMember.schemaVersion,
          'members': records,
        }),
        flush: true,
      );
    } catch (_) {
      // Keep the directory usable; a later mutation retries the write.
    }
  }
}
