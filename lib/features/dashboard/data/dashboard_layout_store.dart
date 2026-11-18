import 'dart:convert';
import 'dart:io';

import 'package:aura_hub/core/utilities/local_paths.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_layout.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';

/// Persists one dashboard layout per workspace as JSON.
///
/// AYUSH and FAMILY never share a file. The pre-workspace
/// `dashboard_layout.json` is used once as a migration source so an existing
/// user's order and visibility survive the upgrade, but it is never rewritten.
class DashboardLayoutStore {
  DashboardLayoutStore({Directory? directory, this.profile})
      : _directory = directory ?? LocalPaths.appData(),
        _file = File(
          '${(directory ?? LocalPaths.appData()).path}${Platform.pathSeparator}${_fileName(profile)}',
        ),
        _legacyFile = profile == null
            ? null
            : File(
                '${(directory ?? LocalPaths.appData()).path}${Platform.pathSeparator}dashboard_layout.json',
              );

  /// Null only for the legacy, unscoped store used by migration tests.
  final AuraProfile? profile;
  final Directory _directory;
  final File _file;
  final File? _legacyFile;

  String get filePath => _file.path;

  static String _fileName(AuraProfile? profile) => profile == null
      ? 'dashboard_layout.json'
      : 'dashboard_layout_${profile.storageScope}.json';

  Future<DashboardLayout> load() async {
    final DashboardLayout? stored = await _read(_file);
    if (stored != null) return stored;

    final File? legacy = _legacyFile;
    if (legacy == null) return DashboardLayout.defaults;

    // One-time migration: adopt the old shared layout into this workspace's
    // own file. Keep the original so the other workspace can migrate too.
    final DashboardLayout? migrated = await _read(legacy);
    if (migrated != null) {
      await save(migrated);
      return migrated;
    }
    return DashboardLayout.defaults;
  }

  Future<DashboardLayout?> _read(File file) async {
    try {
      if (!await file.exists()) return null;
      return DashboardLayout.fromJson(jsonDecode(await file.readAsString()));
    } catch (_) {
      return null;
    }
  }

  Future<void> save(DashboardLayout layout) async {
    try {
      await _directory.create(recursive: true);
      await _file.writeAsString(
        jsonEncode(layout.toJson()),
        flush: true,
      );
    } catch (_) {
      // Keep the running app usable if the user's profile directory is read-only.
    }
  }
}
