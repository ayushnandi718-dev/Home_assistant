/// Quick actions exposed as scene pills on the mobile Dashboard.
///
/// Every one of these needs a paired, connected panel and a real
/// acknowledgement before any success state can be shown.
enum SceneAction { nightMode, nextWallpaper, syncNow, restartPanel }

extension SceneActionLabel on SceneAction {
  String get label => switch (this) {
        SceneAction.nightMode => 'Night mode',
        SceneAction.nextWallpaper => 'Next wallpaper',
        SceneAction.syncNow => 'Sync now',
        SceneAction.restartPanel => 'Restart panel',
      };
}
