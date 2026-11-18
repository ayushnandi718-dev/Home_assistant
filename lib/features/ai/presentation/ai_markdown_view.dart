import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:flutter/material.dart';

/// One ordinary text run inside an assistant message.
class AiTextSegment extends AiMessageSegment {
  const AiTextSegment(this.text);

  final String text;
}

/// A GitHub-flavoured markdown table found inside an assistant message.
class AiTableSegment extends AiMessageSegment {
  const AiTableSegment({
    required this.headers,
    required this.rows,
  });

  final List<String> headers;
  final List<List<String>> rows;
}

/// A plain-text run or a table, in the order they appear in the reply.
abstract class AiMessageSegment {
  const AiMessageSegment();
}

/// Splits raw assistant markdown into text and table segments.
///
/// Only pipe tables with a header separator row are recognised. Anything that
/// does not form a complete table stays as ordinary text, so unusual model
/// output is never silently dropped.
List<AiMessageSegment> parseAiMessageSegments(String text) {
  final List<String> lines = text.split('\n');
  final List<AiMessageSegment> segments = <AiMessageSegment>[];
  final StringBuffer pending = StringBuffer();

  void flushPending() {
    final String content = pending.toString().trimRight();
    if (content.trim().isNotEmpty) {
      segments.add(AiTextSegment(content));
    }
    pending.clear();
  }

  int index = 0;
  while (index < lines.length) {
    if (_startsTable(lines, index)) {
      final List<String> headers = _cells(lines[index]);
      final List<List<String>> rows = <List<String>>[];
      int cursor = index + 2; // header + separator
      while (cursor < lines.length && _looksLikeRow(lines[cursor])) {
        final List<String> cells = _cells(lines[cursor]);
        if (cells.length != headers.length) break;
        rows.add(cells);
        cursor++;
      }
      if (rows.isNotEmpty) {
        flushPending();
        segments.add(
          AiTableSegment(headers: headers, rows: rows),
        );
        index = cursor;
        continue;
      }
    }
    pending.writeln(lines[index]);
    index++;
  }
  flushPending();
  return segments;
}

bool _startsTable(List<String> lines, int index) {
  if (index + 1 >= lines.length) return false;
  if (!_looksLikeRow(lines[index])) return false;
  final List<String> headers = _cells(lines[index]);
  final List<String> separators = _cells(lines[index + 1]);
  if (headers.isEmpty || headers.length != separators.length) return false;
  return separators.every(_isSeparatorCell);
}

bool _looksLikeRow(String line) {
  final String trimmed = line.trim();
  return trimmed.isNotEmpty && trimmed.contains('|');
}

bool _isSeparatorCell(String cell) {
  final String value = cell.trim();
  if (value.isEmpty) return false;
  int start = 0;
  int end = value.length;
  if (value.startsWith(':')) start++;
  if (value.endsWith(':')) end--;
  if (end <= start) return false;
  return value
      .substring(start, end)
      .split('')
      .every((String character) => character == '-');
}

List<String> _cells(String line) {
  String value = line.trim();
  if (value.startsWith('|')) value = value.substring(1);
  if (value.endsWith('|')) value = value.substring(0, value.length - 1);

  final List<String> cells = <String>[];
  final StringBuffer current = StringBuffer();
  for (int index = 0; index < value.length; index++) {
    final String character = value[index];
    if (character == '\\' &&
        index + 1 < value.length &&
        value[index + 1] == '|') {
      current.write('|');
      index++;
    } else if (character == '|') {
      cells.add(current.toString().trim());
      current.clear();
    } else {
      current.write(character);
    }
  }
  cells.add(current.toString().trim());
  return cells;
}

/// Renders assistant markdown, turning pipe tables into readable rows instead
/// of dumping raw `| --- |` syntax into the chat bubble.
class AiMarkdownView extends StatelessWidget {
  const AiMarkdownView({
    required this.text,
    this.style,
    super.key,
  });

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle bodyStyle =
        style ?? theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    final List<AiMessageSegment> segments = parseAiMessageSegments(text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int index = 0; index < segments.length; index++) ...<Widget>[
          if (index > 0) const SizedBox(height: AuraSpace.sm),
          _buildSegment(
            segments[index],
            bodyStyle: bodyStyle,
            theme: theme,
          ),
        ],
      ],
    );
  }

  Widget _buildSegment(
    AiMessageSegment segment, {
    required TextStyle bodyStyle,
    required ThemeData theme,
  }) {
    if (segment is AiTextSegment) {
      return Text(segment.text, style: bodyStyle);
    }
    final AiTableSegment table = segment as AiTableSegment;
    return _AiDataTable(table: table, bodyStyle: bodyStyle);
  }
}

class _AiDataTable extends StatelessWidget {
  const _AiDataTable({required this.table, required this.bodyStyle});

  final AiTableSegment table;
  final TextStyle bodyStyle;

  @override
  Widget build(BuildContext context) {
    final Color border = AuraColors.border.withValues(alpha: 0.85);
    final BorderSide side = BorderSide(color: border);
    final TextStyle headerStyle = bodyStyle.copyWith(
      fontWeight: FontWeight.w700,
      color: AuraColors.textPrimary,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AuraSpace.xs),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder(
            top: side,
            bottom: side,
            left: side,
            right: side,
            horizontalInside: side,
            verticalInside: side,
          ),
          children: <TableRow>[
            TableRow(
              decoration: BoxDecoration(
                color: AuraColors.primary.withValues(alpha: 0.16),
              ),
              children: <Widget>[
                for (final String header in table.headers)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AuraSpace.sm,
                      vertical: AuraSpace.xxs,
                    ),
                    child: Text(header, style: headerStyle),
                  ),
              ],
            ),
            for (int rowIndex = 0;
                rowIndex < table.rows.length;
                rowIndex++) ...<TableRow>[
              TableRow(
                decoration: BoxDecoration(
                  color: rowIndex.isEven
                      ? AuraColors.elevated.withValues(alpha: 0.45)
                      : null,
                ),
                children: <Widget>[
                  for (final String cell in table.rows[rowIndex])
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AuraSpace.sm,
                        vertical: AuraSpace.xxs,
                      ),
                      child: Text(cell, style: bodyStyle),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
