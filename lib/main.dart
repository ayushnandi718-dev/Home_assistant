import 'package:aura_hub/app/aura_app.dart';
import 'package:aura_hub/core/settings/app_settings_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load persisted preferences before the first frame so settings (API URL,
  // poll interval, accessibility) are correct from the start.
  final ProviderContainer container = ProviderContainer();
  await container.read(appSettingsProvider.notifier).load();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const AuraApp(),
    ),
  );
}
