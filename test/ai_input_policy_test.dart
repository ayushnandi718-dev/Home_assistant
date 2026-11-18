import 'package:aura_hub/features/ai/domain/ai_input_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AiInputPolicy', () {
    test('blocks clear abusive slang in English and Hinglish', () {
      for (final String text in <String>[
        'you are a bitch',
        'what the fuck',
        'bhenchod',
        'madarchod',
        'chutiya',
        'lodu',
        'maa ki chut',
      ]) {
        expect(AiInputPolicy.isBlocked(text), isTrue, reason: text);
      }
    });

    test('blocks simple obfuscation without blocking ordinary words', () {
      expect(AiInputPolicy.isBlocked('sh!t'), isTrue);
      expect(AiInputPolicy.isBlocked('b!tch'), isTrue);
      expect(AiInputPolicy.isBlocked('l0du'), isTrue);
      expect(AiInputPolicy.isBlocked('b@stard'), isTrue);

      expect(AiInputPolicy.isBlocked('Paracetamol dosage for fever'), isFalse);
      expect(AiInputPolicy.isBlocked('the assistant has good class'), isFalse);
      expect(
          AiInputPolicy.isBlocked('Gandhi and the freedom movement'), isFalse);
      expect(AiInputPolicy.isBlocked('कृपया मदद करें'), isFalse);
      expect(AiInputPolicy.isBlocked('কেমন আছেন?'), isFalse);
    });

    test('fixed warning never echoes user text', () {
      expect(AiInputPolicy.blockedMessage, contains('respectful'));
      expect(AiInputPolicy.blockedMessage, isNot(contains('bhenchod')));
    });
  });
}
