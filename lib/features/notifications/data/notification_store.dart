import 'dart:convert';
import 'package:aura_hub/core/platform/io_compat.dart';

import 'package:aura_hub/core/config/aura_runtime_config.dart';
import 'package:aura_hub/core/utilities/local_paths.dart';
import 'package:aura_hub/features/notifications/domain/aura_notification.dart';

/// Persists notifications per workspace so private and shared notifications
/// never share a file.
class NotificationStore {
  NotificationStore(
      {Directory? directory, String fileName = 'notifications.json'})
      : _file = File(
          '${(directory ?? LocalPaths.appData()).path}${Platform.pathSeparator}$fileName',
        );

  final File _file;

  Future<List<AuraNotification>> load() async {
    try {
      if (!await _file.exists()) return const <AuraNotification>[];
      final Object? decoded = jsonDecode(await _file.readAsString());
      if (decoded is! List<dynamic>) return const <AuraNotification>[];
      final List<AuraNotification> result = <AuraNotification>[];
      final Set<String> seenIds = <String>{};
      for (final Object? item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        try {
          final AuraNotification notification = AuraNotification.fromJson(item);
          if (seenIds.add(notification.id)) result.add(notification);
        } on FormatException {
          // Skip a malformed record without losing the rest of the history.
          continue;
        }
      }
      result.sort((AuraNotification a, AuraNotification b) =>
          b.timestamp.compareTo(a.timestamp));
      return result.take(AuraRuntimeConfig.maxNotifications).toList();
    } catch (_) {
      return const <AuraNotification>[];
    }
  }

  Future<void> save(List<AuraNotification> notifications) async {
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(
        jsonEncode(
          notifications
              .take(AuraRuntimeConfig.maxNotifications)
              .map((AuraNotification item) => item.toJson())
              .toList(),
        ),
        flush: true,
      );
    } catch (_) {
      // A failed write must never break the running app. The in-memory centre
      // stays usable and the next mutation retries the save.
    }
  }
}
