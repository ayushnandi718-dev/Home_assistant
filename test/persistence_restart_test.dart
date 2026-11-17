import 'dart:io';

import 'package:aura_hub/core/settings/app_settings.dart';
import 'package:aura_hub/core/settings/app_settings_store.dart';
import 'package:aura_hub/features/dashboard/data/dashboard_layout_store.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_layout.dart';
import 'package:aura_hub/features/notifications/data/notification_store.dart';
import 'package:aura_hub/features/notifications/domain/aura_notification.dart';
import 'package:aura_hub/features/profiles/data/profile_pin_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Simulates a full app restart: every store is recreated from the same on-disk
/// directory with no shared in-memory state, mirroring `main()` constructing
/// fresh controllers on launch.
void main() {
  group('persistence across an app restart', () {
    late Directory appData;

    setUp(() {
      appData = Directory.systemTemp.createTempSync('aura_restart_test_');
    });

    tearDown(() {
      if (appData.existsSync()) appData.deleteSync(recursive: true);
    });

    test('settings, layout, per-profile notifications and PIN survive',
        () async {
      // ---- Session A: user changes everything, then closes the app. ----
      final AppSettings chosen = AppSettings.defaults.copyWith(
        apiBaseUrl: 'http://localhost:9000',
        pollingIntervalSeconds: 5,
        historyRetentionMinutes: 60,
        reduceMotion: true,
        density: AuraDensity.compact,
      );
      await AppSettingsStore(directory: appData).save(chosen);

      final DashboardLayout layout = DashboardLayout.defaults
          .toggle(DashboardWidgetId.activity)
          .reorder(0, 3);
      await DashboardLayoutStore(directory: appData).save(layout);

      final AuraNotification privateNote = AuraNotification(
        id: 'private-note',
        title: 'Private event',
        body: 'AYUSH-only history',
        severity: NotificationSeverity.warning,
        source: NotificationSource.profile,
        timestamp: DateTime(2026, 11, 17, 9),
        isRead: true,
      );
      final AuraNotification sharedNote = AuraNotification(
        id: 'shared-note',
        title: 'Shared event',
        body: 'FAMILY-only history',
        severity: NotificationSeverity.info,
        source: NotificationSource.api,
        timestamp: DateTime(2026, 11, 17, 10),
      );
      await NotificationStore(
        directory: appData,
        fileName: 'notifications_ayush.json',
      ).save(<AuraNotification>[privateNote]);
      await NotificationStore(
        directory: appData,
        fileName: 'notifications_family.json',
      ).save(<AuraNotification>[sharedNote]);

      await ProfilePinStore(directory: appData).setPin('4821');

      // ---- Session B: fresh stores read the same files, like a restart. ----
      final AppSettings reloadedSettings =
          await AppSettingsStore(directory: appData).load();
      expect(reloadedSettings, chosen);

      final DashboardLayout reloadedLayout =
          await DashboardLayoutStore(directory: appData).load();
      expect(reloadedLayout, layout);

      final List<AuraNotification> reloadedPrivate = await NotificationStore(
        directory: appData,
        fileName: 'notifications_ayush.json',
      ).load();
      final List<AuraNotification> reloadedShared = await NotificationStore(
        directory: appData,
        fileName: 'notifications_family.json',
      ).load();
      expect(reloadedPrivate.single.id, 'private-note');
      expect(reloadedPrivate.single.isRead, isTrue);
      expect(reloadedShared.single.id, 'shared-note');
      expect(reloadedShared, isNot(reloadedPrivate));

      final ProfilePinStore reloadedPin = ProfilePinStore(directory: appData);
      expect(await reloadedPin.hasPin(), isTrue);
      expect(await reloadedPin.verify('4821'), isTrue);
      expect(await reloadedPin.verify('0000'), isFalse);
    });

    test('a private session is never restored after restart', () async {
      // The PIN verifier persists, but session state is in-memory only, so the
      // freshly constructed controller always starts in the shared workspace.
      await ProfilePinStore(directory: appData).setPin('1234');
      expect(await ProfilePinStore(directory: appData).verify('1234'), isTrue);
      // ProfileSession.initial is the only startup value (asserted in
      // profile_session_test.dart); no session file exists to reload.
      final bool sessionFileExists = File(
        '${appData.path}${Platform.pathSeparator}profile_session.json',
      ).existsSync();
      expect(sessionFileExists, isFalse);
    });
  });
}
