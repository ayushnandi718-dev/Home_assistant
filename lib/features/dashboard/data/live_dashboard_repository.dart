import 'package:aura_hub/core/network/aura_api_client.dart';
import 'package:aura_hub/features/dashboard/domain/activity_event.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_repository.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:aura_hub/features/dashboard/domain/system_metrics.dart';
import 'package:aura_hub/features/devices/domain/aura_device.dart';

/// Loads the dashboard from the local AURA telemetry API.
///
/// Every value in the returned snapshot is measured on this Windows machine.
class LiveDashboardRepository implements DashboardRepository {
  const LiveDashboardRepository({required this.client});

  final AuraApiClient client;

  @override
  Future<DashboardSnapshot> loadDashboard() async {
    final Map<String, dynamic> json = await client.getJson('/api/system');
    final SystemMetrics metrics = _parseMetrics(json);
    final DateTime generatedAt =
        DateTime.tryParse(_string(json, 'generatedAt')) ?? DateTime.now();

    final AuraDevice host = AuraDevice(
      id: 'local-host-${metrics.hostName}',
      name: metrics.hostName,
      model: 'Local Windows host',
      firmwareVersion: metrics.osName,
      connectionState: DeviceConnectionState.online,
      connectionQuality: metrics.cpuPercent >= 85
          ? DeviceConnectionQuality.fair
          : metrics.cpuPercent >= 50
              ? DeviceConnectionQuality.good
              : DeviceConnectionQuality.excellent,
      isDemo: false,
      batteryPercent: metrics.batteryPercent,
      lastSeen: generatedAt,
      lastSynced: generatedAt,
    );

    return DashboardSnapshot(
      devices: <AuraDevice>[host],
      activity: _buildActivity(metrics, generatedAt),
      coreLink: CoreLinkState.linked,
      network: metrics.activeInterfaceCount > 0
          ? NetworkReadiness.configured
          : NetworkReadiness.notConfigured,
      security: metrics.firewallEnabled
          ? SecurityReadiness.ready
          : SecurityReadiness.pending,
      generatedAt: generatedAt,
      isDemo: false,
      system: metrics,
      apiUrl: client.displayUrl,
    );
  }

  List<ActivityEvent> _buildActivity(
    SystemMetrics metrics,
    DateTime generatedAt,
  ) {
    final String prefix = 'live-${generatedAt.millisecondsSinceEpoch}';
    final List<ActivityEvent> events = <ActivityEvent>[
      ActivityEvent(
        id: '$prefix-cpu',
        title: 'CPU load ${metrics.cpuPercent.toStringAsFixed(1)}%',
        detail:
            '${metrics.cpuCores} logical cores, ${metrics.cpuFrequencyMHz} MHz, '
            '${metrics.processCount} processes running.',
        category: ActivityCategory.system,
        severity: metrics.cpuPercent >= 85
            ? ActivitySeverity.warning
            : ActivitySeverity.info,
        timestamp: generatedAt,
        isDemo: false,
      ),
      ActivityEvent(
        id: '$prefix-memory',
        title: 'Memory ${metrics.memoryPercent.toStringAsFixed(1)}% in use',
        detail: '${metrics.memoryUsedGiB.toStringAsFixed(1)} of '
            '${metrics.memoryTotalGiB.toStringAsFixed(1)} GB committed.',
        category: ActivityCategory.system,
        severity: metrics.memoryPercent >= 90
            ? ActivitySeverity.warning
            : ActivitySeverity.info,
        timestamp: generatedAt,
        isDemo: false,
      ),
      ActivityEvent(
        id: '$prefix-disk',
        title:
            '${metrics.diskPath} ${metrics.diskPercent.toStringAsFixed(1)}% full',
        detail: '${metrics.diskFreeGiB.toStringAsFixed(1)} GB free of '
            '${metrics.diskTotalGiB.toStringAsFixed(1)} GB.',
        category: ActivityCategory.system,
        severity: metrics.diskPercent >= 90
            ? ActivitySeverity.warning
            : ActivitySeverity.info,
        timestamp: generatedAt,
        isDemo: false,
      ),
      ActivityEvent(
        id: '$prefix-network',
        title: '${metrics.activeInterfaceCount} network links active',
        detail: 'Down ${_rate(metrics.receivedPerSecond)}, '
            'up ${_rate(metrics.sentPerSecond)}. '
            '${_bytes(metrics.bytesReceived)} received since boot.',
        category: ActivityCategory.device,
        severity: ActivitySeverity.info,
        timestamp: generatedAt,
        isDemo: false,
      ),
      ActivityEvent(
        id: '$prefix-security',
        title: metrics.firewallEnabled
            ? 'Windows firewall enabled'
            : 'Windows firewall not fully enabled',
        detail: 'Read from the local Windows firewall profiles.',
        category: ActivityCategory.security,
        severity: metrics.firewallEnabled
            ? ActivitySeverity.info
            : ActivitySeverity.warning,
        timestamp: generatedAt,
        isDemo: false,
      ),
    ];

    if (metrics.topProcesses.isNotEmpty) {
      final TopProcess top = metrics.topProcesses.first;
      events.add(
        ActivityEvent(
          id: '$prefix-process',
          title: 'Top memory process: ${top.name}',
          detail:
              'PID ${top.pid} using ${top.memoryPercent.toStringAsFixed(1)}% '
              'of installed memory.',
          category: ActivityCategory.system,
          severity: ActivitySeverity.info,
          timestamp: generatedAt,
          isDemo: false,
        ),
      );
    }

    return events;
  }

  static String _rate(double bytesPerSecond) {
    if (bytesPerSecond >= 1024 * 1024) {
      return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
    return '${(bytesPerSecond / 1024).toStringAsFixed(0)} KB/s';
  }

  static String _bytes(int value) {
    if (value >= 1024 * 1024 * 1024) {
      return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(value / (1024 * 1024)).toStringAsFixed(0)} MB';
  }
}

SystemMetrics _parseMetrics(Map<String, dynamic> json) {
  final Map<String, dynamic> host = _object(json, 'host');
  final Map<String, dynamic> cpu = _object(json, 'cpu');
  final Map<String, dynamic> memory = _object(json, 'memory');
  final Map<String, dynamic> disk = _object(json, 'disk');
  final Map<String, dynamic> network = _object(json, 'network');
  final Map<String, dynamic> security = _object(json, 'security');
  final Object? battery = json['battery'];

  return SystemMetrics(
    hostName: _string(host, 'name'),
    osName: _string(host, 'os'),
    bootTime: DateTime.tryParse(_string(host, 'bootTime')) ?? DateTime.now(),
    uptimeSeconds: _int(host, 'uptimeSeconds'),
    cpuPercent: _double(cpu, 'usagePercent'),
    cpuCores: _int(cpu, 'cores'),
    cpuFrequencyMHz: _int(cpu, 'frequencyMHz'),
    perCoreCpu: (cpu['perCore'] as List<dynamic>? ?? <dynamic>[])
        .map((dynamic value) => (value as num).toDouble())
        .toList(),
    memoryTotalBytes: _int(memory, 'totalBytes'),
    memoryUsedBytes: _int(memory, 'usedBytes'),
    memoryAvailableBytes: _int(memory, 'availableBytes'),
    memoryPercent: _double(memory, 'usagePercent'),
    diskPath: _string(disk, 'path'),
    diskTotalBytes: _int(disk, 'totalBytes'),
    diskUsedBytes: _int(disk, 'usedBytes'),
    diskFreeBytes: _int(disk, 'freeBytes'),
    diskPercent: _double(disk, 'usagePercent'),
    bytesSent: _int(network, 'bytesSent'),
    bytesReceived: _int(network, 'bytesReceived'),
    sentPerSecond: _double(network, 'sentBytesPerSecond'),
    receivedPerSecond: _double(network, 'receivedBytesPerSecond'),
    activeInterfaceCount: _int(network, 'activeInterfaces'),
    processCount: _int(json, 'processCount'),
    topProcesses: (json['topProcesses'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(
          (Map<String, dynamic> item) => TopProcess(
            pid: _int(item, 'pid'),
            name: _string(item, 'name'),
            memoryPercent: _double(item, 'memoryPercent'),
          ),
        )
        .toList(),
    batteryPercent:
        battery is Map<String, dynamic> ? _int(battery, 'percent') : null,
    batteryPlugged:
        battery is Map<String, dynamic> ? battery['plugged'] as bool? : null,
    batterySecondsLeft: battery is Map<String, dynamic>
        ? _intOrNull(battery, 'secondsLeft')
        : null,
    firewallEnabled: _bool(security, 'firewallEnabled'),
  );
}

Map<String, dynamic> _object(Map<String, dynamic> json, String key) =>
    json[key] is Map<String, dynamic>
        ? json[key] as Map<String, dynamic>
        : <String, dynamic>{};

String _string(Map<String, dynamic> json, String key) =>
    json[key]?.toString() ?? '';

int _int(Map<String, dynamic> json, String key) =>
    (json[key] as num?)?.toInt() ?? 0;

int? _intOrNull(Map<String, dynamic> json, String key) =>
    (json[key] as num?)?.toInt();

double _double(Map<String, dynamic> json, String key) =>
    (json[key] as num?)?.toDouble() ?? 0;

bool _bool(Map<String, dynamic> json, String key) => json[key] == true;
