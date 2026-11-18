import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/family/domain/family_directory_service.dart';
import 'package:aura_hub/features/family/domain/family_member.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum FamilyExportFormat { json, csv }

class FamilyImportExportDialog extends StatefulWidget {
  const FamilyImportExportDialog({
    super.key,
    required this.members,
    required this.onImport,
  });

  final List<FamilyMember> members;
  final Future<FamilyImportResult> Function(
      List<FamilyMember> incoming, bool overwrite) onImport;

  @override
  State<FamilyImportExportDialog> createState() =>
      _FamilyImportExportDialogState();
}

class _FamilyImportExportDialogState extends State<FamilyImportExportDialog> {
  FamilyExportFormat _format = FamilyExportFormat.json;
  late final TextEditingController _export;
  late final TextEditingController _import;
  bool _overwrite = false;
  String? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _export = TextEditingController(
        text: FamilyDirectoryService.exportJson(widget.members));
    _import = TextEditingController();
  }

  @override
  void dispose() {
    _export.dispose();
    _import.dispose();
    super.dispose();
  }

  void _changeFormat(FamilyExportFormat? format) {
    if (format == null) return;
    setState(() {
      _format = format;
      _export.text = format == FamilyExportFormat.json
          ? FamilyDirectoryService.exportJson(widget.members)
          : FamilyDirectoryService.exportCsv(widget.members);
    });
  }

  Future<void> _copyExport() async {
    await Clipboard.setData(ClipboardData(text: _export.text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Export copied to clipboard')),
    );
  }

  Future<void> _runImport() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final List<FamilyMember> incoming =
          FamilyDirectoryService.parseImport(_import.text);
      final FamilyImportResult result =
          await widget.onImport(incoming, _overwrite);
      if (!mounted) return;
      setState(() {
        _status = 'Added ${result.added}, updated ${result.updated}, '
            'skipped ${result.skipped}.';
      });
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() => _status = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = 'The import file could not be read.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Import & export', style: text.headlineSmall),
        const SizedBox(height: AuraSpace.sm),
        Text(
          'Export is copied as text. Import accepts the same JSON or CSV format. '
          'Existing records are never overwritten unless you allow it.',
          style: text.bodyMedium?.copyWith(color: AuraColors.textSecondary),
        ),
        const SizedBox(height: AuraSpace.lg),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                DropdownButtonFormField<FamilyExportFormat>(
                  initialValue: _format,
                  decoration: const InputDecoration(
                    labelText: 'Export format',
                    border: OutlineInputBorder(),
                  ),
                  items: const <DropdownMenuItem<FamilyExportFormat>>[
                    DropdownMenuItem(
                      value: FamilyExportFormat.json,
                      child: Text('JSON'),
                    ),
                    DropdownMenuItem(
                      value: FamilyExportFormat.csv,
                      child: Text('CSV'),
                    ),
                  ],
                  onChanged: _changeFormat,
                ),
                const SizedBox(height: AuraSpace.sm),
                TextField(
                  controller: _export,
                  maxLines: 6,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Export text',
                    border: OutlineInputBorder(),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _copyExport,
                    icon: const Icon(Icons.copy_all_outlined, size: 16),
                    label: const Text('Copy export'),
                  ),
                ),
                const Divider(),
                TextField(
                  controller: _import,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Paste JSON or CSV to import',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AuraSpace.xs),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Overwrite matching records'),
                  subtitle:
                      const Text('Off by default. Duplicates are skipped.'),
                  value: _overwrite,
                  onChanged: _busy
                      ? null
                      : (bool value) => setState(() => _overwrite = value),
                ),
                if (_status != null) ...<Widget>[
                  const SizedBox(height: AuraSpace.xs),
                  Text(
                    _status!,
                    style: text.bodySmall?.copyWith(color: AuraColors.warning),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AuraSpace.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            const SizedBox(width: AuraSpace.xs),
            FilledButton.icon(
              onPressed:
                  _busy || _import.text.trim().isEmpty ? null : _runImport,
              icon: const Icon(Icons.file_upload_outlined, size: 16),
              label: Text(_busy ? 'Importing…' : 'Import'),
            ),
          ],
        ),
      ],
    );
  }
}
