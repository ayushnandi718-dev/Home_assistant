import 'package:aura_hub/features/ai/presentation/ai_markdown_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseAiMessageSegments', () {
    test('recognises a piped markdown table with its rows', () {
      const String markdown = '''
| Form | Strength |
| --- | --- |
| Tablet | 500 mg |
| Liquid | 160 mg/5 mL |
''';
      final List<AiMessageSegment> segments = parseAiMessageSegments(markdown);

      expect(segments, hasLength(1));
      final AiTableSegment table = segments.single as AiTableSegment;
      expect(table.headers, <String>['Form', 'Strength']);
      expect(
        table.rows,
        <List<String>>[
          <String>['Tablet', '500 mg'],
          <String>['Liquid', '160 mg/5 mL'],
        ],
      );
    });

    test('keeps surrounding prose as separate text segments', () {
      const String markdown = '''
Before the table.
| A | B |
|:--- | ---:|
| 1 | 2 |
After the table.
''';
      final List<AiMessageSegment> segments = parseAiMessageSegments(markdown);

      expect(segments, hasLength(3));
      expect(segments.first, isA<AiTextSegment>());
      expect((segments.first as AiTextSegment).text, 'Before the table.');
      expect(segments[1], isA<AiTableSegment>());
      expect(segments.last, isA<AiTextSegment>());
      expect((segments.last as AiTextSegment).text, 'After the table.');
    });

    test('a bare dashed line is not treated as a table', () {
      final List<AiMessageSegment> segments =
          parseAiMessageSegments('Heading\n---\nSome text');

      expect(segments, hasLength(1));
      expect(segments.single, isA<AiTextSegment>());
    });

    test('a table with mismatched columns stays as text', () {
      const String markdown = '''
| A | B |
| --- | --- |
| only one cell |
''';
      final List<AiMessageSegment> segments = parseAiMessageSegments(markdown);

      expect(segments, hasLength(1));
      expect(segments.single, isA<AiTextSegment>());
    });

    test('escaped pipes inside cells are preserved', () {
      const String markdown = '''
| Name | Value |
| --- | --- |
| a \\| b | ok |
''';
      final List<AiMessageSegment> segments = parseAiMessageSegments(markdown);
      final AiTableSegment table = segments.single as AiTableSegment;

      expect(table.rows.single.first, 'a | b');
    });
  });

  testWidgets('AiMarkdownView renders table headers and cells',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiMarkdownView(
            text: '''
| Form | Strength |
| --- | --- |
| Tablet | 500 mg |
''',
          ),
        ),
      ),
    );

    expect(find.text('Form'), findsOneWidget);
    expect(find.text('Strength'), findsOneWidget);
    expect(find.text('Tablet'), findsOneWidget);
    expect(find.text('500 mg'), findsOneWidget);
    expect(find.byType(Table), findsOneWidget);
    expect(find.textContaining('| --- |'), findsNothing);
  });
}
