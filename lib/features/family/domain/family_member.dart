import 'dart:math';

import 'package:aura_hub/features/family/domain/family_relationship.dart';

/// A non-birthday date saved for a family member (anniversary, wedding, etc.).
class FamilyImportantDate {
  const FamilyImportantDate({
    required this.id,
    required this.label,
    required this.date,
  });

  final String id;
  final String label;
  final DateTime date;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'label': label,
        'date': date.toIso8601String(),
      };

  static FamilyImportantDate? tryFromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final Object? id = value['id'];
    final Object? label = value['label'];
    final Object? rawDate = value['date'];
    if (id is! String || id.trim().isEmpty) return null;
    if (label is! String || label.trim().isEmpty) return null;
    final DateTime? date =
        rawDate is String ? DateTime.tryParse(rawDate) : null;
    if (date == null) return null;
    return FamilyImportantDate(
      id: id,
      label: label.trim(),
      date: DateTime(date.year, date.month, date.day),
    );
  }
}

/// One saved family member.
///
/// Only [fullName], [relationship] and the timestamps are required. Everything
/// else is optional and must stay optional in forms, imports and AI context.
/// The model contains no credentials and is safe to persist as non-secret JSON.
class FamilyMember {
  FamilyMember({
    required this.id,
    required this.fullName,
    required this.relationship,
    required this.createdAt,
    required this.updatedAt,
    this.relationshipLabel,
    this.nickname,
    this.addressName,
    this.auraAddressName,
    this.dateOfBirth,
    this.phone,
    this.email,
    this.address,
    this.photoPath,
    this.notes,
    this.emergencyContact = false,
    this.interests = const <String>[],
    this.importantDates = const <FamilyImportantDate>[],
    this.customFields = const <String, String>{},
  });

  final String id;
  final String fullName;
  final FamilyRelationship relationship;

  /// User-defined label such as "Maa", "Dadu" or "Kakima". Remains empty for
  /// members using the standard relationship label.
  final String? relationshipLabel;
  final String? nickname;

  /// How Ayush addresses the person.
  final String? addressName;

  /// How AURA should address the person.
  final String? auraAddressName;

  final DateTime? dateOfBirth;
  final String? phone;
  final String? email;
  final String? address;
  final String? photoPath;
  final String? notes;
  final bool emergencyContact;
  final List<String> interests;
  final List<FamilyImportantDate> importantDates;
  final Map<String, String> customFields;
  final DateTime createdAt;
  final DateTime updatedAt;

  static const int schemaVersion = 1;

  /// Stable, collision-resistant id without pulling in a UUID dependency.
  static String newId() {
    final DateTime now = DateTime.now();
    final int random = Random.secure().nextInt(1 << 30);
    return 'fm-${now.microsecondsSinceEpoch}-${random.toRadixString(36)}';
  }

  String get displayName {
    final String? preferred = nickname?.trim();
    return preferred != null && preferred.isNotEmpty ? preferred : fullName;
  }

  String get relationshipDisplayName {
    final String? label = relationshipLabel?.trim();
    return label != null && label.isNotEmpty ? label : relationship.label;
  }

  String get preferredAddress {
    final String? preferred = auraAddressName?.trim();
    if (preferred != null && preferred.isNotEmpty) return preferred;
    final String? own = addressName?.trim();
    if (own != null && own.isNotEmpty) return own;
    return relationshipDisplayName;
  }

  /// Blocks saving an unusable record without forcing optional fields.
  String? get validationError {
    if (fullName.trim().isEmpty) return 'Enter a full name.';
    if (relationship == FamilyRelationship.other &&
        (relationshipLabel?.trim().isEmpty ?? true)) {
      return 'Enter a custom relationship label.';
    }
    final String? mail = email?.trim();
    if (mail != null &&
        mail.isNotEmpty &&
        (!mail.contains('@') || !mail.contains('.'))) {
      return 'Enter a valid email address or leave it empty.';
    }
    return null;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schema': schemaVersion,
        'id': id,
        'fullName': fullName,
        'relationship': relationship.storageKey,
        if (relationshipLabel?.trim().isNotEmpty ?? false)
          'relationshipLabel': relationshipLabel!.trim(),
        if (nickname?.trim().isNotEmpty ?? false) 'nickname': nickname!.trim(),
        if (addressName?.trim().isNotEmpty ?? false)
          'addressName': addressName!.trim(),
        if (auraAddressName?.trim().isNotEmpty ?? false)
          'auraAddressName': auraAddressName!.trim(),
        if (dateOfBirth != null) 'dateOfBirth': dateOfBirth!.toIso8601String(),
        if (phone?.trim().isNotEmpty ?? false) 'phone': phone!.trim(),
        if (email?.trim().isNotEmpty ?? false) 'email': email!.trim(),
        if (address?.trim().isNotEmpty ?? false) 'address': address!.trim(),
        if (photoPath?.trim().isNotEmpty ?? false)
          'photoPath': photoPath!.trim(),
        if (notes?.trim().isNotEmpty ?? false) 'notes': notes!.trim(),
        if (emergencyContact) 'emergencyContact': true,
        if (interests.isNotEmpty)
          'interests': interests.toList(growable: false),
        if (importantDates.isNotEmpty)
          'importantDates': importantDates
              .map((FamilyImportantDate item) => item.toJson())
              .toList(),
        if (customFields.isNotEmpty)
          'customFields': Map<String, String>.from(customFields),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  /// Returns null for malformed records. Callers skip them instead of crashing
  /// the directory or displaying invented data.
  static FamilyMember? tryFromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final Object? id = value['id'];
    final Object? fullName = value['fullName'];
    final Object? relationshipValue = value['relationship'];
    final FamilyRelationship? relationship =
        FamilyRelationshipX.fromStorage(relationshipValue);
    if (id is! String || id.trim().isEmpty) return null;
    if (fullName is! String || fullName.trim().isEmpty) return null;
    if (relationship == null) return null;

    final DateTime createdAt = _date(value['createdAt']) ?? DateTime.now();
    final DateTime updatedAt = _date(value['updatedAt']) ?? createdAt;

    return FamilyMember(
      id: id,
      fullName: fullName.trim(),
      relationship: relationship,
      createdAt: createdAt,
      updatedAt: updatedAt,
      relationshipLabel: _text(value['relationshipLabel']),
      nickname: _text(value['nickname']),
      addressName: _text(value['addressName']),
      auraAddressName: _text(value['auraAddressName']),
      dateOfBirth: _date(value['dateOfBirth']),
      phone: _text(value['phone']),
      email: _text(value['email']),
      address: _text(value['address']),
      photoPath: _text(value['photoPath']),
      notes: _text(value['notes']),
      emergencyContact: value['emergencyContact'] == true,
      interests: _stringList(value['interests']),
      importantDates: _importantDates(value['importantDates']),
      customFields: _stringMap(value['customFields']),
    );
  }

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  static String? _text(Object? value) {
    if (value is! String) return null;
    final String clean = value.trim();
    return clean.isEmpty ? null : clean;
  }

  static List<String> _stringList(Object? value) {
    if (value is! List<dynamic>) return const <String>[];
    final List<String> result = <String>[];
    for (final Object? item in value) {
      final String? text = _text(item);
      if (text != null && !result.contains(text)) result.add(text);
    }
    return List<String>.unmodifiable(result);
  }

  static List<FamilyImportantDate> _importantDates(Object? value) {
    if (value is! List<dynamic>) return const <FamilyImportantDate>[];
    final List<FamilyImportantDate> result = <FamilyImportantDate>[];
    final Set<String> seen = <String>{};
    for (final Object? item in value) {
      final FamilyImportantDate? date = FamilyImportantDate.tryFromJson(item);
      if (date != null && seen.add(date.id)) result.add(date);
    }
    return List<FamilyImportantDate>.unmodifiable(result);
  }

  static Map<String, String> _stringMap(Object? value) {
    if (value is! Map<String, dynamic>) return const <String, String>{};
    final Map<String, String> result = <String, String>{};
    for (final MapEntry<String, dynamic> entry in value.entries) {
      final String? text = _text(entry.value);
      if (text != null) result[entry.key] = text;
    }
    return Map<String, String>.unmodifiable(result);
  }

  /// Conservative duplicate check: the same name alone is not enough, because
  /// families can legitimately share names. One matching stable identifier is
  /// required in addition to the name.
  bool looksLikeDuplicate(FamilyMember other) {
    if (_normaliseName(fullName) != _normaliseName(other.fullName)) {
      return false;
    }
    if (dateOfBirth != null && other.dateOfBirth != null) {
      return _sameDate(dateOfBirth, other.dateOfBirth);
    }
    if (_digits(phone) != null &&
        _digits(other.phone) != null &&
        _digits(phone) == _digits(other.phone)) {
      return true;
    }
    if (_normalise(email) != null &&
        _normalise(other.email) != null &&
        _normalise(email) == _normalise(other.email)) {
      return true;
    }
    return _normalise(nickname) != null &&
        _normalise(nickname) == _normalise(other.nickname);
  }

  static String? _normalise(String? value) {
    final String? text = _text(value);
    return text?.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  static String _normaliseName(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  static String? _digits(String? value) {
    final String? text = _text(value);
    if (text == null) return null;
    final String digits = text.replaceAll(RegExp(r'\D'), '');
    return digits.isEmpty ? null : digits;
  }

  static bool _sameDate(DateTime? a, DateTime? b) =>
      a != null &&
      b != null &&
      a.year == b.year &&
      a.month == b.month &&
      a.day == b.day;

  FamilyMember copyWith({
    String? fullName,
    FamilyRelationship? relationship,
    String? relationshipLabel,
    bool clearRelationshipLabel = false,
    String? nickname,
    bool clearNickname = false,
    String? addressName,
    bool clearAddressName = false,
    String? auraAddressName,
    bool clearAuraAddressName = false,
    DateTime? dateOfBirth,
    bool clearDateOfBirth = false,
    String? phone,
    bool clearPhone = false,
    String? email,
    bool clearEmail = false,
    String? address,
    bool clearAddress = false,
    String? photoPath,
    bool clearPhotoPath = false,
    String? notes,
    bool clearNotes = false,
    bool? emergencyContact,
    List<String>? interests,
    List<FamilyImportantDate>? importantDates,
    Map<String, String>? customFields,
  }) {
    return FamilyMember(
      id: id,
      fullName: fullName ?? this.fullName,
      relationship: relationship ?? this.relationship,
      createdAt: createdAt,
      updatedAt: updatedAt,
      relationshipLabel: clearRelationshipLabel
          ? null
          : relationshipLabel ?? this.relationshipLabel,
      nickname: clearNickname ? null : nickname ?? this.nickname,
      addressName: clearAddressName ? null : addressName ?? this.addressName,
      auraAddressName:
          clearAuraAddressName ? null : auraAddressName ?? this.auraAddressName,
      dateOfBirth: clearDateOfBirth ? null : dateOfBirth ?? this.dateOfBirth,
      phone: clearPhone ? null : phone ?? this.phone,
      email: clearEmail ? null : email ?? this.email,
      address: clearAddress ? null : address ?? this.address,
      photoPath: clearPhotoPath ? null : photoPath ?? this.photoPath,
      notes: clearNotes ? null : notes ?? this.notes,
      emergencyContact: emergencyContact ?? this.emergencyContact,
      interests: interests ?? this.interests,
      importantDates: importantDates ?? this.importantDates,
      customFields: customFields ?? this.customFields,
    );
  }

  @override
  String toString() => 'FamilyMember($id, $displayName)';
}
