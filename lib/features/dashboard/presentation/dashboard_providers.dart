import 'package:aura_hub/features/dashboard/data/mock_dashboard_repository.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_repository.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:aura_hub/features/devices/data/mock_device_repository.dart';
import 'package:aura_hub/features/devices/domain/device_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final Provider<DeviceRepository> deviceRepositoryProvider =
    Provider<DeviceRepository>((Ref ref) {
  return const MockDeviceRepository();
});

final Provider<DashboardRepository> dashboardRepositoryProvider =
    Provider<DashboardRepository>((Ref ref) {
  return MockDashboardRepository(
    deviceRepository: ref.watch(deviceRepositoryProvider),
  );
});

final FutureProvider<DashboardSnapshot> dashboardSnapshotProvider =
    FutureProvider<DashboardSnapshot>((Ref ref) async {
  return ref.watch(dashboardRepositoryProvider).loadDashboard();
});
