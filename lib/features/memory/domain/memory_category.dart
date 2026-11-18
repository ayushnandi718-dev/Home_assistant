/// User-facing categories for approved AURA memories.
///
/// Categories are metadata for ranking and filtering. They never grant extra
/// permissions: a memory is usable only when its profile scope and approval
/// status also pass the repository and context-engine checks.
enum MemoryCategory {
  personalFact,
  preference,
  goal,
  technicalContext,
  familyInformation,
  importantDate,
}

extension MemoryCategoryX on MemoryCategory {
  String get storageKey => name;

  String get label => switch (this) {
        MemoryCategory.personalFact => 'Personal fact',
        MemoryCategory.preference => 'Preference',
        MemoryCategory.goal => 'Goal',
        MemoryCategory.technicalContext => 'Technical context',
        MemoryCategory.familyInformation => 'Family information',
        MemoryCategory.importantDate => 'Important date',
      };

  static MemoryCategory? fromStorage(Object? value) {
    if (value is! String) return null;
    for (final MemoryCategory category in MemoryCategory.values) {
      if (category.storageKey == value) return category;
    }
    return null;
  }
}
