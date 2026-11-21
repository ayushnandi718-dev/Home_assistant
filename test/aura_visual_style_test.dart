import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_forui_theme.dart';
import 'package:aura_hub/core/theme/aura_palette.dart';
import 'package:aura_hub/core/theme/aura_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

void main() {
  test('violet palette is exposed through the Material theme', () {
    final ThemeData theme = auraTheme(visual: AuraPalette.violet);
    final AuraPaletteTheme? extension = theme.extension<AuraPaletteTheme>();

    expect(extension?.palette.id, AuraPalette.violet.id);
    expect(theme.colorScheme.primary, AuraPalette.violet.primary);
    expect(theme.scaffoldBackgroundColor, AuraPalette.violet.background);
    expect(theme.textTheme.bodyMedium?.color, AuraPalette.violet.textSecondary);
    expect(
        theme.textTheme.headlineLarge?.color, AuraPalette.violet.textPrimary);
  });

  test('midnight palette keeps the original AURA accents', () {
    final ThemeData theme = auraTheme();

    expect(
      theme.extension<AuraPaletteTheme>()?.palette.id,
      AuraPalette.midnight.id,
    );
    expect(theme.colorScheme.primary, AuraColors.primary);
    expect(theme.scaffoldBackgroundColor, AuraColors.background);
  });

  test('Forui navigation theme follows the active AURA palette', () {
    final FThemeData theme = auraForuiTheme(AuraPalette.violet);

    expect(theme.colors.primary, AuraPalette.violet.primary);
    expect(theme.colors.secondary, AuraPalette.violet.secondary);
    expect(theme.bottomNavigationBarStyle, isNotNull);
  });

  testWidgets('Forui bottom navigation renders AURA destinations',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FTheme(
          data: auraForuiTheme(AuraPalette.violet),
          child: Scaffold(
            body: FBottomNavigationBar(
              index: 0,
              onChange: (int index) {},
              children: const <FBottomNavigationBarItem>[
                FBottomNavigationBarItem(
                  icon: Icon(FLucideIcons.house),
                  label: Text('Home'),
                ),
                FBottomNavigationBarItem(
                  icon: Icon(FLucideIcons.cpu),
                  label: Text('Devices'),
                ),
                FBottomNavigationBarItem(
                  icon: Icon(FLucideIcons.ellipsis),
                  label: Text('More'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byType(FBottomNavigationBar), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Devices'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
