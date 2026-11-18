/// Approval lifecycle for a memory record.
///
/// Only [approved] records can reach an AI request. [deleted] is retained so a
/// loaded tombstone is never revived by a stale file; application deletes
/// normally remove the record entirely.
enum MemoryStatus {
  pending,
  approved,
  rejected,
  deleted,
}

extension MemoryStatusX on MemoryStatus {
  String get storageKey => name;

  String get label => switch (this) {
        MemoryStatus.pending => 'Pending approval',
        MemoryStatus.approved => 'Approved',
        MemoryStatus.rejected => 'Rejected',
        MemoryStatus.deleted => 'Deleted',
      };

  static MemoryStatus? fromStorage(Object? value) {
    if (value is! String) return null;
    for (final MemoryStatus status in MemoryStatus.values) {
      if (status.storageKey == value) return status;
    }
    return null;
  }
}
