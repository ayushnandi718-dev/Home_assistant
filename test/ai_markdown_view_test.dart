import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/features/ai/presentation/ai_markdown_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AiMarkdownView.prepareForRendering', () {
    test('complete markdown is passed through unchanged', () {
      const String markdown = '**4:12 PM**\n\n- one\n- two';

      expect(
        AiMarkdownView.prepareForRendering(markdown),
        markdown,
      );
    });

    test('streaming removes unmatched emphasis and link delimiters', () {
      expect(
        AiMarkdownView.prepareForRendering('**4:12 PM', streaming: true),
        '4:12 PM',
      );
      expect(
        AiMarkdownView.prepareForRendering('*italic', streaming: true),
        'italic',
      );
      expect(
        AiMarkdownView.prepareForRendering('[AURA](https://', streaming: true),
        'AURA',
      );
      expect(
        AiMarkdownView.prepareForRendering('**done** and **pending',
            streaming: true),
        '**done** and pending',
      );
    });

    test('streaming leaves code spans and fenced blocks untouched', () {
      expect(
        AiMarkdownView.prepareForRendering('`**raw**`', streaming: true),
        '`**raw**`',
      );
      expect(
        AiMarkdownView.prepareForRendering('```\n**raw**\n', streaming: true),
        '```\n**raw**\n',
      );
    });
  });

  group('AiMarkdownView rendering', () {
    testWidgets('renders bold and italic instead of literal markers',
        (WidgetTester tester) async {
      await _pump(tester, '**4:12 PM** and *italic note*');

      final String rendered = _renderedText(tester);
      expect(rendered, contains('4:12 PM'));
      expect(rendered, contains('italic note'));
      expect(rendered, isNot(contains('**')));
      expect(
        _spanWithText(tester, '4:12 PM')?.style?.fontWeight,
        FontWeight.w700,
      );
      expect(
        _spanWithText(tester, 'italic note')?.style?.fontStyle,
        FontStyle.italic,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders headings and ordered/unordered lists',
        (WidgetTester tester) async {
      await _pump(
        tester,
        '# Heading\n\n- First item\n- Second item\n\n1. One\n2. Two',
      );

      final String rendered = _renderedText(tester);
      for (final String expected in <String>[
        'Heading',
        'First item',
        'Second item',
        'One',
        'Two',
      ]) {
        expect(rendered, contains(expected));
      }
      expect(rendered, isNot(contains('# Heading')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders inline code and fenced code blocks',
        (WidgetTester tester) async {
      await _pump(
        tester,
        'Use `apiKey` here.\n\n```dart\nprint("hello");\n```',
      );

      final String rendered = _renderedText(tester);
      expect(rendered, contains('apiKey'));
      expect(rendered, contains('print("hello");'));
      expect(rendered, isNot(contains('```')));
      expect(
        _spanWithText(tester, 'apiKey')?.style?.fontFamily,
        'Consolas',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders links, blockquotes and tables',
        (WidgetTester tester) async {
      await _pump(
        tester,
        '[AURA docs](https://example.com)\n\n'
        '> Quoted guidance\n\n'
        '| Form | Strength |\n| --- | --- |\n| Tablet | 500 mg |',
      );

      final String rendered = _renderedText(tester);
      for (final String expected in <String>[
        'AURA docs',
        'Quoted guidance',
        'Form',
        'Strength',
        'Tablet',
        '500 mg',
      ]) {
        expect(rendered, contains(expected));
      }
      expect(rendered, isNot(contains('| --- |')));
      expect(find.byType(Table), findsOneWidget);
      expect(
        _spanWithText(tester, 'AURA docs')?.style?.color,
        AuraColors.primary,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('streaming renders completed bold and hides partial syntax',
        (WidgetTester tester) async {
      await _pump(tester, '**4:12 PM', streaming: true);

      String rendered = _renderedText(tester);
      expect(rendered, contains('4:12 PM'));
      expect(rendered, isNot(contains('**')));

      await _pump(tester, '**4:12 PM**', streaming: true);

      rendered = _renderedText(tester);
      expect(rendered, contains('4:12 PM'));
      expect(rendered, isNot(contains('**')));
      expect(
        _spanWithText(tester, '4:12 PM')?.style?.fontWeight,
        FontWeight.w700,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('streaming hides an incomplete link destination',
        (WidgetTester tester) async {
      await _pump(tester, 'Read [AURA](https://', streaming: true);

      final String rendered = _renderedText(tester);
      expect(rendered, contains('AURA'));
      expect(rendered, isNot(contains('](')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders plain text, empty and malformed messages safely',
        (WidgetTester tester) async {
      await _pump(tester, 'plain text\nsecond line');

      String rendered = _renderedText(tester);
      expect(rendered, contains('plain text'));
      expect(rendered, contains('second line'));

      await _pump(tester, '');
      expect(_renderedText(tester).trim(), isEmpty);

      await _pump(tester, '**unclosed * [link](');
      rendered = _renderedText(tester);
      expect(rendered, isNotEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('does not interpret raw HTML as trusted content',
        (WidgetTester tester) async {
      await _pump(tester, '<script>alert(1)</script>\n\n**safe**');

      final String rendered = _renderedText(tester);
      expect(rendered, isNot(contains('alert(1)')));
      expect(rendered, contains('safe'));
      expect(rendered, isNot(contains('**')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('does not load markdown images from untrusted replies',
        (WidgetTester tester) async {
      await _pump(
        tester,
        '![remote](https://example.invalid/track.png) '
        '![local](file:///C:/Users/ayush/secret.png)',
      );

      expect(find.byType(Image), findsNothing);
      final String rendered = _renderedText(tester);
      expect(rendered, contains('remote'));
      expect(rendered, contains('local'));
      expect(tester.takeException(), isNull);
    });
  });
}

Future<void> _pump(
  WidgetTester tester,
  String markdown, {
  bool streaming = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AiMarkdownView(text: markdown, streaming: streaming),
        ),
      ),
    ),
  );
}

String _renderedText(WidgetTester tester) {
  final StringBuffer out = StringBuffer();
  for (final RichText rich
      in tester.widgetList<RichText>(find.byType(RichText))) {
    out.writeln(rich.text.toPlainText());
  }
  for (final Text text in tester.widgetList<Text>(find.byType(Text))) {
    out.writeln(text.data ?? '');
  }
  return out.toString();
}

TextSpan? _spanWithText(WidgetTester tester, String text) {
  for (final RichText rich
      in tester.widgetList<RichText>(find.byType(RichText))) {
    final TextSpan? match = _findSpan(rich.text, text);
    if (match != null) return match;
  }
  return null;
}

TextSpan? _findSpan(InlineSpan span, String text) {
  if (span is TextSpan) {
    if (span.text == text) return span;
    for (final InlineSpan child in span.children ?? const <InlineSpan>[]) {
      final TextSpan? match = _findSpan(child, text);
      if (match != null) return match;
    }
  }
  return null;
}
