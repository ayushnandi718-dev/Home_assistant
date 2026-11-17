import 'package:aura_hub/features/dashboard/domain/activity_event.dart';
import 'package:aura_hub/features/dashboard/domain/system_metrics.dart';
import 'package:aura_hub/features/devices/domain/aura_device.dart';

enum CoreLinkState { notLinked, linked, degraded }

enum NetworkReadiness { notConfigured, configured }

enum SecurityReadiness { pending, ready }

class DashboardSnapshot {
  const DashboardSnapshot({
    required this.devices,
    required this.activity,
    required this.coreLink,
    required this.network,
    required this.security,
    required this.generatedAt,
    required this.isDemo,
    required this.system,
    required this.apiUrl,
  });

  final List<AuraDevice> devices;
  final List<ActivityEvent> activity;
  final CoreLinkState coreLink;
  final NetworkReadiness network;
  final SecurityReadiness security;
  final DateTime generatedAt;
  final bool isDemo;
  final SystemMetrics system;
  final String apiUrl;

  int get registeredCount => devices.length;

  int get connectedCount =>
      devices.where((AuraDevice device) => device.isOnline).length;

  int? get averageBatteryPercent {
    final List<int> values = devices
        .where((AuraDevice device) => device.batteryPercent != null)
        .map((AuraDevice device) => device.batteryPercent!)
        .toList();
    if (values.isEmpty) return null;
    final int total = values.reduce((int a, int b) => a + b);
    return (total / values.length).round();
  }
}
