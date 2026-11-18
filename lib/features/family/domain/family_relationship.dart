/// Stable relationship categories used by the Family Directory.
///
/// The enum is deliberately extensible through [FamilyRelationship.other] plus
/// a user-supplied `relationshipLabel` on the member. AURA must never infer a
/// relationship that was not saved by the user.
enum FamilyRelationship {
  mother,
  father,
  brother,
  sister,
  grandfather,
  grandmother,
  uncle,
  aunt,
  cousin,
  spouse,
  child,
  other,
}

extension FamilyRelationshipX on FamilyRelationship {
  String get label {
    switch (this) {
      case FamilyRelationship.mother:
        return 'Mother';
      case FamilyRelationship.father:
        return 'Father';
      case FamilyRelationship.brother:
        return 'Brother';
      case FamilyRelationship.sister:
        return 'Sister';
      case FamilyRelationship.grandfather:
        return 'Grandfather';
      case FamilyRelationship.grandmother:
        return 'Grandmother';
      case FamilyRelationship.uncle:
        return 'Uncle';
      case FamilyRelationship.aunt:
        return 'Aunt';
      case FamilyRelationship.cousin:
        return 'Cousin';
      case FamilyRelationship.spouse:
        return 'Spouse';
      case FamilyRelationship.child:
        return 'Child';
      case FamilyRelationship.other:
        return 'Other';
    }
  }

  String get storageKey => name;

  static FamilyRelationship? fromStorage(Object? value) {
    if (value is! String) return null;
    for (final FamilyRelationship relationship in FamilyRelationship.values) {
      if (relationship.storageKey == value.toLowerCase().trim()) {
        return relationship;
      }
    }
    // Accept saved display labels so older or hand-written imports remain
    // readable without inventing a relationship.
    for (final FamilyRelationship relationship in FamilyRelationship.values) {
      if (relationship.label.toLowerCase() == value.toLowerCase().trim()) {
        return relationship;
      }
    }
    return null;
  }
}
