import 'package:aura_hub/core/settings/app_settings.dart';
import 'package:aura_hub/core/settings/app_settings_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final StateNotifierProvider<AppSettingsController, AppSettings>
    appSettingsProvider =
    StateNotifierProvider<AppSettingsController, AppSettings>(
  (Ref ref) => AppSettingsController(),
);
