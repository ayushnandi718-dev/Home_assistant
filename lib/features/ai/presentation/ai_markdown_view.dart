import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

/// Renders assistant Markdown with AURA's dark chat styling.
///
/// Raw HTML syntaxes are deliberately omitted from the extension set. Model
/// output is untrusted, so `<script>` and friends stay visible as literal text
/// instead of becoming live widgets. Links are rendered as styled text; tapping
/// a safe `http(s)` or `mailto` destination copies it instead of launching an
/// arbitrary scheme. Markdown image syntax is inert: only the alt text is
/// shown, so replies cannot trigger unsolicited network or local file reads.
class AiMarkdownView extends StatelessWidget {
  const AiMarkdownView({
    required this.text,
    this.style,
    this.streaming = false,
    super.key,
  });

  final String text;
  final TextStyle? style;

  /// While tokens arrive, drop only trailing/incomplete emphasis and link
  /// delimiters so half-written syntax does not flash in the bubble. Completed
  /// Markdown is always rendered normally.
  final bool streaming;

  /// GitHub-flavored features without `InlineHtmlSyntax`.
  ///
  /// The base parser still provides headings, lists, blockquotes, emphasis,
  /// inline code, links and paragraphs; these extensions add fenced code,
  /// tables, strikethrough and autolinks.
  static final md.ExtensionSet _safeExtensionSet = md.ExtensionSet(
    List<md.BlockSyntax>.unmodifiable(<md.BlockSyntax>[
      const md.FencedCodeBlockSyntax(),
      const md.TableSyntax(),
    ]),
    List<md.InlineSyntax>.unmodifiable(<md.InlineSyntax>[
      md.StrikethroughSyntax(),
      md.AutolinkExtensionSyntax(),
    ]),
  );

  /// Conservative cleanup for partially streamed Markdown.
  ///
  /// This never tries to "complete" a construct; it only removes delimiters
  /// that cannot form a complete token yet. Code spans and fenced code blocks
  /// are left untouched.
  static String prepareForRendering(String text, {bool streaming = false}) {
    if (!streaming) return text;
    String result = _removeUnpairedInlineCodeTick(text);
    result = _applyOutsideCode(result, _hideUnclosedLink);
    result = _applyOutsideCode(
      result,
      (String value) => _removeUnmatchedPair(value, '**'),
    );
    result = _applyOutsideCode(
      result,
      (String value) => _removeUnmatchedPair(value, '__'),
    );
    result = _applyOutsideCode(
      result,
      (String value) => _removeUnmatchedPair(value, '``'),
    );
    result = _applyOutsideCode(
      result,
      (String value) => _removeUnmatchedSingle(value, '*'),
    );
    return _applyOutsideCode(
      result,
      (String value) => _removeUnmatchedSingle(value, '_'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String prepared = prepareForRendering(text, streaming: streaming);
    if (prepared.trim().isEmpty) return const SizedBox.shrink();

    final ThemeData theme = Theme.of(context);
    final TextStyle bodyStyle =
        style ?? theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 14);

    return MarkdownBody(
      data: prepared,
      selectable: false,
      shrinkWrap: true,
      softLineBreak: true,
      extensionSet: _safeExtensionSet,
      sizedImageBuilder: (config) => Text(config.alt ?? '', style: bodyStyle),
      styleSheet: _styleSheet(theme, bodyStyle),
      onTapLink: (String? label, String? href, String? title) =>
          _handleLinkTap(context, label, href),
    );
  }

  MarkdownStyleSheet _styleSheet(ThemeData theme, TextStyle body) {
    final BorderSide side = BorderSide(
      color: AuraColors.border.withValues(alpha: 0.85),
    );
    final TextStyle emphasis = body.copyWith(
      color: AuraColors.textPrimary,
      fontStyle: FontStyle.italic,
    );
    final TextStyle strong = body.copyWith(
      color: AuraColors.textPrimary,
      fontWeight: FontWeight.w700,
    );

    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: body,
      a: body.copyWith(
        color: AuraColors.primary,
        decoration: TextDecoration.underline,
      ),
      em: emphasis,
      strong: strong,
      del: body.copyWith(
        color: AuraColors.textSecondary,
        decoration: TextDecoration.lineThrough,
      ),
      h1: strong.copyWith(fontSize: 18),
      h2: strong.copyWith(fontSize: 16),
      h3: strong.copyWith(fontSize: 14),
      h4: strong.copyWith(fontSize: body.fontSize),
      h5: strong.copyWith(fontSize: body.fontSize),
      h6: strong.copyWith(fontSize: body.fontSize),
      h1Padding: const EdgeInsets.only(bottom: AuraSpace.xs),
      h2Padding: const EdgeInsets.only(bottom: AuraSpace.xs),
      h3Padding: const EdgeInsets.only(bottom: AuraSpace.xxs),
      code: body.copyWith(
        fontFamily: 'Consolas',
        color: AuraColors.success,
        backgroundColor: AuraColors.elevated.withValues(alpha: 0.75),
      ),
      codeblockPadding: const EdgeInsets.all(AuraSpace.sm),
      codeblockDecoration: BoxDecoration(
        color: AuraColors.elevated.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AuraSpace.xs),
        border: Border.all(color: AuraColors.border.withValues(alpha: 0.65)),
      ),
      blockquote: body.copyWith(fontStyle: FontStyle.italic),
      blockquotePadding: const EdgeInsets.fromLTRB(
        AuraSpace.sm,
        AuraSpace.xxs,
        AuraSpace.xxs,
        AuraSpace.xxs,
      ),
      blockquoteDecoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: AuraColors.secondary, width: 2),
        ),
      ),
      tableHead: strong,
      tableBody: body,
      tableBorder: TableBorder(
        top: side,
        bottom: side,
        left: side,
        right: side,
        horizontalInside: side,
        verticalInside: side,
      ),
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: AuraSpace.sm,
        vertical: AuraSpace.xxs,
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: side),
      ),
      blockSpacing: AuraSpace.sm.toDouble(),
      listIndent: AuraSpace.md.toDouble(),
    );
  }

  void _handleLinkTap(BuildContext context, String? label, String? href) {
    if (href == null || href.trim().isEmpty) return;
    final Uri? uri = Uri.tryParse(href);
    final bool safe = uri != null &&
        (uri.isScheme('http') ||
            uri.isScheme('https') ||
            uri.isScheme('mailto'));
    final SnackBar snackBar = SnackBar(
      content: Text(
        safe ? 'Link copied: $href' : 'Unsupported link destination',
      ),
    );
    if (safe) {
      Clipboard.setData(ClipboardData(text: href));
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(snackBar);
  }
}

class _Region {
  const _Region(this.start, this.end);

  final int start;
  final int end;
}

String _applyOutsideCode(String text, String Function(String) transform) {
  final List<_Region> regions = _editableRegions(text);
  if (regions.isEmpty) return text;
  final StringBuffer out = StringBuffer();
  int cursor = 0;
  for (final _Region region in regions) {
    out.write(text.substring(cursor, region.start));
    out.write(transform(text.substring(region.start, region.end)));
    cursor = region.end;
  }
  out.write(text.substring(cursor));
  return out.toString();
}

/// Finds ranges outside fenced blocks and inline code spans.
List<_Region> _editableRegions(String text) {
  final List<_Region> regions = <_Region>[];
  final RegExp backticks = RegExp(r'`+');
  bool inFence = false;
  int lineStart = 0;

  for (final String line in text.split('\n')) {
    final String trimmed = line.trimLeft();
    final bool isFence = trimmed.startsWith('```') || trimmed.startsWith('~~~');
    if (isFence) {
      inFence = !inFence;
      lineStart += line.length + 1;
      continue;
    }
    if (!inFence) {
      bool inCode = false;
      int regionStart = 0;
      for (final RegExpMatch match in backticks.allMatches(line)) {
        if (!inCode && match.start > regionStart) {
          regions
              .add(_Region(lineStart + regionStart, lineStart + match.start));
        }
        inCode = !inCode;
        regionStart = match.end;
      }
      if (!inCode && line.length > regionStart) {
        regions.add(_Region(lineStart + regionStart, lineStart + line.length));
      }
    }
    lineStart += line.length + 1;
  }
  return regions;
}

String _removeUnpairedInlineCodeTick(String text) {
  final int first = text.indexOf('`');
  if (first == -1) return text;
  final int last = text.lastIndexOf('`');
  if (first == last) {
    return text.substring(0, last) + text.substring(last + 1);
  }
  return text;
}

String _hideUnclosedLink(String text) {
  for (int index = text.length - 1; index >= 0; index--) {
    if (text[index] != '[') continue;
    final int labelEnd = text.indexOf('](', index + 1);
    if (labelEnd == -1) {
      // A lone '[' cannot be a link yet; keep the label text.
      return text.substring(0, index) + text.substring(index + 1);
    }
    if (!text.contains(')', labelEnd + 2)) {
      // Keep the label while dropping the incomplete destination syntax.
      final String label = text.substring(index + 1, labelEnd);
      return text.substring(0, index) + label;
    }
  }
  return text;
}

String _removeUnmatchedPair(String text, String delimiter) {
  final List<int> indices = <int>[];
  int cursor = 0;
  while (true) {
    final int index = text.indexOf(delimiter, cursor);
    if (index == -1) break;
    indices.add(index);
    cursor = index + delimiter.length;
  }
  if (indices.length.isEven || indices.isEmpty) return text;
  final int removeAt = indices.last;
  return text.substring(0, removeAt) +
      text.substring(removeAt + delimiter.length);
}

String _removeUnmatchedSingle(String text, String delimiter) {
  final List<int> indices = <int>[];
  for (int index = 0; index < text.length; index++) {
    if (text[index] != delimiter) continue;
    final bool previousSame = index > 0 && text[index - 1] == delimiter;
    final bool nextSame =
        index + 1 < text.length && text[index + 1] == delimiter;
    if (!previousSame && !nextSame) indices.add(index);
  }
  if (indices.length.isEven || indices.isEmpty) return text;
  final int removeAt = indices.last;
  return text.substring(0, removeAt) + text.substring(removeAt + 1);
}
