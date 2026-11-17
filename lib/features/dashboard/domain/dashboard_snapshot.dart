import 'package:aura_hub/features/dashboard/domain/activity_event.dart';
import 'package:aura_hub/features/dashboard/domain/system_metrics.dart';
import 'package:aura_hub/features/devices/domain/aura_device.dart';

/// Status of the AURA device/backend link.
///
/// This is deliberately independent of the local Windows telemetry API: a
/// responding PC API says nothing about whether ESP32 AURA hardware is linked.
enum CoreLinkState { notLinked, linked, degraded }

enum NetworkReadiness { notConfigured, configured }

enum SecurityReadiness { pending, ready }

class DashboardSnapshot {
  const DashboardSnapshot({
    required this.devices,
    required this.activity,
    required this.coreLink,
    required this.localApiOnline,
    this.stale = false,
    required this.network,
    required this.security,
    required this.generatedAt,
    required this.isDemo,
    required this.system,
    required this.apiUrl,
  });

  /// Registered AURA devices only. The Windows host is never one of these.
  final List<AuraDevice> devices;

  /// Sampled Windows host events, not AURA device events.
  final List<ActivityEvent> activity;

  /// Always notLinked until an actual AURA device/backend is connected.
  final CoreLinkState coreLink;

  /// Whether the local Windows telemetry endpoint answered this request.
  final bool localApiOnline;

  /// True when these are the last successful readings after a failed poll.
  final bool stale;
  final NetworkReadiness network;
  final SecurityReadiness security;
  final DateTime generatedAt;
  final bool isDemo;

  /// Real Windows host telemetry. Never AURA hardware telemetry.
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

  /// Returns the same measurements with refreshed connection metadata.
  DashboardSnapshot copyWith({
    bool? localApiOnline,
    bool? stale,
  }) {
    return DashboardSnapshot(
      devices: devices,
      activity: activity,
      coreLink: coreLink,
      localApiOnline: localApiOnline ?? this.localApiOnline,
      stale: stale ?? this.stale,
      network: network,
      security: security,
      generatedAt: generatedAt,
      isDemo: isDemo,
      system: system,
      apiUrl: apiUrl,
    );
  }
}
