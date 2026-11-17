import 'package:aura_hub/app/router.dart';
import 'package:aura_hub/core/constants/app_info.dart';
import 'package:aura_hub/core/settings/app_settings.dart';
import 'package:aura_hub/core/settings/app_settings_providers.dart';
import 'package:aura_hub/core/theme/aura_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AuraApp extends ConsumerStatefulWidget {
  const AuraApp({super.key});

  @override
  ConsumerState<AuraApp> createState() => _AuraAppState();
}

class _AuraAppState extends ConsumerState<AuraApp> {
  late final GoRouter _router = createAppRouter();

  @override
  Widget build(BuildContext context) {
    final AppSettings settings = ref.watch(appSettingsProvider);

    return MaterialApp.router(
      title: AppInfo.name,
      debugShowCheckedModeBanner: false,
      theme: auraTheme(visualDensity: settings.visualDensity),
      builder: (BuildContext context, Widget? child) {
        // The OS "reduce animations" setting is already honoured by AuraMotion;
        // this adds the in-app preference on top of it.
        final MediaQueryData query = MediaQuery.of(context);
        return MediaQuery(
          data: settings.reduceMotion
              ? query.copyWith(disableAnimations: true)
              : query,
          child: child ?? const SizedBox.shrink(),
        );
      },
      routerConfig: _router,
    );
  }
}
