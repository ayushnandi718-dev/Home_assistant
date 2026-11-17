import 'package:aura_hub/features/dashboard/domain/dashboard_snapshot.dart';

abstract class DashboardRepository {
  Future<DashboardSnapshot> loadDashboard();
}
