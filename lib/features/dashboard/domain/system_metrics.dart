/// Windows firewall state. A failed probe is unavailable, never disabled.
enum FirewallReadiness { enabled, disabled, unavailable }

/// A single sample of real telemetry reported by the local AURA API.
class SystemMetrics {
  const SystemMetrics({
    required this.hostName,
    required this.osName,
    required this.bootTime,
    required this.uptimeSeconds,
    required this.cpuPercent,
    required this.cpuCores,
    required this.cpuFrequencyMHz,
    required this.perCoreCpu,
    required this.memoryTotalBytes,
    required this.memoryUsedBytes,
    required this.memoryAvailableBytes,
    required this.memoryPercent,
    required this.diskPath,
    required this.diskTotalBytes,
    required this.diskUsedBytes,
    required this.diskFreeBytes,
    required this.diskPercent,
    required this.bytesSent,
    required this.bytesReceived,
    required this.sentPerSecond,
    required this.receivedPerSecond,
    required this.activeInterfaceCount,
    required this.processCount,
    required this.topProcesses,
    required this.batteryPercent,
    required this.batteryPlugged,
    required this.batterySecondsLeft,
    required this.firewallEnabled,
    required this.firewallState,
  });

  final String hostName;
  final String osName;
  final DateTime bootTime;
  final int uptimeSeconds;
  final double cpuPercent;
  final int cpuCores;
  final int cpuFrequencyMHz;
  final List<double> perCoreCpu;
  final int memoryTotalBytes;
  final int memoryUsedBytes;
  final int memoryAvailableBytes;
  final double memoryPercent;
  final String diskPath;
  final int diskTotalBytes;
  final int diskUsedBytes;
  final int diskFreeBytes;
  final double diskPercent;
  final int bytesSent;
  final int bytesReceived;
  final double sentPerSecond;
  final double receivedPerSecond;
  final int activeInterfaceCount;
  final int processCount;
  final List<TopProcess> topProcesses;
  final int? batteryPercent;
  final bool? batteryPlugged;
  final int? batterySecondsLeft;

  /// Null when the firewall probe could not be completed.
  final bool? firewallEnabled;

  /// Explicit tri-state: enabled, disabled or unavailable.
  final FirewallReadiness firewallState;

  double get memoryUsedGiB => memoryUsedBytes / (1024 * 1024 * 1024);
  double get memoryTotalGiB => memoryTotalBytes / (1024 * 1024 * 1024);
  double get diskFreeGiB => diskFreeBytes / (1024 * 1024 * 1024);
  double get diskTotalGiB => diskTotalBytes / (1024 * 1024 * 1024);
}

class TopProcess {
  const TopProcess({
    required this.pid,
    required this.name,
    required this.memoryPercent,
  });

  final int pid;
  final String name;
  final double memoryPercent;
}
