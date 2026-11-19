import 'dart:async';

import 'package:aura_hub/app/router.dart';
import 'package:aura_hub/core/config/aura_runtime_config.dart';
import 'package:aura_hub/core/constants/app_info.dart';
import 'package:aura_hub/core/lifecycle/background_service.dart';
import 'package:aura_hub/core/settings/app_settings.dart';
import 'package:aura_hub/core/settings/app_settings_providers.dart';
import 'package:aura_hub/core/telemetry/telemetry_providers.dart';
import 'package:aura_hub/core/theme/aura_theme.dart';
import 'package:aura_hub/features/profiles/presentation/ayush_unlock_dialog.dart';
import 'package:aura_hub/features/security/presentation/auto_lock_controller.dart';
import 'package:aura_hub/features/startup/presentation/startup_providers.dart';
import 'package:aura_hub/shared/widgets/glass/glass_dialog.dart';
import 'package:aura_hub/features/system/presentation/service_health_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AuraApp extends ConsumerStatefulWidget {
  const AuraApp({super.key});

  @override
  ConsumerState<AuraApp> createState() => _AuraAppState();
}

class _AuraAppState extends ConsumerState<AuraApp> with WidgetsBindingObserver {
  late final GoRouter _router = createAppRouter();
  ServiceLifecycleManager? _lifecycle;

  late final KeyEventCallback _keyHandler;

  @override
  void initState() {
    super.initState();
    _keyHandler = (event) {
      if (mounted && (event is KeyDownEvent || event is KeyRepeatEvent)) {
        // Global keyboard handler: no focus required, and it is a no-op for
        // FAMILY inside the controller's private-session guard.
        ref.read(ayushAutoLockControllerProvider).registerActivity();
      }
      // Observation only: never consume the event from the real focus owner.
      return false;
    };
    // The observer is always registered: auto-lock needs resume notifications
    // even when background telemetry services are disabled (e.g. tests).
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_keyHandler);
    // In widget tests background services stay disabled, so no timer or real
    // network probe is created by simply rendering the app shell.
    if (AuraRuntimeConfig.backgroundServicesEnabled) {
      _lifecycle = ref.read(serviceLifecycleProvider);
      _lifecycle!.startAll();
    }
    // Minimize once the window exists. The service is a no-op off Windows and
    // when the preference is off.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final AppSettings settings = ref.read(appSettingsProvider);
      ref
          .read(startupServiceProvider)
          .minimizeIfRequested(settings.startMinimized);
      // A remembered AYUSH scope only opens the PIN prompt. It never restores
      // an authenticated session, so private content stays locked after a
      // restart until the user verifies their PIN.
      if (ref.read(shouldPromptAyushUnlockProvider)) {
        unawaited(showGlassDialog<bool>(
          context: context,
          width: 440,
          child: const AyushUnlockDialog(),
        ));
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_keyHandler);
    _lifecycle?.stopAll();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _lifecycle?.resumeAll();
        // Returning to the foreground counts as user interaction and restarts
        // the AYUSH inactivity countdown (no-op while FAMILY is active).
        ref.read(ayushAutoLockControllerProvider).onAppResumed();
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _lifecycle?.pauseAll();
      case AppLifecycleState.detached:
        _lifecycle?.pauseAll();
        // Best-effort early shutdown. The Windows job handle assigned to the
        // child process is the final guarantee if this callback is missed.
        unawaited(ref.read(telemetryApiServiceProvider.notifier).shutdown());
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings settings = ref.watch(appSettingsProvider);

    return MaterialApp.router(
      title: AppInfo.name,
      debugShowCheckedModeBanner: false,
      // `theme` is the light variant; `darkTheme` is selected by ThemeMode.dark
      // and by system-dark. Dark remains the default in AppSettings.defaults.
      theme: auraTheme(visualDensity: settings.visualDensity, light: true),
      darkTheme: auraTheme(visualDensity: settings.visualDensity),
      themeMode: settings.themeMode.themeMode,
      locale: settings.language.locale,
      supportedLocales: const <Locale>[
        Locale('en'),
        Locale('hi'),
        Locale('bn'),
      ],
      builder: (BuildContext context, Widget? child) {
        // The OS "reduce animations" setting is already honoured by AuraMotion;
        // this adds the in-app preference on top of it.
        final MediaQueryData query = MediaQuery.of(context);
        return MediaQuery(
          data: settings.reduceMotion
              ? query.copyWith(disableAnimations: true)
              : query,
          child: Listener(
            // Pointer-down is a deliberate interaction that resets the private
            // inactivity countdown. Mouse movement alone does not count.
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) =>
                ref.read(ayushAutoLockControllerProvider).registerActivity(),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      routerConfig: _router,
    );
  }
}
