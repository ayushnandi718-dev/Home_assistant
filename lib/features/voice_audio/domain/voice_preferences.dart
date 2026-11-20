import 'package:flutter/material.dart';

/// Languages exposed by the planned voice pipeline.
///
/// Automatic detection is intentionally absent: no speech recognition pipeline
/// exists in this build, so offering it would be a misleading claim.
enum VoiceLanguage { english, hindi, bengali }

extension VoiceLanguageX on VoiceLanguage {
  String get label => switch (this) {
        VoiceLanguage.english => 'English',
        VoiceLanguage.hindi => 'हिन्दी',
        VoiceLanguage.bengali => 'বাংলা',
      };

  String get preview => switch (this) {
        VoiceLanguage.english => 'AURA is ready.',
        VoiceLanguage.hindi => 'AURA तैयार है।',
        VoiceLanguage.bengali => 'AURA প্রস্তুত।',
      };
}

/// How much a spoken response should say.
enum VoiceVerbosity { concise, balanced, detailed }

extension VoiceVerbosityX on VoiceVerbosity {
  String get label => switch (this) {
        VoiceVerbosity.concise => 'Concise',
        VoiceVerbosity.balanced => 'Balanced',
        VoiceVerbosity.detailed => 'Detailed',
      };

  String detailFor(VoiceLanguage language) {
    final String base = language.preview;
    return switch (this) {
      VoiceVerbosity.concise => base,
      VoiceVerbosity.balanced => switch (language) {
          VoiceLanguage.english => '$base I can help with your home.',
          VoiceLanguage.hindi => '$base मैं आपके घर में मदद कर सकता हूँ।',
          VoiceLanguage.bengali => '$base আমি আপনার বাড়িতে সাহায্য করতে পারি।',
        },
      VoiceVerbosity.detailed => switch (language) {
          VoiceLanguage.english =>
            '$base I can help with your home. Say the wake phrase when a '
                'voice pipeline is available.',
          VoiceLanguage.hindi =>
            '$base मैं आपके घर में मदद कर सकता हूँ। जब वॉइस पाइपलाइन उपलब्ध होगी, '
                'तब वेक फ्रेज़ कहें।',
          VoiceLanguage.bengali =>
            '$base আমি আপনার বাড়িতে সাহায্য করতে পারি। ভয়েস পাইপলাইন উপলব্ধ হলে '
                'ওয়েক ফ্রেজ বলুন।',
        },
    };
  }
}

/// Playback speed preference for future generated speech.
enum VoiceSpeed { slow, normal, fast }

extension VoiceSpeedX on VoiceSpeed {
  String get label => switch (this) {
        VoiceSpeed.slow => 'Slow',
        VoiceSpeed.normal => 'Normal',
        VoiceSpeed.fast => 'Fast',
      };

  double get rate => switch (this) {
        VoiceSpeed.slow => 0.8,
        VoiceSpeed.normal => 1.0,
        VoiceSpeed.fast => 1.2,
      };
}

/// How AURA confirms a spoken request.
enum VoiceConfirmation { silent, brief, spoken }

extension VoiceConfirmationX on VoiceConfirmation {
  String get label => switch (this) {
        VoiceConfirmation.silent => 'No confirmation',
        VoiceConfirmation.brief => 'On-screen only',
        VoiceConfirmation.spoken => 'Spoken (requires hardware)',
      };
}

/// Configured output target. No path actually plays audio in this build.
enum AudioOutputPreference { computerSpeakers, auraPanel }

extension AudioOutputPreferenceX on AudioOutputPreference {
  String get label => switch (this) {
        AudioOutputPreference.computerSpeakers =>
          'This computer (not wired up)',
        AudioOutputPreference.auraPanel => 'AURA panel (requires hardware)',
      };
}

/// Visual feedback states for a voice interaction.
///
/// These are preview states only in this build: no audio capture exists to
/// drive idle → listening → processing transitions automatically.
enum ListeningFeedbackState { idle, listening, processing, success, error }

extension ListeningFeedbackStateX on ListeningFeedbackState {
  String get label => switch (this) {
        ListeningFeedbackState.idle => 'Idle',
        ListeningFeedbackState.listening => 'Listening',
        ListeningFeedbackState.processing => 'Processing',
        ListeningFeedbackState.success => 'Success',
        ListeningFeedbackState.error => 'Error',
      };

  IconData get icon => switch (this) {
        ListeningFeedbackState.idle => Icons.mic_off_outlined,
        ListeningFeedbackState.listening => Icons.mic_none_outlined,
        ListeningFeedbackState.processing => Icons.hourglass_top_rounded,
        ListeningFeedbackState.success => Icons.check_circle_outline_rounded,
        ListeningFeedbackState.error => Icons.error_outline_rounded,
      };
}

/// Schema validation failure for persisted voice preferences.
///
/// These are controlled load errors: callers must not silently treat an unknown
/// or invalid schema as current and must not overwrite the original file with
/// defaults automatically.
sealed class VoicePreferencesSchemaException implements Exception {
  const VoicePreferencesSchemaException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The file declares a newer schema than this build understands.
class UnsupportedFutureVoicePreferencesSchemaException
    extends VoicePreferencesSchemaException {
  const UnsupportedFutureVoicePreferencesSchemaException(this.version)
      : super('Unsupported voice preferences schema version: $version');
  final int version;
}

/// The file declares an invalid or unreadable schema version.
class InvalidVoicePreferencesSchemaException
    extends VoicePreferencesSchemaException {
  const InvalidVoicePreferencesSchemaException(Object? version)
      : super('Invalid voice preferences schema version: $version');
}

/// Profile-scoped Voice & Audio configuration.
///
/// Every field is configuration or local preview state. No field represents a
/// live microphone session, a paired Bluetooth device or an audio command.
class VoicePreferences {
  const VoicePreferences({
    this.wakePhraseEnabled = false,
    this.microphoneEnabled = false,
    this.language = VoiceLanguage.english,
    this.verbosity = VoiceVerbosity.balanced,
    this.speed = VoiceSpeed.normal,
    this.confirmation = VoiceConfirmation.brief,
    this.output = AudioOutputPreference.computerSpeakers,
    this.volume = 60,
  });

  static const String wakePhrase = 'Hey AURA';
  static const int minVolume = 0;
  static const int maxVolume = 100;
  static const int supportedSchemaVersion = 1;
  static const VoicePreferences defaults = VoicePreferences();

  final bool wakePhraseEnabled;
  final bool microphoneEnabled;
  final VoiceLanguage language;
  final VoiceVerbosity verbosity;
  final VoiceSpeed speed;
  final VoiceConfirmation confirmation;
  final AudioOutputPreference output;
  final int volume;

  String get responsePreview => verbosity.detailFor(language);

  /// True only when both local preferences are on. Even then, no capture or
  /// detection is running; this describes intent, not capability.
  bool get voiceInputRequested => wakePhraseEnabled && microphoneEnabled;

  VoicePreferences copyWith({
    bool? wakePhraseEnabled,
    bool? microphoneEnabled,
    VoiceLanguage? language,
    VoiceVerbosity? verbosity,
    VoiceSpeed? speed,
    VoiceConfirmation? confirmation,
    AudioOutputPreference? output,
    int? volume,
  }) =>
      VoicePreferences(
        wakePhraseEnabled: wakePhraseEnabled ?? this.wakePhraseEnabled,
        microphoneEnabled: microphoneEnabled ?? this.microphoneEnabled,
        language: language ?? this.language,
        verbosity: verbosity ?? this.verbosity,
        speed: speed ?? this.speed,
        confirmation: confirmation ?? this.confirmation,
        output: output ?? this.output,
        volume: clampVolume(volume ?? this.volume),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': supportedSchemaVersion,
        'wakePhraseEnabled': wakePhraseEnabled,
        'microphoneEnabled': microphoneEnabled,
        'language': language.name,
        'verbosity': verbosity.name,
        'speed': speed.name,
        'confirmation': confirmation.name,
        'output': output.name,
        'volume': volume,
      };

  factory VoicePreferences.fromJson(Object? decoded) {
    if (decoded is! Map) return defaults;
    final Map<Object?, Object?> map = Map<Object?, Object?>.from(decoded);

    // Schema version policy:
    // - missing key: legacy v1 data (backward compatible)
    // - 1: current
    // - integer > 1: unsupported future schema (controlled error, preserve file)
    // - null/string/negative/zero/other types: invalid schema (controlled error)
    if (map.containsKey('version')) {
      final Object? rawVersion = map['version'];
      if (rawVersion is! int) {
        throw InvalidVoicePreferencesSchemaException(rawVersion);
      }
      if (rawVersion == supportedSchemaVersion) {
        // current
      } else if (rawVersion > supportedSchemaVersion) {
        throw UnsupportedFutureVoicePreferencesSchemaException(rawVersion);
      } else {
        throw InvalidVoicePreferencesSchemaException(rawVersion);
      }
    }

    return VoicePreferences(
      wakePhraseEnabled: map['wakePhraseEnabled'] == true,
      microphoneEnabled: map['microphoneEnabled'] == true,
      language: _enumByName<VoiceLanguage>(
          VoiceLanguage.values, map['language'], defaults.language),
      verbosity: _enumByName<VoiceVerbosity>(
          VoiceVerbosity.values, map['verbosity'], defaults.verbosity),
      speed: _enumByName<VoiceSpeed>(
          VoiceSpeed.values, map['speed'], defaults.speed),
      confirmation: _enumByName<VoiceConfirmation>(
          VoiceConfirmation.values, map['confirmation'], defaults.confirmation),
      output: _enumByName<AudioOutputPreference>(
          AudioOutputPreference.values, map['output'], defaults.output),
      volume: clampVolume(map['volume'], fallback: defaults.volume),
    );
  }

  static int clampVolume(Object? value, {int fallback = 60}) {
    if (value is int) return value.clamp(minVolume, maxVolume);
    if (value is num) return value.round().clamp(minVolume, maxVolume);
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
      other is VoicePreferences &&
          other.wakePhraseEnabled == wakePhraseEnabled &&
          other.microphoneEnabled == microphoneEnabled &&
          other.language == language &&
          other.verbosity == verbosity &&
          other.speed == speed &&
          other.confirmation == confirmation &&
          other.output == output &&
          other.volume == volume;

  @override
  int get hashCode => Object.hash(
        wakePhraseEnabled,
        microphoneEnabled,
        language,
        verbosity,
        speed,
        confirmation,
        output,
        volume,
      );
}
