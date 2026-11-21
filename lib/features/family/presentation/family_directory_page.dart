import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/family/domain/family_birthday.dart';
import 'package:aura_hub/features/family/domain/family_directory_service.dart';
import 'package:aura_hub/features/family/domain/family_member.dart';
import 'package:aura_hub/features/family/domain/family_relationship.dart';
import 'package:aura_hub/features/family/presentation/family_import_export_dialog.dart';
import 'package:aura_hub/features/family/presentation/family_member_details.dart';
import 'package:aura_hub/features/family/presentation/family_member_editor.dart';
import 'package:aura_hub/features/family/presentation/family_member_card.dart';
import 'package:aura_hub/features/family/presentation/family_providers.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:aura_hub/shared/widgets/aura_scroll_area.dart';
import 'package:aura_hub/shared/widgets/glass/glass_dialog.dart';
import 'package:aura_hub/shared/widgets/info_banner.dart';
import 'package:aura_hub/shared/widgets/page_header.dart';
import 'package:aura_hub/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Relationship directory for the shared FAMILY workspace.
///
/// The page never reads family records while AYUSH is active. The guard below
/// is a separate widget so the family providers are not even instantiated in
/// the private workspace.
class FamilyDirectoryPage extends ConsumerWidget {
  const FamilyDirectoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AuraProfile profile = ref.watch(activeProfileProvider);
    if (profile != AuraProfile.family) {
      return const _FamilyWorkspaceGuard();
    }
    return const _FamilyDirectoryView();
  }
}

class _FamilyWorkspaceGuard extends ConsumerWidget {
  const _FamilyWorkspaceGuard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AuraColors.background,
      body: AuraScrollArea(
        child: Padding(
          padding: const EdgeInsets.all(AuraSpace.lg),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: SurfaceCard(
                padding: const EdgeInsets.all(AuraSpace.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.lock_outline_rounded,
                        size: 46, color: AuraColors.secondary),
                    const SizedBox(height: AuraSpace.md),
                    Text('Family workspace required',
                        style: text.headlineSmall, textAlign: TextAlign.center),
                    const SizedBox(height: AuraSpace.sm),
                    Text(
                      'The Family Directory lives in the shared FAMILY workspace. '
                      'It is not available while the private AYUSH workspace is '
                      'active, and no family records are loaded here.',
                      style: text.bodyMedium?.copyWith(
                        color: AuraColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AuraSpace.lg),
                    FilledButton.icon(
                      onPressed: () => ref
                          .read(profileSessionProvider.notifier)
                          .openFamily(),
                      icon: const Icon(Icons.groups_outlined, size: 18),
                      label: const Text('Switch to FAMILY'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FamilyDirectoryView extends ConsumerStatefulWidget {
  const _FamilyDirectoryView();

  @override
  ConsumerState<_FamilyDirectoryView> createState() =>
      _FamilyDirectoryViewState();
}

class _FamilyDirectoryViewState extends ConsumerState<_FamilyDirectoryView> {
  final TextEditingController _search = TextEditingController();
  FamilyRelationship? _relationshipFilter;
  FamilySortMode _sort = FamilySortMode.alphabetical;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _showEditor({FamilyMember? member}) async {
    final FamilyMember? saved = await showGlassDialog<FamilyMember>(
      context: context,
      width: 620,
      child: FamilyMemberEditor(member: member),
    );
    if (saved == null || !mounted) return;
    final FamilyDirectoryController controller =
        ref.read(familyDirectoryControllerProvider.notifier);
    if (member == null) {
      await controller.add(saved);
    } else {
      await controller.update(saved);
    }
  }

  Future<void> _showDetails(FamilyMember member) async {
    await showGlassDialog<void>(
      context: context,
      width: 620,
      child: FamilyMemberDetails(
        member: member,
        onEdit: (FamilyMember current) async {
          final NavigatorState navigator = Navigator.of(context);
          final FamilyMember? saved = await showGlassDialog<FamilyMember>(
            context: context,
            width: 620,
            child: FamilyMemberEditor(member: current),
          );
          if (saved == null) return;
          await ref
              .read(familyDirectoryControllerProvider.notifier)
              .update(saved);
          if (navigator.mounted) navigator.pop();
        },
        onDelete: (FamilyMember current) async => _confirmDelete(current),
      ),
    );
  }

  Future<void> _confirmDelete(FamilyMember member) async {
    final bool? confirmed = await showGlassDialog<bool>(
      context: context,
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Delete ${member.displayName}?',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: AuraSpace.sm),
          Text(
            'This removes the saved directory record from the FAMILY workspace.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AuraSpace.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: AuraSpace.xs),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                label: const Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref
        .read(familyDirectoryControllerProvider.notifier)
        .remove(member.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${member.displayName} removed')),
      );
    }
  }

  Future<void> _showImportExport(List<FamilyMember> members) async {
    await showGlassDialog<void>(
      context: context,
      width: 680,
      child: FamilyImportExportDialog(
        members: members,
        onImport: (List<FamilyMember> incoming, bool overwrite) async {
          return ref
              .read(familyDirectoryControllerProvider.notifier)
              .importMembers(
                  incoming: incoming, overwriteDuplicates: overwrite);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<FamilyMember> members = ref.watch(familyDirectoryProvider);
    final DateTime now = DateTime.now();
    final List<FamilyMember> visible = FamilyDirectoryService.query(
      members,
      search: _search.text,
      relationship: _relationshipFilter,
      sort: _sort,
      now: now,
    );
    final List<FamilyBirthday> birthdays = FamilyBirthdayService.upcoming(
      members,
      now: now,
      limit: 5,
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool dense = auraDenseLayout(
          context,
          availableHeight: constraints.maxHeight,
        );
        return Scaffold(
          backgroundColor: AuraColors.background,
          body: AuraScrollArea(
            child: Padding(
              padding: EdgeInsets.all(
                  pageHorizontalPadding(MediaQuery.sizeOf(context).width)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  PageHeader(
                    eyebrow: 'FAMILY WORKSPACE',
                    title: 'Family Directory',
                    description:
                        'Keep names, relationships, birthdays and contact '
                        'details in one shared household directory.',
                    icon: Icons.groups_outlined,
                    accent: AuraColors.secondary,
                    compact: dense,
                    trailing: Wrap(
                      spacing: AuraSpace.xs,
                      runSpacing: AuraSpace.xs,
                      children: <Widget>[
                        OutlinedButton.icon(
                          onPressed: () => _showImportExport(members),
                          icon: const Icon(Icons.import_export_outlined,
                              size: 16),
                          label: const Text('Import / Export'),
                        ),
                        FilledButton.icon(
                          onPressed: () => _showEditor(),
                          icon: const Icon(Icons.person_add_alt_1_outlined,
                              size: 16),
                          label: const Text('Add member'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AuraSpace.lg),
                  const InfoBanner(
                    title: 'Shared by design',
                    message:
                        'These records belong to the FAMILY workspace. They '
                        'are not private AYUSH data, are never sent to AI, and can '
                        'be opened without a PIN.',
                    icon: Icons.groups_outlined,
                    tone: AuraBannerTone.privacy,
                  ),
                  const SizedBox(height: AuraSpace.lg),
                  _StatsRow(members: members, birthdays: birthdays),
                  const SizedBox(height: AuraSpace.lg),
                  _DirectoryControls(
                    search: _search,
                    relationshipFilter: _relationshipFilter,
                    sort: _sort,
                    dense: dense,
                    onSearchChanged: () => setState(() {}),
                    onRelationshipChanged: (FamilyRelationship? value) =>
                        setState(() => _relationshipFilter = value),
                    onSortChanged: (FamilySortMode value) =>
                        setState(() => _sort = value),
                  ),
                  const SizedBox(height: AuraSpace.md),
                  _BirthdayPanel(birthdays: birthdays),
                  const SizedBox(height: AuraSpace.lg),
                  _MemberList(
                    members: visible,
                    hasFilters: _search.text.trim().isNotEmpty ||
                        _relationshipFilter != null,
                    onTap: _showDetails,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.members, required this.birthdays});

  final List<FamilyMember> members;
  final List<FamilyBirthday> birthdays;

  @override
  Widget build(BuildContext context) {
    final int emergency =
        members.where((FamilyMember member) => member.emergencyContact).length;
    final int birthdaysSaved = members
        .where((FamilyMember member) => member.dateOfBirth != null)
        .length;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : AuraBreakpoints.content;
        final double cardWidth =
            width >= 900 ? (width - AuraSpace.md) / 3 : width;
        return Wrap(
          spacing: AuraSpace.md,
          runSpacing: AuraSpace.md,
          children: <Widget>[
            SizedBox(
              width: cardWidth,
              child: _StatCard(
                icon: Icons.people_outline_rounded,
                label: 'Saved members',
                value: '${members.length}',
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _StatCard(
                icon: Icons.cake_outlined,
                label: 'Birthdays this year',
                value: '$birthdaysSaved',
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _StatCard(
                icon: Icons.priority_high_rounded,
                label: 'Emergency contacts',
                value: '$emergency',
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return SurfaceCard(
      padding: const EdgeInsets.all(AuraSpace.md),
      child: Row(
        children: <Widget>[
          Icon(icon, color: AuraColors.secondary),
          const SizedBox(width: AuraSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(value, style: text.headlineSmall),
                Text(label,
                    style: text.labelSmall?.copyWith(
                      color: AuraColors.textSecondary,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DirectoryControls extends StatelessWidget {
  const _DirectoryControls({
    required this.search,
    required this.relationshipFilter,
    required this.sort,
    required this.dense,
    required this.onSearchChanged,
    required this.onRelationshipChanged,
    required this.onSortChanged,
  });

  final TextEditingController search;
  final FamilyRelationship? relationshipFilter;
  final FamilySortMode sort;
  final bool dense;
  final VoidCallback onSearchChanged;
  final ValueChanged<FamilyRelationship?> onRelationshipChanged;
  final ValueChanged<FamilySortMode> onSortChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : AuraBreakpoints.content;
        final double fieldWidth =
            width >= 1000 ? (width - AuraSpace.md * 2) / 3 : width;
        return Wrap(
          spacing: AuraSpace.md,
          runSpacing: AuraSpace.md,
          children: <Widget>[
            SizedBox(
              width: fieldWidth,
              child: TextField(
                controller: search,
                onChanged: (_) => onSearchChanged(),
                decoration: InputDecoration(
                  labelText: 'Search name or relationship',
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  border: const OutlineInputBorder(),
                  isDense: dense,
                ),
              ),
            ),
            SizedBox(
              width: fieldWidth,
              child: DropdownButtonFormField<FamilyRelationship?>(
                isExpanded: true,
                initialValue: relationshipFilter,
                decoration: const InputDecoration(
                  labelText: 'Relationship',
                  border: OutlineInputBorder(),
                ),
                items: <DropdownMenuItem<FamilyRelationship?>>[
                  const DropdownMenuItem<FamilyRelationship?>(
                    value: null,
                    child: Text('All relationships'),
                  ),
                  for (final FamilyRelationship value
                      in FamilyRelationship.values)
                    DropdownMenuItem<FamilyRelationship?>(
                      value: value,
                      child: Text(value.label),
                    ),
                ],
                onChanged: onRelationshipChanged,
              ),
            ),
            SizedBox(
              width: fieldWidth,
              child: DropdownButtonFormField<FamilySortMode>(
                isExpanded: true,
                initialValue: sort,
                decoration: const InputDecoration(
                  labelText: 'Sort by',
                  border: OutlineInputBorder(),
                ),
                items: const <DropdownMenuItem<FamilySortMode>>[
                  DropdownMenuItem(
                    value: FamilySortMode.alphabetical,
                    child: Text('Name A–Z'),
                  ),
                  DropdownMenuItem(
                    value: FamilySortMode.upcomingBirthday,
                    child: Text('Upcoming birthday'),
                  ),
                  DropdownMenuItem(
                    value: FamilySortMode.recentlyUpdated,
                    child: Text('Recently updated'),
                  ),
                ],
                onChanged: (FamilySortMode? value) {
                  if (value != null) onSortChanged(value);
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BirthdayPanel extends StatelessWidget {
  const _BirthdayPanel({required this.birthdays});

  final List<FamilyBirthday> birthdays;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return SurfaceCard(
      padding: const EdgeInsets.all(AuraSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.event_available_outlined,
                  size: 18, color: AuraColors.warning),
              const SizedBox(width: AuraSpace.xs),
              Expanded(
                child: Text(
                  'Upcoming birthdays',
                  style: text.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AuraSpace.sm),
          if (birthdays.isEmpty)
            Text(
              'Add a date of birth to see upcoming birthdays here.',
              style: text.bodySmall?.copyWith(color: AuraColors.textSecondary),
            )
          else
            Wrap(
              spacing: AuraSpace.sm,
              runSpacing: AuraSpace.xs,
              children: <Widget>[
                for (final FamilyBirthday birthday in birthdays)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        CircleAvatar(
                          radius: 12,
                          backgroundColor:
                              AuraColors.warning.withValues(alpha: 0.16),
                          child: Text(
                            birthday.member.fullName.isEmpty
                                ? '?'
                                : birthday.member.fullName[0].toUpperCase(),
                            style: const TextStyle(
                              color: AuraColors.warning,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const SizedBox(width: AuraSpace.xs),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                birthday.member.displayName,
                                style: text.labelMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                birthday.description,
                                style: text.labelSmall?.copyWith(
                                  color: AuraColors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _MemberList extends StatelessWidget {
  const _MemberList({
    required this.members,
    required this.hasFilters,
    required this.onTap,
  });

  final List<FamilyMember> members;
  final bool hasFilters;
  final ValueChanged<FamilyMember> onTap;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return SurfaceCard(
        padding: const EdgeInsets.all(AuraSpace.xl),
        child: Center(
          child: Column(
            children: <Widget>[
              Icon(Icons.person_search_outlined,
                  size: 38, color: AuraColors.textSecondary),
              const SizedBox(height: AuraSpace.sm),
              Text(
                hasFilters
                    ? 'No members match those filters.'
                    : 'No family members yet.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AuraSpace.xxs),
              Text(
                hasFilters
                    ? 'Try a different name or relationship.'
                    : 'Use “Add member” to create the first record.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AuraColors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : AuraBreakpoints.content;
        final int columns = width >= 1050 ? 2 : 1;
        final double cardWidth =
            columns == 2 ? (width - AuraSpace.md) / 2 : width;
        return Wrap(
          spacing: AuraSpace.md,
          runSpacing: AuraSpace.md,
          children: <Widget>[
            for (final FamilyMember member in members)
              SizedBox(
                width: cardWidth,
                child: FamilyMemberCard(
                  member: member,
                  onTap: () => onTap(member),
                ),
              ),
          ],
        );
      },
    );
  }
}
