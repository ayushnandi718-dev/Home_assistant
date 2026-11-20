import 'package:aura_hub/core/services/clock_service.dart';
import 'package:aura_hub/features/ai/data/ai_runtime_time_context.dart';
import 'package:aura_hub/features/ai/data/default_ai_context_assembler.dart';
import 'package:aura_hub/features/ai/domain/ai_context.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  SystemAuraClock.ensureZonesLoaded();

  final FixedAuraClock fixedClock = FixedAuraClock(
    DateTime.utc(2026, 1, 15, 10, 30),
    deviceTimeZoneName: 'Test device zone',
    deviceUtcOffset: Duration(hours: 1),
  );

  group('AiRuntimeTimeContext', () {
    test('matches positive time, date, timezone and conversion intents', () {
      const List<String> positives = <String>[
        'What time is it?',
        "What's the current time in India?",
        "What is today's date?",
        'What day is it today?',
        'What time is it in Tokyo?',
        'What is the local time in London?',
        'Convert 8 PM IST to New York time.',
        'How many hours until midnight?',
        'Is it morning in Kolkata?',
        'What is the current UTC offset?',
        "What time will it be in India when it's 9 AM in London?",
      ];
      for (final String prompt in positives) {
        expect(
          AiRuntimeTimeContext.isTimeRelated(prompt),
          isTrue,
          reason: prompt,
        );
      }

      // Existing supported time-related requests remain relevant.
      expect(AiRuntimeTimeContext.isTimeRelated("Today's date in Kolkata"),
          isTrue);
      expect(AiRuntimeTimeContext.isTimeRelated('What time is it in India?'),
          isTrue);
    });

    test('does not activate for ordinary prompts with broad tokens', () {
      const List<String> negatives = <String>[
        'I am learning Flutter.',
        'I am currently building a website.',
        'What is the current version of Flutter?',
        'Give me a summary now.',
        'Explain current electricity.',
        'Make a presentation about time management.',
        'Explain the current in an electrical circuit.',
        'Write a poem about the present moment.',
        'Explain gravity',
      ];
      for (final String prompt in negatives) {
        expect(
          AiRuntimeTimeContext.isTimeRelated(prompt),
          isFalse,
          reason: prompt,
        );
        expect(
          AiRuntimeTimeContext.instructionFor(prompt, clock: fixedClock),
          isNull,
          reason: prompt,
        );
      }
    });

    test('supplies authoritative India time from the injected clock', () {
      final String? instruction = AiRuntimeTimeContext.instructionFor(
        'What time is it in India?',
        clock: fixedClock,
      );

      expect(instruction, isNotNull);
      expect(instruction, contains('AUTHORITATIVE RUNTIME CLOCK'));
      expect(instruction, contains('UTC now: 2026-01-15T10:30:00.000Z'));
      expect(instruction, contains('Asia/Kolkata (IST, UTC+05:30)'));
      expect(instruction, contains('16:00'));
      expect(instruction, contains('Do not mention this clock context'));
    });

    test('uses another city zone when the user asks for it', () {
      final String? instruction = AiRuntimeTimeContext.instructionFor(
        'What is the time in London?',
        clock: fixedClock,
      );

      expect(instruction, contains('Requested location (Europe/London)'));
      expect(instruction, contains('10:30'));
      expect(instruction, contains('UTC+00:00'));
    });

    test('does not invent a time for an unresolvable location', () {
      final String? instruction = AiRuntimeTimeContext.instructionFor(
        'What time is it in Atlantis?',
        clock: _UnavailableZoneClock(
          DateTime.utc(2026, 1, 15, 10),
        ),
        resolver: const _AtlantisResolver(),
      );

      expect(instruction, isNotNull);
      expect(instruction, contains('Atlantis'));
      expect(instruction,
          contains('reliable timezone information is unavailable'));
      expect(instruction, contains('Do not invent a time'));
      expect(instruction, isNot(contains('Requested location (')));
    });
  });

  group('DefaultAiContextAssembler time integration', () {
    test('adds time context only to relevant assembled requests', () {
      final DefaultAiContextAssembler assembler =
          DefaultAiContextAssembler(clock: fixedClock);

      final AiAssembledContext timed = assembler.assemble(
        _request('What time is it in India?'),
      );
      final AiAssembledContext plain = assembler.assemble(
        _request('Write a short poem about rain.'),
      );
      final String timedInstructions = timed.systemInstructions.join('\n');
      final String plainInstructions = plain.systemInstructions.join('\n');

      expect(timedInstructions, contains('Asia/Kolkata'));
      expect(timedInstructions, contains('16:00'));
      expect(plainInstructions, isNot(contains('AUTHORITATIVE RUNTIME CLOCK')));
      expect(timed.estimatedTokens, greaterThan(plain.estimatedTokens));
    });

    test('reads the clock again for a second request', () {
      final _SteppingClock clock = _SteppingClock(
        DateTime.utc(2026, 1, 15, 10, 30),
      );
      final DefaultAiContextAssembler assembler =
          DefaultAiContextAssembler(clock: clock);

      final String first = assembler
          .assemble(_request('What time is it in India?'))
          .systemInstructions
          .join('\n');
      clock.advance(const Duration(hours: 2));
      final String second = assembler
          .assemble(_request('What time is it in India?'))
          .systemInstructions
          .join('\n');

      expect(first, contains('16:00'));
      expect(second, contains('18:00'));
      expect(second, isNot(first));
    });
  });
}

AiContextRequest _request(String prompt) {
  return AiContextRequest(
    profile: AuraProfile.ayush,
    historyProfile: AuraProfile.ayush,
    history: <AiMessage>[
      AiMessage(
        role: AiMessageRole.user,
        content: prompt,
        timestamp: DateTime.utc(2020),
      ),
    ],
  );
}

class _AtlantisResolver extends AuraCityTimeZoneResolver {
  const _AtlantisResolver();

  @override
  String? resolve(String locationName) =>
      locationName.trim().toLowerCase() == 'atlantis' ? 'Bad/Zone' : null;

  @override
  List<String> mentionedIn(String text) {
    final int index = text.toLowerCase().indexOf('atlantis');
    if (index == -1) return const <String>[];
    return <String>[text.substring(index, index + 'atlantis'.length)];
  }
}

class _UnavailableZoneClock extends FixedAuraClock {
  _UnavailableZoneClock(super.instantUtc);

  @override
  DateTime nowIn(String ianaIdentifier) {
    if (ianaIdentifier == 'Bad/Zone') {
      throw const AuraTimeZoneUnavailable('Bad/Zone');
    }
    return super.nowIn(ianaIdentifier);
  }
}

class _SteppingClock implements AuraClock {
  _SteppingClock(this._instant);

  DateTime _instant;

  void advance(Duration duration) => _instant = _instant.add(duration);

  @override
  DateTime nowUtc() => _instant.toUtc();

  @override
  DateTime nowDeviceLocal() => _instant;

  @override
  String get deviceTimeZoneName => 'Stepping test zone';

  @override
  Duration get deviceUtcOffset => Duration.zero;

  @override
  DateTime nowIn(String ianaIdentifier) =>
      tz.TZDateTime.from(nowUtc(), tz.getLocation(ianaIdentifier));

  @override
  bool supportsZone(String ianaIdentifier) =>
      tz.timeZoneDatabase.locations.containsKey(ianaIdentifier);

  @override
  String formatIn(
    DateTime instant, {
    required String ianaIdentifier,
    String locale = 'en_US',
  }) {
    return DateFormat('d MMM yyyy, HH:mm', locale).format(
      tz.TZDateTime.from(instant.toUtc(), tz.getLocation(ianaIdentifier)),
    );
  }
}
