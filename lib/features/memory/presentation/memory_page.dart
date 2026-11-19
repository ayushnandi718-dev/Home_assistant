import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/memory/domain/memory_category.dart';
import 'package:aura_hub/features/memory/domain/memory_record.dart';
import 'package:aura_hub/features/memory/domain/memory_status.dart';
import 'package:aura_hub/features/memory/presentation/memory_providers.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:aura_hub/shared/widgets/aura_scroll_area.dart';
import 'package:aura_hub/shared/widgets/glass/glass_badge.dart';
import 'package:aura_hub/shared/widgets/glass/glass_dialog.dart';
import 'package:aura_hub/shared/widgets/info_banner.dart';
import 'package:aura_hub/shared/widgets/page_header.dart';
import 'package:aura_hub/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Management screen for the active workspace's local memory.
///
/// The active profile provider is the only source of scope. This screen never
/// accepts a profile argument, so FAMILY cannot ask to display AYUSH memory.
class MemoryPage extends ConsumerStatefulWidget {
  const MemoryPage({super.key});

  @override
  ConsumerState<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends ConsumerState<MemoryPage> {
  String _query = '';
  MemoryCategory? _category;
  MemoryStatus _tab = MemoryStatus.approved;

  List<MemoryRecord> _visible(List<MemoryRecord> records) {
    final String query = _query.trim().toLowerCase();
    final List<MemoryRecord> filtered = records.where((MemoryRecord item) {
      if (_category != null && item.category != _category) return false;
      if (query.isEmpty) return true;
      return item.content.toLowerCase().contains(query) ||
          item.tags.any((String tag) => tag.toLowerCase().contains(query)) ||
          item.category.label.toLowerCase().contains(query);
    }).toList();
    filtered.sort(
        (MemoryRecord a, MemoryRecord b) => b.updatedAt.compareTo(a.updatedAt));
    return filtered;
  }

  Future<void> _notify(bool succeeded, String successMessage) async {
    if (!mounted) return;
    final String? error = ref.read(activeMemoryStateProvider).errorMessage;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(succeeded ? successMessage : error ?? 'Not saved.')),
    );
  }

  Future<void> _openEditor(
      {MemoryRecord? existing, bool suggestion = false}) async {
    final _MemoryDraft? draft = await showGlassDialog<_MemoryDraft>(
      context: context,
      width: 620,
      child: _MemoryEditorDialog(record: existing, suggestion: suggestion),
    );
    if (draft == null || !mounted) return;
    final MemoryController controller =
        ref.read(activeMemoryControllerProvider);
    final bool ok = existing == null
        ? suggestion
            ? await controller.suggest(
                content: draft.content,
                category: draft.category,
                tags: draft.tags,
                expiresAt: draft.expiresAt,
              )
            : await controller.createApproved(
                content: draft.content,
                category: draft.category,
                tags: draft.tags,
                expiresAt: draft.expiresAt,
              )
        : await controller.update(
            id: existing.id,
            content: draft.content,
            category: draft.category,
            tags: draft.tags,
            expiresAt: draft.expiresAt,
          );
    await _notify(
        ok, suggestion ? 'Suggestion saved for approval.' : 'Memory saved.');
  }

  Future<void> _confirmAction({
    required String title,
    required String message,
    required Future<bool> Function() action,
    required String successMessage,
  }) async {
    final bool? confirmed = await showGlassDialog<bool>(
      context: context,
      width: 460,
      child: _ConfirmDialog(title: title, message: message),
    );
    if (confirmed != true || !mounted) return;
    final bool ok = await action();
    await _notify(ok, successMessage);
  }

  @override
  Widget build(BuildContext context) {
    final AuraProfile profile = ref.watch(activeProfileProvider);
    final MemoryState state = ref.watch(activeMemoryStateProvider);
    final MemoryController controller =
        ref.read(activeMemoryControllerProvider);
    final TextTheme text = Theme.of(context).textTheme;
    final bool isAyush = profile == AuraProfile.ayush;
    final List<MemoryRecord> records =
        _tab == MemoryStatus.pending ? state.pending : state.approved;
    final List<MemoryRecord> visible = _visible(records);

    return AuraScrollArea(
      padding: EdgeInsets.fromLTRB(
        pageHorizontalPadding(MediaQuery.sizeOf(context).width),
        AuraSpace.lg,
        pageHorizontalPadding(MediaQuery.sizeOf(context).width),
        AuraSpace.xxl,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AuraBreakpoints.content),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              PageHeader(
                eyebrow: 'Local-first memory',
                title: 'AURA Memory',
                description:
                    'Approved information from this workspace only. Nothing is '
                    'saved automatically from conversations.',
                icon: Icons.psychology_outlined,
                trailing: Wrap(
                  spacing: AuraSpace.sm,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: () => _openEditor(suggestion: true),
                      icon: const Icon(Icons.lightbulb_outlined, size: 16),
                      label: const Text('Add suggestion'),
                    ),
                    FilledButton.icon(
                      onPressed: () => _openEditor(),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('New memory'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AuraSpace.lg),
              InfoBanner(
                tone: isAyush ? AuraBannerTone.privacy : AuraBannerTone.warning,
                icon: isAyush
                    ? Icons.lock_outline
                    : Icons.family_restroom_outlined,
                title: '${profile.label} memory workspace',
                message: isAyush
                    ? 'Private memory is available only while the AYUSH PIN '
                        'session is active. Locking clears it from active state.'
                    : 'Shared household memory. It is not private and never '
                        'reads or displays AYUSH memory.',
              ),
              if (state.hasError) ...<Widget>[
                const SizedBox(height: AuraSpace.md),
                InfoBanner(
                  tone: AuraBannerTone.warning,
                  icon: Icons.error_outline_rounded,
                  title: state.storageError
                      ? 'Private memory storage unavailable'
                      : 'Memory change not completed',
                  message: state.errorMessage ?? 'Please try again.',
                ),
              ],
              const SizedBox(height: AuraSpace.lg),
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SegmentedButton<MemoryStatus>(
                      segments: const <ButtonSegment<MemoryStatus>>[
                        ButtonSegment<MemoryStatus>(
                          value: MemoryStatus.approved,
                          label: Text('Approved'),
                          icon: Icon(Icons.check_circle_outline, size: 16),
                        ),
                        ButtonSegment<MemoryStatus>(
                          value: MemoryStatus.pending,
                          label: Text('Pending suggestions'),
                          icon: Icon(Icons.schedule_outlined, size: 16),
                        ),
                      ],
                      selected: <MemoryStatus>{_tab},
                      onSelectionChanged: (Set<MemoryStatus> selection) {
                        setState(() => _tab = selection.first);
                      },
                    ),
                    const SizedBox(height: AuraSpace.md),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              hintText: 'Search memories or tags',
                              prefixIcon: Icon(Icons.search, size: 18),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (String value) =>
                                setState(() => _query = value),
                          ),
                        ),
                        const SizedBox(width: AuraSpace.md),
                        DropdownButton<MemoryCategory?>(
                          value: _category,
                          hint: const Text('All categories'),
                          items: <DropdownMenuItem<MemoryCategory?>>[
                            const DropdownMenuItem<MemoryCategory?>(
                              value: null,
                              child: Text('All categories'),
                            ),
                            ...MemoryCategory.values.map(
                              (MemoryCategory category) =>
                                  DropdownMenuItem<MemoryCategory?>(
                                value: category,
                                child: Text(category.label),
                              ),
                            ),
                          ],
                          onChanged: (MemoryCategory? value) =>
                              setState(() => _category = value),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AuraSpace.lg),
              if (state.isLoading && state.records.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(AuraSpace.xl),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (visible.isEmpty)
                SurfaceCard(
                  child: Column(
                    children: <Widget>[
                      Icon(Icons.psychology_outlined,
                          size: 36, color: AuraColors.textSecondary),
                      const SizedBox(height: AuraSpace.md),
                      Text(
                        _tab == MemoryStatus.pending
                            ? 'No pending suggestions'
                            : 'No approved memories yet',
                        style: text.titleMedium,
                      ),
                      const SizedBox(height: AuraSpace.xs),
                      Text(
                        _query.isEmpty && _category == null
                            ? 'Add a memory or suggestion to get started.'
                            : 'Try clearing the search or category filter.',
                        style: text.bodyMedium?.copyWith(
                          color: AuraColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...visible.map(
                  (MemoryRecord record) => Padding(
                    padding: const EdgeInsets.only(bottom: AuraSpace.md),
                    child: _MemoryCard(
                      record: record,
                      onEdit: () => _openEditor(existing: record),
                      onApprove: () async {
                        final bool ok = await controller.approve(record.id);
                        await _notify(ok, 'Memory approved.');
                      },
                      onReject: () => _confirmAction(
                        title: 'Reject suggestion?',
                        message:
                            'This suggestion will not be used or shown as pending.',
                        action: () => controller.reject(record.id),
                        successMessage: 'Suggestion rejected.',
                      ),
                      onDelete: () => _confirmAction(
                        title: 'Delete memory?',
                        message:
                            'This memory will be removed from this workspace.',
                        action: () => controller.delete(record.id),
                        successMessage: 'Memory deleted.',
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: AuraSpace.lg),
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Memory controls', style: text.titleMedium),
                    const SizedBox(height: AuraSpace.sm),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: state.settings.retrievalEnabled,
                      title: const Text('Use approved memories in AI requests'),
                      subtitle: const Text(
                        'Off by default. Turning this off keeps stored memories '
                        'but stops retrieval immediately.',
                      ),
                      onChanged: (bool value) async {
                        final bool ok = await controller.setSettings(
                          state.settings.copyWith(retrievalEnabled: value),
                        );
                        await _notify(ok, 'Memory retrieval setting saved.');
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: state.settings.suggestionsEnabled,
                      title: const Text('Allow pending memory suggestions'),
                      subtitle: const Text(
                        'Suggestions still require your approval before use.',
                      ),
                      onChanged: (bool value) async {
                        final bool ok = await controller.setSettings(
                          state.settings.copyWith(suggestionsEnabled: value),
                        );
                        await _notify(ok, 'Suggestion setting saved.');
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AuraSpace.md),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _confirmAction(
                    title: 'Clear ${profile.label} memory?',
                    message:
                        'Every memory in this workspace will be deleted. This '
                        'cannot be undone.',
                    action: controller.clear,
                    successMessage: 'Workspace memory cleared.',
                  ),
                  icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                  label: const Text('Clear memory for this workspace'),
                  style:
                      TextButton.styleFrom(foregroundColor: AuraColors.danger),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemoryCard extends StatelessWidget {
  const _MemoryCard({
    required this.record,
    required this.onEdit,
    required this.onApprove,
    required this.onReject,
    required this.onDelete,
  });

  final MemoryRecord record;
  final VoidCallback onEdit;
  final Future<void> Function() onApprove;
  final Future<void> Function() onReject;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool pending = record.status == MemoryStatus.pending;
    return SurfaceCard(
      padding: const EdgeInsets.all(AuraSpace.md),
      borderColor: (pending ? AuraColors.warning : AuraColors.primary)
          .withValues(alpha: 0.24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              GlassStatusBadge(
                label: record.category.label,
                icon: Icons.label_outline,
                color: pending ? AuraColors.warning : AuraColors.primary,
                dense: true,
              ),
              const SizedBox(width: AuraSpace.sm),
              GlassStatusBadge(
                label: record.status.label,
                color: pending ? AuraColors.warning : AuraColors.success,
                dense: true,
              ),
              const Spacer(),
              Text(
                'Updated ${_formatDate(record.updatedAt)}',
                style: text.bodySmall?.copyWith(
                  color: AuraColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AuraSpace.sm),
          Text(record.content, style: text.bodyMedium),
          if (record.tags.isNotEmpty) ...<Widget>[
            const SizedBox(height: AuraSpace.sm),
            Wrap(
              spacing: AuraSpace.xs,
              children: record.tags
                  .map(
                    (String tag) => GlassStatusBadge(
                      label: tag,
                      showDot: false,
                      dense: true,
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          const SizedBox(height: AuraSpace.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              if (pending)
                TextButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.check, size: 15),
                  label: const Text('Approve'),
                ),
              if (pending)
                TextButton.icon(
                  onPressed: onReject,
                  icon: const Icon(Icons.close, size: 15),
                  label: const Text('Reject'),
                ),
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 15),
                label: const Text('Edit'),
              ),
              TextButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 15),
                label: const Text('Delete'),
                style: TextButton.styleFrom(foregroundColor: AuraColors.danger),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime value) {
    final String date = value.toIso8601String().substring(0, 10);
    return date;
  }
}

class _MemoryDraft {
  const _MemoryDraft({
    required this.content,
    required this.category,
    required this.tags,
    required this.expiresAt,
  });

  final String content;
  final MemoryCategory category;
  final List<String> tags;
  final DateTime? expiresAt;
}

class _MemoryEditorDialog extends StatefulWidget {
  const _MemoryEditorDialog({this.record, this.suggestion = false});

  final MemoryRecord? record;
  final bool suggestion;

  @override
  State<_MemoryEditorDialog> createState() => _MemoryEditorDialogState();
}

class _MemoryEditorDialogState extends State<_MemoryEditorDialog> {
  late final TextEditingController _content =
      TextEditingController(text: widget.record?.content ?? '');
  late final TextEditingController _tags = TextEditingController(
    text: widget.record?.tags.join(', ') ?? '',
  );
  late MemoryCategory _category =
      widget.record?.category ?? MemoryCategory.preference;
  late DateTime? _expiresAt = widget.record?.expiresAt;

  @override
  void dispose() {
    _content.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (picked != null && mounted) setState(() => _expiresAt = picked);
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          widget.suggestion
              ? 'Suggest a memory'
              : widget.record == null
                  ? 'New memory'
                  : 'Edit memory',
          style: text.headlineSmall,
        ),
        const SizedBox(height: AuraSpace.xs),
        Text(
          widget.suggestion
              ? 'Suggestions stay pending until you approve them.'
              : 'This information is stored locally in the active workspace.',
          style: text.bodyMedium?.copyWith(color: AuraColors.textSecondary),
        ),
        const SizedBox(height: AuraSpace.lg),
        TextField(
          controller: _content,
          maxLines: 5,
          minLines: 3,
          decoration: const InputDecoration(
            labelText: 'Information to remember',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AuraSpace.md),
        Row(
          children: <Widget>[
            Expanded(
              child: DropdownButtonFormField<MemoryCategory>(
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items: MemoryCategory.values
                    .map(
                      (MemoryCategory category) =>
                          DropdownMenuItem<MemoryCategory>(
                        value: category,
                        child: Text(category.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (MemoryCategory? value) {
                  if (value != null) setState(() => _category = value);
                },
              ),
            ),
            const SizedBox(width: AuraSpace.md),
            Expanded(
              child: TextField(
                controller: _tags,
                decoration: const InputDecoration(
                  labelText: 'Tags (comma separated)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AuraSpace.md),
        OutlinedButton.icon(
          onPressed: _pickExpiry,
          icon: const Icon(Icons.event_outlined, size: 16),
          label: Text(
            _expiresAt == null
                ? 'Optional expiry date'
                : 'Expires ${_expiresAt!.toIso8601String().substring(0, 10)}',
          ),
        ),
        const SizedBox(height: AuraSpace.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: AuraSpace.sm),
            FilledButton(
              onPressed: () {
                final String content = _content.text.trim();
                if (content.isEmpty) return;
                Navigator.of(context).pop(
                  _MemoryDraft(
                    content: content,
                    category: _category,
                    tags: _tags.text
                        .split(',')
                        .map((String tag) => tag.trim())
                        .where((String tag) => tag.isNotEmpty)
                        .toList(growable: false),
                    expiresAt: _expiresAt,
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: AuraSpace.md),
        Text(message, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: AuraSpace.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: AuraSpace.sm),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: AuraColors.danger,
              ),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ],
    );
  }
}
