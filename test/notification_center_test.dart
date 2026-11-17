import 'dart:convert';
import 'dart:io';

import 'package:aura_hub/features/notifications/data/notification_store.dart';
import 'package:aura_hub/features/notifications/domain/aura_notification.dart';
import 'package:aura_hub/features/notifications/presentation/notification_providers.dart';
import 'package:flutter_test/flutter_test.dart';

AuraNotification _notification({
  required String id,
  bool isRead = false,
  DateTime? timestamp,
}) =>
    AuraNotification(
      id: id,
      title: 'Title $id',
      body: 'Body $id',
      severity: NotificationSeverity.warning,
      source: NotificationSource.api,
      timestamp: timestamp ?? DateTime(2026, 1, 1, 12),
      isRead: isRead,
    );

void main() {
  group('NotificationCenter', () {
    late Directory directory;
    late NotificationStore store;
    late NotificationCenter center;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('aura_notify_test_');
      store = NotificationStore(directory: directory);
      center = NotificationCenter(store);
    });

    tearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    test('starts empty', () {
      expect(center.state, isEmpty);
      expect(center.unreadCount, 0);
      expect(center.recent, isEmpty);
    });

    test('publish adds newest first and tracks unread', () {
      final String first = center.publish(
        title: 'Offline',
        body: 'API unreachable',
        severity: NotificationSeverity.error,
        source: NotificationSource.api,
      );
      center.publish(
        title: 'Online',
        body: 'Recovered',
        severity: NotificationSeverity.success,
        source: NotificationSource.api,
      );

      expect(center.state.length, 2);
      expect(center.state.first.title, 'Online');
      expect(center.unreadCount, 2);
      expect(center.recent.length, 2);

      center.markRead(first);
      expect(center.unreadCount, 1);
      center.markAllRead();
      expect(center.unreadCount, 0);
    });

    test('stable id updates one entry instead of duplicating', () {
      center.publish(
        id: 'api-availability',
        title: 'Offline',
        body: 'First',
        severity: NotificationSeverity.error,
        source: NotificationSource.api,
      );
      center.publish(
        id: 'api-availability',
        title: 'Online',
        body: 'Second',
        severity: NotificationSeverity.success,
        source: NotificationSource.api,
      );

      expect(center.state.length, 1);
      expect(center.state.single.title, 'Online');
      expect(center.state.single.body, 'Second');
    });

    test('dismiss and clear remove entries', () {
      final String id = center.publish(
        title: 'Notice',
        body: 'Body',
        severity: NotificationSeverity.info,
        source: NotificationSource.system,
      );
      expect(center.state.length, 1);
      center.dismiss(id);
      expect(center.state, isEmpty);

      center.publish(
        title: 'Other',
        body: 'Body',
        severity: NotificationSeverity.info,
        source: NotificationSource.system,
      );
      center.clear();
      expect(center.state, isEmpty);
    });
  });

  group('NotificationStore', () {
    late Directory directory;

    setUp(() {
      directory =
          Directory.systemTemp.createTempSync('aura_notify_store_test_');
    });

    tearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    test('round trips notifications in newest-first order', () async {
      final NotificationStore store = NotificationStore(directory: directory);
      final List<AuraNotification> input = <AuraNotification>[
        _notification(id: 'old', timestamp: DateTime(2026, 1, 1)),
        _notification(id: 'new', timestamp: DateTime(2026, 2, 1)),
      ];
      await store.save(input);

      final List<AuraNotification> loaded =
          await NotificationStore(directory: directory).load();
      expect(loaded.length, 2);
      expect(loaded.first.id, 'new');
      expect(loaded.last.isRead, isFalse);
    });

    test('deduplicates ids and skips malformed records', () async {
      final NotificationStore store = NotificationStore(directory: directory);
      final Map<String, dynamic> broken = <String, dynamic>{
        'title': 'No id',
        'body': 'Should be skipped',
      };
      final Map<String, dynamic> duplicate = _notification(id: 'same').toJson();
      final File file = File(
        '${directory.path}${Platform.pathSeparator}notifications.json',
      );
      await file.writeAsString(
        jsonEncode(<dynamic>[broken, duplicate, duplicate]),
      );

      final List<AuraNotification> loaded = await store.load();
      expect(loaded.length, 1);
      expect(loaded.single.id, 'same');
    });

    test('per-profile files are independent', () async {
      final NotificationStore ayush = NotificationStore(
        directory: directory,
        fileName: 'notifications_ayush.json',
      );
      final NotificationStore family = NotificationStore(
        directory: directory,
        fileName: 'notifications_family.json',
      );

      await ayush.save(<AuraNotification>[_notification(id: 'private')]);
      expect(await family.load(), isEmpty);
      expect((await ayush.load()).single.id, 'private');
    });

    test('corrupt file loads an empty list', () async {
      final NotificationStore store = NotificationStore(directory: directory);
      final File file = File(
        '${directory.path}${Platform.pathSeparator}notifications.json',
      );
      await file.writeAsString('{broken');
      expect(await store.load(), isEmpty);
    });
  });
}
