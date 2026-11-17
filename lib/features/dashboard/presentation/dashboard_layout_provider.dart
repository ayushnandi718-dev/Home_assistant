import 'dart:async';

import 'package:aura_hub/features/dashboard/data/dashboard_layout_store.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Owns dashboard customization and persists every change immediately.
class DashboardLayoutController extends StateNotifier<DashboardLayout> {
  DashboardLayoutController({DashboardLayoutStore? store})
      : _store = store ?? DashboardLayoutStore(),
        super(DashboardLayout.defaults);

  final DashboardLayoutStore _store;

  Future<void> load() async => state = await _store.load();

  void toggle(DashboardWidgetId id) => _commit(state.toggle(id));

  void reorder(int oldIndex, int newIndex) =>
      _commit(state.reorder(oldIndex, newIndex));

  Future<void> reset() async {
    state = DashboardLayout.defaults;
    await _store.save(state);
  }

  void _commit(DashboardLayout next) {
    if (next == state) return;
    state = next;
    unawaited(_store.save(next));
  }
}

final StateNotifierProvider<DashboardLayoutController, DashboardLayout>
    dashboardLayoutProvider =
    StateNotifierProvider<DashboardLayoutController, DashboardLayout>(
  (Ref ref) => DashboardLayoutController(),
);
