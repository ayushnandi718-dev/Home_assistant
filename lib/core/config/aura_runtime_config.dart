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
  static const int maxAiConversations = 50;

  /// Conservative Phase 1 context budget. Provider-specific context windows are
  /// not configured yet; these values keep requests bounded until per-model
  /// limits are introduced. The estimator and budget are injectable in tests.
  static const int defaultAiContextTokens = 6000;
  static const int aiResponseReserveTokens = 512;
  static const int maxAiContextMessages = 20;

  /// Local-first memory limits. These are code-level safety bounds, not user
  /// preferences. They keep memory files small and stop a single record from
  /// consuming an entire provider request.
  static const int maxMemoryRecords = 200;
  static const int maxMemoryContentChars = 1200;
  static const int maxMemoryTags = 10;
  static const int maxMemoryTagChars = 40;
  static const int maxMemoryContextItems = 5;
  static const int maxMemoryContextTokens = 400;

  /// How often the app-wide service health monitor probes the local API while
  /// the application is active. This is independent of dashboard visibility.
  static const Duration serviceHealthInterval = Duration(seconds: 30);

  /// Set by main() only. Keeps background timers out of widget tests, where a
  /// real network probe would make tests flaky.
  static bool backgroundServicesEnabled = false;
}
