import 'package:aura_hub/core/config/aura_runtime_config.dart';
import 'package:aura_hub/core/logging/aura_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuraLogger', () {
    test('keeps newest entries first', () {
      final AuraLogger logger = AuraLogger();
      logger.info('core', 'first');
      logger.warning('api', 'second');

      expect(logger.state.length, 2);
      expect(logger.state.first.message, 'second');
      expect(logger.state.first.level, AuraLogLevel.warning);
      expect(logger.state.last.message, 'first');
    });

    test('redacts URLs and paths in messages and context', () {
      final AuraLogger logger = AuraLogger();
      logger.error(
        'api',
        'Failed at https://example.test/telemetry?token=secret',
        context: <String, String>{
          'path': r'C:\Users\ayush\Home_assistant\secret.txt',
        },
      );

      final AuraLogEntry entry = logger.state.single;
      expect(entry.message, isNot(contains('example.test')));
      expect(entry.message, contains('<url>'));
      expect(entry.context['path'], '<path>');
      expect(jsonSafe(entry), isNot(contains('example.test')));
    });

    test('level helpers set the correct severity', () {
      final AuraLogger logger = AuraLogger();
      logger.debug('core', 'd');
      logger.info('core', 'i');
      logger.warning('core', 'w');
      logger.error('core', 'e');

      expect(
        logger.state.map((AuraLogEntry e) => e.level).toList(),
        <AuraLogLevel>[
          AuraLogLevel.error,
          AuraLogLevel.warning,
          AuraLogLevel.info,
          AuraLogLevel.debug,
        ],
      );
    });

    test('buffer is bounded', () {
      final AuraLogger logger = AuraLogger();
      final int total = AuraRuntimeConfig.maxLogEntries + 25;
      for (int index = 0; index < total; index++) {
        logger.info('core', 'entry $index');
      }

      expect(logger.state.length, AuraRuntimeConfig.maxLogEntries);
      expect(logger.state.first.message, 'entry ${total - 1}');
    });

    test('clear empties the buffer', () {
      final AuraLogger logger = AuraLogger();
      logger.info('core', 'one');
      logger.clear();
      expect(logger.state, isEmpty);
    });
  });
}

String jsonSafe(AuraLogEntry entry) => entry.toJson().toString();
