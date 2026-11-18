import 'dart:convert';

import 'package:aura_hub/features/family/domain/family_birthday.dart';
import 'package:aura_hub/features/family/domain/family_member.dart';
import 'package:aura_hub/features/family/domain/family_relationship.dart';

enum FamilySortMode { alphabetical, upcomingBirthday, recentlyUpdated }

class FamilyImportResult {
  const FamilyImportResult({
    required this.members,
    required this.added,
    required this.updated,
    required this.skipped,
  });

  final List<FamilyMember> members;
  final int added;
  final int updated;
  final int skipped;
}

/// Pure directory operations. No file I/O, no network, no personal data logs.
abstract final class FamilyDirectoryService {
  static List<FamilyMember> query(
    List<FamilyMember> members, {
    String search = '',
    FamilyRelationship? relationship,
    FamilySortMode sort = FamilySortMode.alphabetical,
    DateTime? now,
  }) {
    final String needle = search.trim().toLowerCase();
    final List<FamilyMember> result = members.where((FamilyMember member) {
      if (relationship != null && member.relationship != relationship) {
        return false;
      }
      if (needle.isEmpty) return true;
      return <String>[
        member.fullName,
        member.nickname ?? '',
        member.relationshipDisplayName,
      ].any((String value) => value.toLowerCase().contains(needle));
    }).toList();

    switch (sort) {
      case FamilySortMode.alphabetical:
        result.sort((FamilyMember a, FamilyMember b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      case FamilySortMode.upcomingBirthday:
        final DateTime reference = now ?? DateTime.now();
        result.sort((FamilyMember a, FamilyMember b) {
          final DateTime? aBirth = a.dateOfBirth;
          final DateTime? bBirth = b.dateOfBirth;
          if (aBirth == null && bBirth == null) return 0;
          if (aBirth == null) return 1;
          if (bBirth == null) return -1;
          final DateTime aNext =
              FamilyBirthdayService.nextOccurrence(aBirth, now: reference) ??
                  DateTime(9999);
          final DateTime bNext =
              FamilyBirthdayService.nextOccurrence(bBirth, now: reference) ??
                  DateTime(9999);
          final int byDate = aNext.compareTo(bNext);
          if (byDate != 0) return byDate;
          return a.displayName.compareTo(b.displayName);
        });
      case FamilySortMode.recentlyUpdated:
        result.sort((FamilyMember a, FamilyMember b) =>
            b.updatedAt.compareTo(a.updatedAt));
    }
    return List<FamilyMember>.unmodifiable(result);
  }

  /// Imports without silent overwrites by default.
  static FamilyImportResult importMembers(
    List<FamilyMember> existing,
    List<FamilyMember> incoming, {
    bool overwriteDuplicates = false,
  }) {
    final List<FamilyMember> next = List<FamilyMember>.from(existing);
    int added = 0;
    int updated = 0;
    int skipped = 0;

    for (final FamilyMember candidate in incoming) {
      if (candidate.validationError != null) {
        skipped++;
        continue;
      }
      final int idIndex =
          next.indexWhere((FamilyMember item) => item.id == candidate.id);
      if (idIndex >= 0) {
        if (overwriteDuplicates) {
          next[idIndex] = candidate;
          updated++;
        } else {
          skipped++;
        }
        continue;
      }
      final int duplicateIndex = next.indexWhere(
        (FamilyMember item) => item.looksLikeDuplicate(candidate),
      );
      if (duplicateIndex >= 0) {
        if (overwriteDuplicates) {
          next[duplicateIndex] = _keepIdentity(
            candidate: candidate,
            existing: next[duplicateIndex],
          );
          updated++;
        } else {
          skipped++;
        }
        continue;
      }
      next.add(candidate);
      added++;
    }

    return FamilyImportResult(
      members: List<FamilyMember>.unmodifiable(next),
      added: added,
      updated: updated,
      skipped: skipped,
    );
  }

  static FamilyMember _keepIdentity({
    required FamilyMember candidate,
    required FamilyMember existing,
  }) {
    return FamilyMember(
      id: existing.id,
      fullName: candidate.fullName,
      relationship: candidate.relationship,
      createdAt: existing.createdAt,
      updatedAt: DateTime.now(),
      relationshipLabel: candidate.relationshipLabel,
      nickname: candidate.nickname,
      addressName: candidate.addressName,
      auraAddressName: candidate.auraAddressName,
      dateOfBirth: candidate.dateOfBirth,
      phone: candidate.phone,
      email: candidate.email,
      address: candidate.address,
      photoPath: candidate.photoPath,
      notes: candidate.notes,
      emergencyContact: candidate.emergencyContact,
      interests: candidate.interests,
      importantDates: candidate.importantDates,
      customFields: candidate.customFields,
    );
  }

  static String exportJson(List<FamilyMember> members) {
    return const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
      'schema': FamilyMember.schemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'members': members.map((FamilyMember member) => member.toJson()).toList(),
    });
  }

  static const List<String> csvColumns = <String>[
    'fullName',
    'nickname',
    'relationship',
    'relationshipLabel',
    'addressName',
    'auraAddressName',
    'dateOfBirth',
    'phone',
    'email',
    'address',
    'notes',
    'emergencyContact',
    'interests',
  ];

  static String exportCsv(List<FamilyMember> members) {
    final StringBuffer buffer = StringBuffer(csvColumns.join(','));
    buffer.writeln();
    for (final FamilyMember member in members) {
      buffer.writeln(<String>[
        member.fullName,
        member.nickname ?? '',
        member.relationship.storageKey,
        member.relationshipLabel ?? '',
        member.addressName ?? '',
        member.auraAddressName ?? '',
        member.dateOfBirth?.toIso8601String() ?? '',
        member.phone ?? '',
        member.email ?? '',
        member.address ?? '',
        member.notes ?? '',
        member.emergencyContact ? 'true' : 'false',
        member.interests.join('; '),
      ].map(_csvCell).join(','));
    }
    return buffer.toString();
  }

  static List<FamilyMember> parseImport(String text) {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) throw const FormatException('Nothing to import.');
    if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
      final Object? decoded = jsonDecode(trimmed);
      final Object? rawMembers = decoded is Map<String, dynamic>
          ? decoded['members']
          : decoded is List<dynamic>
              ? decoded
              : null;
      if (rawMembers is! List<dynamic>) {
        throw const FormatException('No member list in import.');
      }
      final List<FamilyMember> result = <FamilyMember>[];
      for (final Object? item in rawMembers) {
        final FamilyMember? member = FamilyMember.tryFromJson(item);
        if (member != null) result.add(member);
      }
      return result;
    }
    return _parseCsv(trimmed);
  }

  static List<FamilyMember> _parseCsv(String text) {
    final List<String> lines = text
        .split(RegExp(r'\r?\n'))
        .where((String line) => line.trim().isNotEmpty)
        .toList();
    if (lines.length < 2) {
      throw const FormatException('CSV needs a header and at least one row.');
    }
    final List<String> headers = _splitCsvLine(lines.first)
        .map((String value) => value.trim().toLowerCase())
        .toList();
    final List<FamilyMember> result = <FamilyMember>[];
    for (final String line in lines.skip(1)) {
      final List<String> cells = _splitCsvLine(line);
      final Map<String, String> row = <String, String>{};
      for (int index = 0;
          index < headers.length && index < cells.length;
          index++) {
        row[headers[index]] = cells[index].trim();
      }
      final String fullName = row['fullname'] ?? '';
      if (fullName.isEmpty) continue;
      final String relationshipText = row['relationship'] ?? '';
      final FamilyRelationship relationship =
          FamilyRelationshipX.fromStorage(relationshipText) ??
              FamilyRelationship.other;
      final String customLabel = row['relationshiplabel'] ?? relationshipText;
      final DateTime? birthDate = DateTime.tryParse(row['dateofbirth'] ?? '') ??
          DateTime.tryParse(row['dateOfBirth'] ?? '');
      final DateTime now = DateTime.now();
      result.add(
        FamilyMember(
          id: FamilyMember.newId(),
          fullName: fullName,
          relationship: relationship,
          relationshipLabel:
              relationship == FamilyRelationship.other ? customLabel : null,
          nickname: _emptyToNull(row['nickname']),
          addressName: _emptyToNull(row['addressname']),
          auraAddressName: _emptyToNull(row['auraaddressname']),
          dateOfBirth: birthDate,
          phone: _emptyToNull(row['phone']),
          email: _emptyToNull(row['email']),
          address: _emptyToNull(row['address']),
          notes: _emptyToNull(row['notes']),
          emergencyContact: row['emergencycontact'] == 'true',
          interests: (row['interests'] ?? '')
              .split(';')
              .map((String item) => item.trim())
              .where((String item) => item.isNotEmpty)
              .toList(growable: false),
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    return result;
  }

  static String? _emptyToNull(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  static String _csvCell(String value) {
    final bool needsQuotes =
        value.contains(',') || value.contains('"') || value.contains('\n');
    final String escaped = value.replaceAll('"', '""');
    return needsQuotes ? '"$escaped"' : escaped;
  }

  static List<String> _splitCsvLine(String line) {
    final List<String> cells = <String>[];
    final StringBuffer current = StringBuffer();
    bool quoted = false;
    for (int index = 0; index < line.length; index++) {
      final String character = line[index];
      if (character == '"') {
        if (quoted && index + 1 < line.length && line[index + 1] == '"') {
          current.write('"');
          index++;
        } else {
          quoted = !quoted;
        }
      } else if (character == ',' && !quoted) {
        cells.add(current.toString());
        current.clear();
      } else {
        current.write(character);
      }
    }
    cells.add(current.toString());
    return cells;
  }
}
