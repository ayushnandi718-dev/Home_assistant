import 'package:aura_hub/features/dashboard/domain/activity_event.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_repository.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:aura_hub/features/devices/domain/device_repository.dart';

/// Supplies clearly labelled demonstration values for the first milestone.
class MockDashboardRepository implements DashboardRepository {
  const MockDashboardRepository({
    required this.deviceRepository,
    this.latency = const Duration(milliseconds: 500),
  });

  final DeviceRepository deviceRepository;
  final Duration latency;

  @override
  Future<DashboardSnapshot> loadDashboard() async {
    if (latency > Duration.zero) {
      await Future<void>.delayed(latency);
    }
    final DateTime now = DateTime.now();
    final List<ActivityEvent> activity = <ActivityEvent>[
      ActivityEvent(
        id: 'demo-evt-004',
        title: 'Workspace protection pending',
        detail:
            'Ayush PIN authentication will be enforced when backend security lands.',
        category: ActivityCategory.security,
        severity: ActivitySeverity.warning,
        timestamp: now.subtract(const Duration(minutes: 42)),
        isDemo: true,
      ),
      ActivityEvent(
        id: 'demo-evt-003',
        title: 'Integration catalogue staged',
        detail:
            'Gmail, Spotify, GitHub, Weather and Tavily connectors are planned.',
        category: ActivityCategory.integration,
        severity: ActivitySeverity.info,
        timestamp: now.subtract(const Duration(hours: 5)),
        isDemo: true,
      ),
      ActivityEvent(
        id: 'demo-evt-002',
        title: 'Demo device record loaded',
        detail:
            'AURA Desk is a sample offline record. No hardware was contacted.',
        category: ActivityCategory.device,
        severity: ActivitySeverity.info,
        timestamp: now.subtract(const Duration(hours: 2, minutes: 15)),
        isDemo: true,
      ),
      ActivityEvent(
        id: 'demo-evt-001',
        title: 'AURA Hub foundation initialised',
        detail:
            'The shell and dashboard loaded from the local mock repository.',
        category: ActivityCategory.system,
        severity: ActivitySeverity.info,
        timestamp: now.subtract(const Duration(days: 1)),
        isDemo: true,
      ),
    ];
    activity.sort((ActivityEvent a, ActivityEvent b) =>
        b.timestamp.compareTo(a.timestamp));

    return DashboardSnapshot(
      devices: await deviceRepository.fetchDevices(),
      activity: activity,
      coreLink: CoreLinkState.notLinked,
      network: NetworkReadiness.notConfigured,
      security: SecurityReadiness.pending,
      generatedAt: now,
      isDemo: true,
    );
  }
}
