import 'package:aura_hub/features/family/data/family_directory_store.dart';
import 'package:aura_hub/features/family/domain/family_member.dart';

/// Application boundary for family records. Widgets never touch the file store.
abstract class FamilyDirectoryRepository {
  Future<List<FamilyMember>> load();

  Future<List<FamilyMember>> upsert(FamilyMember member);

  Future<List<FamilyMember>> remove(String id);

  Future<List<FamilyMember>> replaceAll(List<FamilyMember> members);
}

/// Local, profile-scoped repository implementation.
class LocalFamilyDirectoryRepository implements FamilyDirectoryRepository {
  LocalFamilyDirectoryRepository({required FamilyDirectoryStore store})
      : _store = store;

  final FamilyDirectoryStore _store;
  List<FamilyMember> _members = const <FamilyMember>[];
  bool _loaded = false;

  @override
  Future<List<FamilyMember>> load() async {
    _members = await _store.load();
    _loaded = true;
    return List<FamilyMember>.unmodifiable(_members);
  }

  Future<void> _ensureLoaded() async {
    if (!_loaded) await load();
  }

  @override
  Future<List<FamilyMember>> upsert(FamilyMember member) async {
    await _ensureLoaded();
    final List<FamilyMember> next = <FamilyMember>[
      member,
      ..._members.where((FamilyMember item) => item.id != member.id),
    ];
    return _commit(next);
  }

  @override
  Future<List<FamilyMember>> remove(String id) async {
    await _ensureLoaded();
    return _commit(
      _members.where((FamilyMember item) => item.id != id).toList(),
    );
  }

  @override
  Future<List<FamilyMember>> replaceAll(List<FamilyMember> members) async =>
      _commit(members);

  Future<List<FamilyMember>> _commit(List<FamilyMember> next) async {
    await _store.save(next);
    _members = await _store.load();
    _loaded = true;
    return List<FamilyMember>.unmodifiable(_members);
  }
}
