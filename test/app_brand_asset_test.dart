import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

ui.Size _pngSize(File file) {
  final ByteData bytes = ByteData.sublistView(file.readAsBytesSync());
  expect(bytes.getUint32(0), 0x89504e47, reason: '${file.path} is not a PNG');
  return ui.Size(
      bytes.getUint32(16).toDouble(), bytes.getUint32(20).toDouble());
}

void main() {
  test('AURA brand artwork is bundled and declared', () {
    final File source = File('android/app/app-remove-background.png');
    final File bundled = File('assets/images/aura_logo.png');
    final String pubspec = File('pubspec.yaml').readAsStringSync();

    expect(source.existsSync(), isTrue);
    expect(bundled.existsSync(), isTrue);
    expect(bundled.lengthSync(), greaterThan(0));
    expect(_pngSize(bundled).width, lessThanOrEqualTo(512));
    expect(pubspec, contains('    - assets/images/'));
  });

  test('launcher icons use the supplied artwork at every density', () {
    const Map<String, int> legacySizes = <String, int>{
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    };
    const Map<String, int> foregroundSizes = <String, int>{
      'mdpi': 108,
      'hdpi': 162,
      'xhdpi': 216,
      'xxhdpi': 324,
      'xxxhdpi': 432,
    };

    for (final MapEntry<String, int> density in legacySizes.entries) {
      final String folder = 'android/app/src/main/res/mipmap-${density.key}';
      for (final String name in <String>[
        'ic_launcher.png',
        'ic_launcher_round.png',
      ]) {
        final File icon = File('$folder/$name');
        expect(icon.existsSync(), isTrue, reason: icon.path);
        expect(_pngSize(icon).width, density.value);
        expect(_pngSize(icon).height, density.value);
      }

      final File foreground = File('$folder/ic_launcher_foreground.png');
      expect(foreground.existsSync(), isTrue, reason: foreground.path);
      expect(
        _pngSize(foreground).width,
        foregroundSizes[density.key],
      );
      expect(
        _pngSize(foreground).height,
        foregroundSizes[density.key],
      );
    }

    for (final String name in <String>[
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml',
    ]) {
      expect(
        File(name).readAsStringSync(),
        contains('@mipmap/ic_launcher_foreground'),
      );
    }
  });
}
