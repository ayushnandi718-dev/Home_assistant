import 'package:aura_hub/core/constants/app_info.dart';

/// Central runtime configuration shared by the AURA Core services.
///
/// Values here are code-level policy, not user preferences. User-editable
/// preferences live in [AppSettingsStore](lib/core/settings/app_settings_store.dart).
abstract final class AuraRuntimeConfig {
  /// Version label shown in diagnostics and the About section.
  static String get versionLabel => '${AppInfo.version}+${AppInfo.buildNumber}';

  /// Bounded so a long-running desktop app cannot grow memory without limit.
  static const int maxLogEntries = 200;
  static const int maxNotifications = 200;
  static const int maxConversationMessages = 200;

  /// How often the app-wide service health monitor probes the local API while
  /// the application is active. This is independent of dashboard visibility.
  static const Duration serviceHealthInterval = Duration(seconds: 30);

  /// Set by main() only. Keeps background timers out of widget tests, where a
  /// real network probe would make tests flaky.
  static bool backgroundServicesEnabled = false;
}
