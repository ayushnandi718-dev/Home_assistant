import 'package:flutter/material.dart';

/// Decorative layer painted over a panel wallpaper gradient.
///
/// Patterns are drawn by Flutter; no image asset or download is involved.
enum WallpaperPattern { none, dots, rays, grid }

/// Panel wallpaper choices used by the local preview.
///
/// These are painted by Flutter; no image file, download or device sync is
/// involved. The selected value is persisted per workspace for a future panel
/// renderer to consume through the device transport seam.
enum PanelWallpaper {
  aurora,
  dusk,
  slate,
  midnight,
  sunrise,
  ocean,
  forest,
  neon,
}

extension PanelWallpaperX on PanelWallpaper {
  String get label => switch (this) {
        PanelWallpaper.aurora => 'Aurora',
        PanelWallpaper.dusk => 'Dusk',
        PanelWallpaper.slate => 'Slate',
        PanelWallpaper.midnight => 'Midnight',
        PanelWallpaper.sunrise => 'Sunrise',
        PanelWallpaper.ocean => 'Ocean',
        PanelWallpaper.forest => 'Forest',
        PanelWallpaper.neon => 'Neon',
      };

  List<Color> get gradient => switch (this) {
        PanelWallpaper.aurora => const <Color>[
            Color(0xFF152642),
            Color(0xFF2D2350)
          ],
        PanelWallpaper.dusk => const <Color>[
            Color(0xFF3A2038),
            Color(0xFF202A46)
          ],
        PanelWallpaper.slate => const <Color>[
            Color(0xFF1C2733),
            Color(0xFF27313D)
          ],
        PanelWallpaper.midnight => const <Color>[
            Color(0xFF0C1320),
            Color(0xFF16233A)
          ],
        PanelWallpaper.sunrise => const <Color>[
            Color(0xFF5A2E3F),
            Color(0xFFB25B4B)
          ],
        PanelWallpaper.ocean => const <Color>[
            Color(0xFF06344A),
            Color(0xFF116B7A)
          ],
        PanelWallpaper.forest => const <Color>[
            Color(0xFF13342B),
            Color(0xFF2F5D43)
          ],
        PanelWallpaper.neon => const <Color>[
            Color(0xFF241044),
            Color(0xFF5B1B67)
          ],
      };

  WallpaperPattern get pattern => switch (this) {
        PanelWallpaper.aurora => WallpaperPattern.rays,
        PanelWallpaper.dusk => WallpaperPattern.none,
        PanelWallpaper.slate => WallpaperPattern.grid,
        PanelWallpaper.midnight => WallpaperPattern.dots,
        PanelWallpaper.sunrise => WallpaperPattern.rays,
        PanelWallpaper.ocean => WallpaperPattern.dots,
        PanelWallpaper.forest => WallpaperPattern.grid,
        PanelWallpaper.neon => WallpaperPattern.rays,
      };
}

/// Accent styling for the local panel preview.
///
/// This is deliberately separate from [AuraThemeMode], which is the real,
/// app-wide theme in [AppSettings]. Changing the application theme continues to
/// go through the single existing settings store; this value only styles the
/// simulated panel surface.
enum PanelTheme { aura, violet, mono, ember, mint, sunset }

extension PanelThemeX on PanelTheme {
  String get label => switch (this) {
        PanelTheme.aura => 'Aura blue',
        PanelTheme.violet => 'Violet',
        PanelTheme.mono => 'Mono',
        PanelTheme.ember => 'Ember',
        PanelTheme.mint => 'Mint',
        PanelTheme.sunset => 'Sunset',
      };

  Color get accent => switch (this) {
        PanelTheme.aura => const Color(0xFF78AFFF),
        PanelTheme.violet => const Color(0xFF9B8CFF),
        PanelTheme.mono => const Color(0xFFD3DEEC),
        PanelTheme.ember => const Color(0xFFFF9A6B),
        PanelTheme.mint => const Color(0xFF6FE3B0),
        PanelTheme.sunset => const Color(0xFFFFB36B),
      };
}

/// Clock rendering used by the local panel preview.
enum ClockStyle {
  analog,
  digital,
  minimal,
  roman,
  segment,
  ring,
  flip,
}

extension ClockStyleX on ClockStyle {
  String get label => switch (this) {
        ClockStyle.analog => 'Analog',
        ClockStyle.digital => 'Digital',
        ClockStyle.minimal => 'Minimal',
        ClockStyle.roman => 'Roman',
        ClockStyle.segment => 'Segment',
        ClockStyle.ring => 'Ring',
        ClockStyle.flip => 'Flip',
      };
}

/// Decorative frame drawn around the selected clock in the local preview.
///
/// This is a watch-face treatment only: it sits between the wallpaper and the
/// clock renderer and is persisted per workspace for a future panel renderer.
enum PanelWatchFace { classic, sport, pulse, outline }

extension PanelWatchFaceX on PanelWatchFace {
  String get label => switch (this) {
        PanelWatchFace.classic => 'Classic',
        PanelWatchFace.sport => 'Sport',
        PanelWatchFace.pulse => 'Pulse',
        PanelWatchFace.outline => 'Outline',
      };
}

/// Orientation of the simulated panel surface.
///
/// Saved as configuration only: rotating a physical ESP32 panel requires a real
/// device transport, which does not exist in this build.
enum PanelOrientation { portrait, landscape }

extension PanelOrientationX on PanelOrientation {
  String get label => switch (this) {
        PanelOrientation.portrait => 'Portrait',
        PanelOrientation.landscape => 'Landscape',
      };
}

/// Screen timeout options offered for panel configuration.
enum ScreenTimeout {
  never,
  seconds30,
  minutes1,
  minutes5,
  minutes10,
}

extension ScreenTimeoutX on ScreenTimeout {
  String get label => switch (this) {
        ScreenTimeout.never => 'Never',
        ScreenTimeout.seconds30 => '30 seconds',
        ScreenTimeout.minutes1 => '1 minute',
        ScreenTimeout.minutes5 => '5 minutes',
        ScreenTimeout.minutes10 => '10 minutes',
      };

  Duration? get duration => switch (this) {
        ScreenTimeout.never => null,
        ScreenTimeout.seconds30 => const Duration(seconds: 30),
        ScreenTimeout.minutes1 => const Duration(minutes: 1),
        ScreenTimeout.minutes5 => const Duration(minutes: 5),
        ScreenTimeout.minutes10 => const Duration(minutes: 10),
      };
}

/// Nightly dim/sleep window stored as minutes from midnight.
///
/// Values are validated on load so a hand-edited file can never produce an
/// invalid time. The window is configuration only until a device transport can
/// apply it to the physical panel.
class SleepSchedule {
  const SleepSchedule({
    this.enabled = false,
    this.startMinutes = 1320,
    this.endMinutes = 360,
  });

  static const int defaultStartMinutes = 1320;
  static const int defaultEndMinutes = 360;

  final bool enabled;
  final int startMinutes;
  final int endMinutes;

  String get startLabel => formatMinutes(startMinutes);
  String get endLabel => formatMinutes(endMinutes);

  String get summary => enabled
      ? '$startLabel – $endLabel'
      : 'Off (start $startLabel, end $endLabel)';

  SleepSchedule copyWith({
    bool? enabled,
    int? startMinutes,
    int? endMinutes,
  }) =>
      SleepSchedule(
        enabled: enabled ?? this.enabled,
        startMinutes: normalizeMinutes(startMinutes ?? this.startMinutes),
        endMinutes: normalizeMinutes(endMinutes ?? this.endMinutes),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'enabled': enabled,
        'startMinutes': startMinutes,
        'endMinutes': endMinutes,
      };

  factory SleepSchedule.fromJson(Object? decoded) {
    if (decoded is! Map<String, dynamic>) return const SleepSchedule();
    return SleepSchedule(
      enabled: decoded['enabled'] == true,
      startMinutes: normalizeMinutes(decoded['startMinutes'],
          fallback: defaultStartMinutes),
      endMinutes:
          normalizeMinutes(decoded['endMinutes'], fallback: defaultEndMinutes),
    );
  }

  /// Normalizes a sleep-minute value to the UI-supported 30-minute increments.
  ///
  /// Policy: accept numeric values, clamp to [0, 1410], then round to the
  /// nearest 30-minute step (0, 30, ..., 1410). Missing/invalid values use the
  /// normalized fallback so dropdowns always receive a selectable value.
  static int normalizeMinutes(Object? value, {int fallback = 0}) {
    final int? raw = _coerceInt(value);
    if (raw == null) return _normalizeStep(fallback);
    return _normalizeStep(raw);
  }

  static int _normalizeStep(int value) {
    final int clamped = value.clamp(0, 1410);
    final int step = ((clamped + 15) ~/ 30) * 30;
    return step.clamp(0, 1410);
  }

  static int? _coerceInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return null;
  }

  static String formatMinutes(int minutes) {
    final int normalized = normalizeMinutes(minutes);
    final String hour = (normalized ~/ 60).toString().padLeft(2, '0');
    final String minute = (normalized % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SleepSchedule &&
          other.enabled == enabled &&
          other.startMinutes == startMinutes &&
          other.endMinutes == endMinutes;

  @override
  int get hashCode => Object.hash(enabled, startMinutes, endMinutes);
}

/// Profile-scoped Display Studio configuration.
///
/// Nothing here is a command: every control changes either the local preview or
/// a saved preference. Hardware-dependent values are consumed only when a real
/// AURA device transport exists.
class DisplayPreferences {
  const DisplayPreferences({
    this.brightness = 70,
    this.screenTimeout = ScreenTimeout.minutes5,
    this.sleepSchedule = const SleepSchedule(),
    this.panelTheme = PanelTheme.aura,
    this.wallpaper = PanelWallpaper.aurora,
    this.clockStyle = ClockStyle.digital,
    this.watchFace = PanelWatchFace.classic,
    this.orientation = PanelOrientation.portrait,
  });

  static const int minBrightness = 10;
  static const int maxBrightness = 100;
  static const DisplayPreferences defaults = DisplayPreferences();

  final int brightness;
  final ScreenTimeout screenTimeout;
  final SleepSchedule sleepSchedule;
  final PanelTheme panelTheme;
  final PanelWallpaper wallpaper;
  final ClockStyle clockStyle;
  final PanelWatchFace watchFace;
  final PanelOrientation orientation;

  /// Opacity of the simulated panel fill. Keeps the preview legible at the
  /// lowest setting while still making the slider's effect visible.
  double get previewDim =>
      1.0 -
      (0.55 * (maxBrightness - brightness) / (maxBrightness - minBrightness));

  DisplayPreferences copyWith({
    int? brightness,
    ScreenTimeout? screenTimeout,
    SleepSchedule? sleepSchedule,
    PanelTheme? panelTheme,
    PanelWallpaper? wallpaper,
    ClockStyle? clockStyle,
    PanelWatchFace? watchFace,
    PanelOrientation? orientation,
  }) =>
      DisplayPreferences(
        brightness: clampBrightness(brightness ?? this.brightness),
        screenTimeout: screenTimeout ?? this.screenTimeout,
        sleepSchedule: sleepSchedule ?? this.sleepSchedule,
        panelTheme: panelTheme ?? this.panelTheme,
        wallpaper: wallpaper ?? this.wallpaper,
        clockStyle: clockStyle ?? this.clockStyle,
        watchFace: watchFace ?? this.watchFace,
        orientation: orientation ?? this.orientation,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': 1,
        'brightness': brightness,
        'screenTimeout': screenTimeout.name,
        'sleepSchedule': sleepSchedule.toJson(),
        'panelTheme': panelTheme.name,
        'wallpaper': wallpaper.name,
        'clockStyle': clockStyle.name,
        'watchFace': watchFace.name,
        'orientation': orientation.name,
      };

  factory DisplayPreferences.fromJson(Object? decoded) {
    if (decoded is! Map<String, dynamic>) return defaults;
    return DisplayPreferences(
      brightness:
          clampBrightness(decoded['brightness'], fallback: defaults.brightness),
      screenTimeout: _enumByName<ScreenTimeout>(ScreenTimeout.values,
          decoded['screenTimeout'], defaults.screenTimeout),
      sleepSchedule: SleepSchedule.fromJson(decoded['sleepSchedule']),
      panelTheme: _enumByName<PanelTheme>(
          PanelTheme.values, decoded['panelTheme'], defaults.panelTheme),
      wallpaper: _enumByName<PanelWallpaper>(
          PanelWallpaper.values, decoded['wallpaper'], defaults.wallpaper),
      clockStyle: _enumByName<ClockStyle>(
          ClockStyle.values, decoded['clockStyle'], defaults.clockStyle),
      watchFace: _enumByName<PanelWatchFace>(
          PanelWatchFace.values, decoded['watchFace'], defaults.watchFace),
      orientation: _enumByName<PanelOrientation>(PanelOrientation.values,
          decoded['orientation'], defaults.orientation),
    );
  }

  static int clampBrightness(Object? value, {int fallback = 70}) {
    if (value is int) {
      return value.clamp(minBrightness, maxBrightness);
    }
    if (value is num) {
      return value.round().clamp(minBrightness, maxBrightness);
    }
    return fallback;
  }

  static T _enumByName<T extends Enum>(
    Iterable<T> values,
    Object? name,
    T fallback,
  ) {
    if (name is! String) return fallback;
    for (final T value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DisplayPreferences &&
          other.brightness == brightness &&
          other.screenTimeout == screenTimeout &&
          other.sleepSchedule == sleepSchedule &&
          other.panelTheme == panelTheme &&
          other.wallpaper == wallpaper &&
          other.clockStyle == clockStyle &&
          other.watchFace == watchFace &&
          other.orientation == orientation;

  @override
  int get hashCode => Object.hash(
        brightness,
        screenTimeout,
        sleepSchedule,
        panelTheme,
        wallpaper,
        clockStyle,
        watchFace,
        orientation,
      );
}
