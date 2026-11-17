import 'dart:convert';
import 'dart:io';

import 'package:aura_hub/core/utilities/local_paths.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_layout.dart';

/// Persists the user's dashboard widget order and visibility as JSON.
class DashboardLayoutStore {
  DashboardLayoutStore({Directory? directory})
      : _file = File(
          '${(directory ?? LocalPaths.appData()).path}${Platform.pathSeparator}dashboard_layout.json',
        );

  final File _file;

  Future<DashboardLayout> load() async {
    try {
      if (!await _file.exists()) return DashboardLayout.defaults;
      return DashboardLayout.fromJson(jsonDecode(await _file.readAsString()));
    } catch (_) {
      return DashboardLayout.defaults;
    }
  }

  Future<void> save(DashboardLayout layout) async {
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(
        jsonEncode(layout.toJson()),
        flush: true,
      );
    } catch (_) {
      // Keep the running app usable if the user's profile directory is read-only.
    }
  }
}
