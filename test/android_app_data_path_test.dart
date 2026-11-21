import 'dart:io';

import 'package:aura_hub/core/logging/aura_log.dart';
import 'package:aura_hub/core/utilities/local_paths.dart';
import 'package:aura_hub/features/profiles/data/profile_pin_store.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:flutter_test/flutter_test.dart';

/// The native Android channel cannot run on the host, so these tests inject the
/// same resolved directory and verify the shared persistence path end to end.
void main() {
  late Directory appData;

  setUp(() {
    appData = Directory.systemTemp.createTempSync('aura_android_app_data_');
    LocalPaths.setAppDataDirectoryForTesting(appData);
  });

  tearDown(() {
    LocalPaths.setAppDataDirectoryForTesting(null);
    if (appData.existsSync()) appData.deleteSync(recursive: true);
  });

  File pinFile() =>
      File('${appData.path}${Platform.pathSeparator}profile_pin.json');

  test('resolved platform directory replaces the portable fallback', () {
    expect(LocalPaths.appData().path, appData.path);
  });

  test(
    'default PIN store persists inside the resolved app-data directory',
    () async {
      final ProfilePinStore store = ProfilePinStore(iterations: 1000);

      await store.setPin('4821');

      expect(pinFile().existsSync(), isTrue);
      expect(await store.verify('4821'), isTrue);
    },
  );

  test(
    'AYUSH setup unlocks and persists with default storage resolution',
    () async {
      final ProfileSessionController controller = ProfileSessionController(
        store: ProfilePinStore(iterations: 1000),
        logger: AuraLogger(),
      );

      expect(await controller.setupPin('2468'), ProfileUnlockResult.success);
      expect(controller.state.profile, AuraProfile.ayush);
      expect(controller.state.privateSessionActive, isTrue);
      expect(pinFile().existsSync(), isTrue);
      expect(await controller.hasPin(), isTrue);
    },
  );
}
