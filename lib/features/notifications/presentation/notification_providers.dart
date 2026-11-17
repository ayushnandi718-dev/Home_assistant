import 'dart:async';
import 'dart:math';

import 'package:aura_hub/core/config/aura_runtime_config.dart';
import 'package:aura_hub/features/notifications/data/notification_store.dart';
import 'package:aura_hub/features/notifications/domain/aura_notification.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Application-wide notification centre for a single workspace.
class NotificationCenter extends StateNotifier<List<AuraNotification>> {
  NotificationCenter(this._store) : super(const <AuraNotification>[]);

  final NotificationStore _store;

  Future<void> load() async => state = await _store.load();

  int get unreadCount =>
      state.where((AuraNotification item) => !item.isRead).length;

  List<AuraNotification> get recent => state.take(5).toList();

  /// Adds or replaces a notification. A stable [id] lets service transitions
  /// update one entry instead of filling history with duplicate warnings.
  String publish({
    String? id,
    required String title,
    required String body,
    required NotificationSeverity severity,
    required NotificationSource source,
  }) {
    final String notificationId = id ?? _nextId();
    final AuraNotification notification = AuraNotification(
      id: notificationId,
      title: title,
      body: body,
      severity: severity,
      source: source,
      timestamp: DateTime.now(),
    );
    state = <AuraNotification>[
      notification,
      ...state.where((AuraNotification item) => item.id != notificationId),
    ].take(AuraRuntimeConfig.maxNotifications).toList();
    _persist();
    return notificationId;
  }

  void markRead(String id) {
    state = state
        .map((AuraNotification item) =>
            item.id == id ? item.copyWith(isRead: true) : item)
        .toList();
    _persist();
  }

  void markAllRead() {
    state = state
        .map((AuraNotification item) => item.copyWith(isRead: true))
        .toList();
    _persist();
  }

  void dismiss(String id) {
    state = state
        .where((AuraNotification item) => item.id != id)
        .toList(growable: false);
    _persist();
  }

  void clear() {
    state = const <AuraNotification>[];
    _persist();
  }

  String _nextId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(65536).toRadixString(16)}';

  void _persist() => unawaited(_store.save(state));
}

/// One independent, persisted centre per workspace.
final StateNotifierProviderFamily<NotificationCenter, List<AuraNotification>,
        AuraProfile> notificationCenterForProvider =
    StateNotifierProvider.family<NotificationCenter, List<AuraNotification>,
        AuraProfile>((Ref ref, AuraProfile profile) {
  return NotificationCenter(
    NotificationStore(
      fileName: 'notifications_${profile.storageScope}.json',
    ),
  );
});

/// The centre for the currently active workspace.
final Provider<NotificationCenter> activeNotificationCenterProvider =
    Provider<NotificationCenter>((Ref ref) {
  final AuraProfile profile = ref.watch(activeProfileProvider);
  return ref.watch(notificationCenterForProvider(profile).notifier);
});

final Provider<List<AuraNotification>> activeNotificationsProvider =
    Provider<List<AuraNotification>>((Ref ref) {
  final AuraProfile profile = ref.watch(activeProfileProvider);
  return ref.watch(notificationCenterForProvider(profile));
});

final Provider<int> unreadNotificationCountProvider = Provider<int>((Ref ref) {
  return ref.watch(activeNotificationCenterProvider).unreadCount;
});
