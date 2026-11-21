import 'dart:async';

import 'package:aura_hub/features/dashboard/presentation/widgets/aura_tile.dart';
import 'package:aura_hub/features/display/presentation/display_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Formats the live tile with the platform's 12/24-hour preference.
String formatMobileClock(DateTime now, {required bool use24Hour}) =>
    DateFormat(use24Hour ? 'HH:mm' : 'h:mm a', 'en_US').format(now);

/// A self-contained one-second clock. Only this tile rebuilds on each tick;
/// the surrounding Dashboard is never torn down.
class MobileTimeTile extends ConsumerStatefulWidget {
  const MobileTimeTile({super.key});

  @override
  ConsumerState<MobileTimeTile> createState() => _MobileTimeTileState();
}

class _MobileTimeTileState extends ConsumerState<MobileTimeTile>
    with WidgetsBindingObserver {
  static const Key tileKey = ValueKey<String>('time-tile');

  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = ref.read(displayClockProvider).nowDeviceLocal();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 1), _tick);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _tick(null);
  }

  void _tick(Timer? timer) {
    if (!mounted) return;
    final DateTime next = ref.read(displayClockProvider).nowDeviceLocal();
    if (next == _now) return;
    setState(() => _now = next);
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    return SizedBox(
      key: tileKey,
      width: double.infinity,
      child: AuraTile(
        icon: Icons.schedule_rounded,
        accent: const Color(0xFFB69CFF),
        label: DateFormat('EEEE', 'en_US').format(_now),
        value: formatMobileClock(_now, use24Hour: use24Hour),
        sub: DateFormat('d MMM', 'en_US').format(_now),
        height: 152,
      ),
    );
  }
}
