import 'package:aura_hub/app/router.dart';
import 'package:aura_hub/core/constants/app_info.dart';
import 'package:aura_hub/core/theme/aura_theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AuraApp extends StatefulWidget {
  const AuraApp({super.key});

  @override
  State<AuraApp> createState() => _AuraAppState();
}

class _AuraAppState extends State<AuraApp> {
  late final GoRouter _router = createAppRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: AppInfo.name,
      debugShowCheckedModeBanner: false,
      theme: auraTheme(),
      routerConfig: _router,
    );
  }
}
