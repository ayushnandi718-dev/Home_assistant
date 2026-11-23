import 'dart:async';

import 'package:aura_hub/features/family/data/family_directory_repository.dart';
import 'package:aura_hub/features/family/data/family_directory_store.dart';
import 'package:aura_hub/features/family/domain/family_directory_service.dart';
import 'package:aura_hub/features/family/domain/family_member.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the active directory state for one workspace.
class FamilyDirectoryController extends StateNotifier<List<FamilyMember>> {
  FamilyDirectoryController(
    this._repository, {
    required ProfileAccessReader accessReader,
  })  : _accessReader = accessReader,
        super(const <FamilyMember>[]) {
    unawaited(load());
  }

  final FamilyDirectoryRepository _repository;
  final ProfileAccessReader _accessReader;
  int _generation = 0;

  ProfileOperationOwner? _beginOwner() {
    try {
      return ProfileOperationOwner(
        accessReader: _accessReader,
        profile: AuraProfile.family,
      );
    } on AuraProfileAccessDenied {
      return null;
    }
  }

  bool _isCurrent(ProfileOperationOwner owner, int generation) =>
      owner.isCurrent && generation == _generation;

  Future<void> load() async {
    final int generation = ++_generation;
    final ProfileOperationOwner? owner = _beginOwner();
    if (owner == null) return;
    final List<FamilyMember> members = await _repository.load();
    if (!mounted || !_isCurrent(owner, generation)) return;
    state = members;
  }

  Future<void> add(FamilyMember member) async {
    if (member.validationError != null) return;
    final int generation = _generation;
    final ProfileOperationOwner? owner = _beginOwner();
    if (owner == null) return;
    final List<FamilyMember> members = await _repository.upsert(member);
    if (!mounted || !_isCurrent(owner, generation)) return;
    state = members;
  }

  Future<void> update(FamilyMember member) async {
    if (member.validationError != null) return;
    final int generation = _generation;
    final ProfileOperationOwner? owner = _beginOwner();
    if (owner == null) return;
    final List<FamilyMember> members = await _repository.upsert(member);
    if (!mounted || !_isCurrent(owner, generation)) return;
    state = members;
  }

  Future<void> remove(String id) async {
    final int generation = _generation;
    final ProfileOperationOwner? owner = _beginOwner();
    if (owner == null) return;
    final List<FamilyMember> members = await _repository.remove(id);
    if (!mounted || !_isCurrent(owner, generation)) return;
    state = members;
  }

  Future<FamilyImportResult> importMembers({
    required List<FamilyMember> incoming,
    bool overwriteDuplicates = false,
  }) async {
    final int generation = _generation;
    final ProfileOperationOwner? owner = _beginOwner();
    if (owner == null) {
      return FamilyImportResult(
        members: state,
        added: 0,
        updated: 0,
        skipped: incoming.length,
      );
    }
    final FamilyImportResult result = FamilyDirectoryService.importMembers(
      state,
      incoming,
      overwriteDuplicates: overwriteDuplicates,
    );
    final List<FamilyMember> members = await _repository.replaceAll(
      result.members,
    );
    if (!mounted || !_isCurrent(owner, generation)) {
      return FamilyImportResult(
        members: state,
        added: 0,
        updated: 0,
        skipped: incoming.length,
      );
    }
    state = members;
    return FamilyImportResult(
      members: state,
      added: result.added,
      updated: result.updated,
      skipped: result.skipped,
    );
  }

  /// Called when the workspace changes. FAMILY data is shared, but stale async
  /// results from a previously opened session must not publish new state.
  void discardForProfileSwitch() {
    _generation++;
    state = const <FamilyMember>[];
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
  (Ref ref) {
    final FamilyDirectoryController controller = FamilyDirectoryController(
      ref.read(familyDirectoryRepositoryProvider),
      accessReader: () => ref.read(profileAccessProvider),
    );
    // The owner checks already stop stale publication. Listening to real
    // session changes also invalidates in-flight work and clears state through
    // the production lifecycle instead of relying on a caller-invoked method.
    ref.listen<ProfileSession>(profileSessionProvider, (_, __) {
      if (controller.mounted) controller.discardForProfileSwitch();
    });
    return controller;
  },
);

final Provider<List<FamilyMember>> familyDirectoryProvider =
    Provider<List<FamilyMember>>(
  (Ref ref) => ref.watch(familyDirectoryControllerProvider),
);
