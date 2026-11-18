import 'dart:async';

import 'package:aura_hub/features/family/data/family_directory_repository.dart';
import 'package:aura_hub/features/family/data/family_directory_store.dart';
import 'package:aura_hub/features/family/domain/family_directory_service.dart';
import 'package:aura_hub/features/family/domain/family_member.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the active directory state for one workspace.
class FamilyDirectoryController extends StateNotifier<List<FamilyMember>> {
  FamilyDirectoryController(this._repository) : super(const <FamilyMember>[]) {
    unawaited(load());
  }

  final FamilyDirectoryRepository _repository;

  Future<void> load() async => state = await _repository.load();

  Future<void> add(FamilyMember member) async {
    if (member.validationError != null) return;
    state = await _repository.upsert(member);
  }

  Future<void> update(FamilyMember member) async {
    if (member.validationError != null) return;
    state = await _repository.upsert(member);
  }

  Future<void> remove(String id) async {
    state = await _repository.remove(id);
  }

  Future<FamilyImportResult> importMembers({
    required List<FamilyMember> incoming,
    bool overwriteDuplicates = false,
  }) async {
    final FamilyImportResult result = FamilyDirectoryService.importMembers(
      state,
      incoming,
      overwriteDuplicates: overwriteDuplicates,
    );
    state = await _repository.replaceAll(result.members);
    return FamilyImportResult(
      members: state,
      added: result.added,
      updated: result.updated,
      skipped: result.skipped,
    );
  }
}

/// The directory belongs to the FAMILY workspace. AYUSH-private data is never
/// used as a source for this provider.
final Provider<FamilyDirectoryRepository> familyDirectoryRepositoryProvider =
    Provider<FamilyDirectoryRepository>((Ref ref) {
  return LocalFamilyDirectoryRepository(
    store: FamilyDirectoryStore(profile: AuraProfile.family),
  );
});

final StateNotifierProvider<FamilyDirectoryController, List<FamilyMember>>
    familyDirectoryControllerProvider =
    StateNotifierProvider<FamilyDirectoryController, List<FamilyMember>>(
  (Ref ref) => FamilyDirectoryController(
    ref.read(familyDirectoryRepositoryProvider),
  ),
);

final Provider<List<FamilyMember>> familyDirectoryProvider =
    Provider<List<FamilyMember>>(
  (Ref ref) => ref.watch(familyDirectoryControllerProvider),
);
