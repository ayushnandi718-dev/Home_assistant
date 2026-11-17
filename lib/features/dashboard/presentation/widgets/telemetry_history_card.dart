import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/dashboard/domain/telemetry_history.dart';
import 'package:aura_hub/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';

/// Compact, dependency-free trend display for the current app session.
class TelemetryHistoryCard extends StatelessWidget {
  const TelemetryHistoryCard({
    super.key,
    required this.samples,
    this.revision = 0,
    this.capacity = 60,
    this.retentionLabel = '30 min',
  });

  final List<TelemetrySample> samples;
  final int revision;
  final int capacity;
  final String retentionLabel;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.insights_outlined, color: AuraColors.secondary),
              const SizedBox(width: AuraSpace.sm),
              Text('Host telemetry trends', style: text.titleLarge),
              const Spacer(),
              Text('${samples.length}/$capacity · $retentionLabel',
                  style: text.labelMedium),
            ],
          ),
          const SizedBox(height: AuraSpace.xs),
          Text(
            'Windows host only · session memory · missing samples are gaps, not zero',
            style: text.bodySmall,
          ),
          const SizedBox(height: AuraSpace.md),
          SizedBox(
            height: 164,
            width: double.infinity,
            child: samples.length < 2
                ? Center(
                    child: Text(
                      'Trend data appears after two healthy host samples.',
                      style: text.bodySmall,
                    ),
                  )
                : RepaintBoundary(
                    child: CustomPaint(
                      painter: _TelemetryHistoryPainter(samples, revision),
                      child: const SizedBox.expand(),
                    ),
                  ),
          ),
          const SizedBox(height: AuraSpace.sm),
          const Wrap(
            spacing: AuraSpace.md,
            runSpacing: AuraSpace.xs,
            children: <Widget>[
              _Legend(label: 'CPU %', color: AuraColors.primary),
              _Legend(label: 'Memory %', color: AuraColors.secondary),
              _Legend(label: 'Disk %', color: AuraColors.warning),
              _Legend(label: 'Network B/s', color: AuraColors.success),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AuraSpace.xxs),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      );
}

class _TelemetryHistoryPainter extends CustomPainter {
  _TelemetryHistoryPainter(this.samples, this.revision);

  final List<TelemetrySample> samples;
  final int revision;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint grid = Paint()
      ..color = AuraColors.border.withValues(alpha: 0.65)
      ..strokeWidth = 1;
    for (int index = 1; index < 4; index++) {
      final double y = size.height * index / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    _draw(
      canvas,
      size,
      (TelemetrySample s) => s.cpuPercent,
      (double value) => value / 100,
      AuraColors.primary,
    );
    _draw(
      canvas,
      size,
      (TelemetrySample s) => s.memoryPercent,
      (double value) => value / 100,
      AuraColors.secondary,
    );
    _draw(
      canvas,
      size,
      (TelemetrySample s) => s.diskPercent,
      (double value) => value / 100,
      AuraColors.warning,
    );

    final double maxRate = samples
        .map((TelemetrySample s) {
          final double? sent = s.bytesSentPerSecond;
          final double? received = s.bytesReceivedPerSecond;
          if (sent == null || received == null) return null;
          return sent + received;
        })
        .whereType<double>()
        .fold<double>(
            1, (double max, double value) => value > max ? value : max);
    _draw(
      canvas,
      size,
      (TelemetrySample s) {
        final double? sent = s.bytesSentPerSecond;
        final double? received = s.bytesReceivedPerSecond;
        if (sent == null || received == null) return null;
        return sent + received;
      },
      (double value) => value / maxRate,
      AuraColors.success,
    );
  }

  void _draw(
    Canvas canvas,
    Size size,
    double? Function(TelemetrySample) sampleValue,
    double Function(double) normalise,
    Color color,
  ) {
    final Path path = Path();
    final double denominator = (samples.length - 1).toDouble();
    Offset? previous;

    for (int index = 0; index < samples.length; index++) {
      final double? value = sampleValue(samples[index]);
      if (value == null) {
        previous = null;
        continue;
      }
      final Offset point = Offset(
        size.width * index / denominator,
        size.height * (1 - normalise(value).clamp(0.0, 1.0)),
      );
      if (previous == null) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
      previous = point;
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_TelemetryHistoryPainter oldDelegate) =>
      oldDelegate.revision != revision || oldDelegate.samples != samples;
}
