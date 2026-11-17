import 'package:aura_hub/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:aura_hub/features/diagnostics/domain/sampler_health.dart';

/// One timestamped host measurement.
///
/// Values are nullable on purpose: an unavailable or failed sampler must never
/// be charted as a zero reading. Network rates stay in bytes per second.
class TelemetrySample {
  const TelemetrySample({
    required this.timestamp,
    this.cpuPercent,
    this.memoryPercent,
    this.diskPercent,
    this.bytesSentPerSecond,
    this.bytesReceivedPerSecond,
  });

  factory TelemetrySample.fromSnapshot(DashboardSnapshot snapshot) {
    final bool trustworthy = !snapshot.stale &&
        snapshot.localApiOnline &&
        snapshot.samplerHealth?.status == SamplerReadiness.ready;
    return TelemetrySample(
      timestamp: snapshot.generatedAt,
      cpuPercent: trustworthy ? _number(snapshot.system.cpuPercent) : null,
      memoryPercent:
          trustworthy ? _number(snapshot.system.memoryPercent) : null,
      diskPercent: trustworthy ? _number(snapshot.system.diskPercent) : null,
      bytesSentPerSecond:
          trustworthy ? _number(snapshot.system.sentPerSecond) : null,
      bytesReceivedPerSecond:
          trustworthy ? _number(snapshot.system.receivedPerSecond) : null,
    );
  }

  static double? _number(double value) =>
      value.isFinite && value >= 0 ? value : null;

  final DateTime timestamp;
  final double? cpuPercent;
  final double? memoryPercent;
  final double? diskPercent;
  final double? bytesSentPerSecond;
  final double? bytesReceivedPerSecond;
}

/// Bounded, session-only circular buffer of successful Windows host samples.
///
/// The backing array is fixed-size. Once full, the oldest entry is overwritten
/// and the start pointer advances, so long polling sessions cannot grow memory
/// without limit. Time-based retention is applied on every write.
class TelemetryHistory {
  const TelemetryHistory({
    this.maxSamples = defaultMaxSamples,
    this.retention = const Duration(minutes: 30),
  })  : _buffer = const <TelemetrySample?>[],
        _start = 0,
        _count = 0,
        _revision = 0;

  static const int defaultMaxSamples = 600;

  TelemetryHistory._(
    this._buffer,
    this._start,
    this._count,
    this.maxSamples,
    this.retention,
    this._revision,
  );

  final List<TelemetrySample?> _buffer;
  final int _start;
  final int _count;
  final int _revision;

  /// Maximum number of samples retained in memory.
  final int maxSamples;

  /// Maximum age of a sample before it is discarded.
  final Duration retention;

  int get length => _count;
  bool get isEmpty => _count == 0;

  /// Increments only when a sample is written, so painters can skip repaints.
  int get revision => _revision;

  /// Samples in chronological order, oldest first.
  ///
  /// The const constructor starts with an empty backing list, so guard against
  /// that case before indexing into it.
  List<TelemetrySample> get samples {
    final List<TelemetrySample> ordered = <TelemetrySample>[];
    if (_buffer.isEmpty) {
      return List<TelemetrySample>.unmodifiable(ordered);
    }
    for (int index = 0; index < _count; index++) {
      final TelemetrySample? sample =
          _buffer[(_start + index) % _buffer.length];
      if (sample != null) ordered.add(sample);
    }
    return List<TelemetrySample>.unmodifiable(ordered);
  }

  /// Writes [sample] into a fixed-size buffer of exactly [maxSamples] slots.
  ///
  /// Samples outside the retention window are dropped first. Once the window
  /// is full, the oldest sample is overwritten and the start pointer advances,
  /// so a long polling session never grows memory without bound.
  TelemetryHistory add(TelemetrySample sample) {
    final int capacity = maxSamples < 1 ? 1 : maxSamples;
    final DateTime cutoff = sample.timestamp.subtract(retention);

    final List<TelemetrySample> kept = samples
        .where((TelemetrySample s) => !s.timestamp.isBefore(cutoff))
        .toList();

    final List<TelemetrySample?> buffer =
        List<TelemetrySample?>.filled(capacity, null);
    int start = 0;
    int count;

    if (kept.length >= capacity) {
      // Keep the most recent capacity-1 samples, then append the new one.
      final List<TelemetrySample> recent =
          kept.sublist(kept.length - capacity + 1);
      for (int index = 0; index < recent.length; index++) {
        buffer[index] = recent[index];
      }
      buffer[capacity - 1] = sample;
      count = capacity;
    } else {
      for (int index = 0; index < kept.length; index++) {
        buffer[index] = kept[index];
      }
      count = kept.length;
      buffer[count] = sample;
      count++;
    }

    return TelemetryHistory._(
      buffer,
      start,
      count,
      capacity,
      retention,
      _revision + 1,
    );
  }
}
