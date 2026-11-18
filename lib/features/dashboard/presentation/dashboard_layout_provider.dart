import 'dart:async';

import 'package:aura_hub/features/dashboard/data/dashboard_layout_store.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_layout.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Owns one workspace's dashboard layout and persists every change immediately.
class DashboardLayoutController extends StateNotifier<DashboardLayout> {
  DashboardLayoutController({DashboardLayoutStore? store})
      : _store = store ?? DashboardLayoutStore(),
        super(DashboardLayout.defaults);

  final DashboardLayoutStore _store;

  Future<void> load() async => state = await _store.load();

  void toggle(DashboardWidgetId id) => _commit(state.toggle(id));

  void setSize(DashboardWidgetId id, DashboardWidgetSize size) =>
      _commit(state.setSize(id, size));

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

/// One independent, persisted layout per workspace.
final StateNotifierProviderFamily<DashboardLayoutController, DashboardLayout,
        AuraProfile> dashboardLayoutForProvider =
    StateNotifierProvider.family<DashboardLayoutController, DashboardLayout,
        AuraProfile>((Ref ref, AuraProfile profile) {
  return DashboardLayoutController(
    store: DashboardLayoutStore(profile: profile),
  );
});

/// The layout for the currently active workspace.
///
/// These are plain providers on purpose: the controller is owned and disposed
/// by [dashboardLayoutForProvider]. A `StateNotifierProvider` here would try to
/// dispose the borrowed controller a second time when the container closes.
/// Switching profiles still swaps controllers, so an AYUSH edit can never be
/// written to the FAMILY file. Both controllers are preloaded in `main()`.
final Provider<DashboardLayout> dashboardLayoutProvider =
    Provider<DashboardLayout>((Ref ref) {
  final AuraProfile profile = ref.watch(activeProfileProvider);
  return ref.watch(dashboardLayoutForProvider(profile));
});

/// Commands for the active workspace's layout.
final Provider<DashboardLayoutController>
    activeDashboardLayoutControllerProvider =
    Provider<DashboardLayoutController>((Ref ref) {
  final AuraProfile profile = ref.watch(activeProfileProvider);
  return ref.watch(dashboardLayoutForProvider(profile).notifier);
});
