import 'package:aura_hub/core/network/aura_api_client.dart';
import 'package:aura_hub/features/dashboard/data/live_dashboard_repository.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_repository.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final Provider<AuraApiClient> auraApiClientProvider =
    Provider<AuraApiClient>((Ref ref) {
  return AuraApiClient();
});

final Provider<DashboardRepository> dashboardRepositoryProvider =
    Provider<DashboardRepository>((Ref ref) {
  return LiveDashboardRepository(client: ref.watch(auraApiClientProvider));
});

final FutureProvider<DashboardSnapshot> dashboardSnapshotProvider =
    FutureProvider<DashboardSnapshot>((Ref ref) async {
  return ref.watch(dashboardRepositoryProvider).loadDashboard();
});
