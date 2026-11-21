import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/family/domain/family_birthday.dart';
import 'package:aura_hub/features/family/domain/family_member.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FamilyMemberDetails extends StatelessWidget {
  const FamilyMemberDetails({
    super.key,
    required this.member,
    required this.onEdit,
    required this.onDelete,
  });

  final FamilyMember member;
  final Future<void> Function(FamilyMember member) onEdit;
  final Future<void> Function(FamilyMember member) onDelete;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            CircleAvatar(
              radius: 26,
              backgroundColor: AuraColors.secondary.withValues(alpha: 0.18),
              child: Text(
                member.fullName.isEmpty
                    ? '?'
                    : member.fullName[0].toUpperCase(),
                style: const TextStyle(color: AuraColors.secondary),
              ),
            ),
            const SizedBox(width: AuraSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(member.fullName, style: text.headlineSmall),
                  Text(
                    member.relationshipDisplayName,
                    style: text.bodyMedium?.copyWith(
                      color: AuraColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AuraSpace.lg),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              children: <Widget>[
                _DetailRow(
                  icon: Icons.alternate_email_outlined,
                  label: 'Nickname',
                  value: member.nickname,
                ),
                _DetailRow(
                  icon: Icons.record_voice_over_outlined,
                  label: 'Ayush calls them',
                  value: member.addressName,
                ),
                _DetailRow(
                  icon: Icons.auto_awesome_outlined,
                  label: 'AURA addresses them',
                  value: member.auraAddressName,
                ),
                _DetailRow(
                  icon: Icons.cake_outlined,
                  label: 'Birthday',
                  value: _birthdayText(),
                ),
                _CopyableRow(
                  icon: Icons.phone_outlined,
                  label: 'Phone',
                  value: member.phone,
                  onCopy: () => _copy(context, member.phone ?? '', 'Phone'),
                ),
                _CopyableRow(
                  icon: Icons.mail_outline,
                  label: 'Email',
                  value: member.email,
                  onCopy: () => _copy(context, member.email ?? '', 'Email'),
                ),
                _DetailRow(
                  icon: Icons.home_outlined,
                  label: 'Address',
                  value: member.address,
                ),
                if (member.interests.isNotEmpty)
                  _DetailRow(
                    icon: Icons.bookmark_border,
                    label: 'Interests',
                    value: member.interests.join(', '),
                  ),
                if (member.emergencyContact)
                  _DetailRow(
                    icon: Icons.priority_high_rounded,
                    label: 'Emergency contact',
                    value: 'Yes',
                  ),
                if (member.notes != null)
                  _DetailRow(
                    icon: Icons.notes_outlined,
                    label: 'Notes',
                    value: member.notes,
                  ),
                for (final FamilyImportantDate date in member.importantDates)
                  _DetailRow(
                    icon: Icons.event_outlined,
                    label: date.label,
                    value: FamilyBirthdayService.formatDate(date.date),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AuraSpace.md),
        Wrap(
          spacing: AuraSpace.xs,
          runSpacing: AuraSpace.xs,
          children: <Widget>[
            FilledButton.icon(
              onPressed: () => onEdit(member),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit'),
            ),
            OutlinedButton.icon(
              onPressed: () => onDelete(member),
              icon: const Icon(Icons.delete_outline_rounded, size: 16),
              label: const Text('Delete'),
            ),
          ],
        ),
      ],
    );
  }

  String? _birthdayText() {
    final DateTime? birthDate = member.dateOfBirth;
    if (birthDate == null) return null;
    final DateTime next =
        FamilyBirthdayService.nextOccurrence(birthDate) ?? birthDate;
    final int? age = FamilyBirthdayService.ageOn(birthDate, next);
    final String base =
        '${FamilyBirthdayService.formatDate(birthDate)} · next ${FamilyBirthdayService.formatDate(next)}';
    return age == null ? base : '$base · turning $age';
  }

  Future<void> _copy(BuildContext context, String value, String label) async {
    if (value.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied to clipboard')),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.trim().isEmpty) return const SizedBox.shrink();
    final TextTheme text = Theme.of(context).textTheme;
    final Widget labelText = Text(
      label,
      style: text.labelMedium?.copyWith(
        color: AuraColors.textSecondary,
      ),
    );
    final Widget valueText = Text(value!, style: text.bodyMedium);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final bool stacked = constraints.maxWidth < 620 * scale;
        if (stacked) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AuraSpace.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(icon, size: 17, color: AuraColors.secondary),
                const SizedBox(width: AuraSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      labelText,
                      const SizedBox(height: AuraSpace.xxs),
                      valueText,
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: AuraSpace.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, size: 17, color: AuraColors.secondary),
              const SizedBox(width: AuraSpace.sm),
              SizedBox(width: 150, child: labelText),
              Expanded(child: valueText),
            ],
          ),
        );
      },
    );
  }
}

class _CopyableRow extends StatelessWidget {
  const _CopyableRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onCopy,
  });

  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.trim().isEmpty) return const SizedBox.shrink();
    final TextTheme text = Theme.of(context).textTheme;
    final Widget labelText = Text(
      label,
      style: text.labelMedium?.copyWith(
        color: AuraColors.textSecondary,
      ),
    );
    final Widget valueText = Text(value!, style: text.bodyMedium);
    final Widget copyButton = IconButton(
      tooltip: 'Copy $label',
      icon: const Icon(Icons.copy_all_outlined, size: 16),
      onPressed: onCopy,
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final bool stacked = constraints.maxWidth < 620 * scale;
        if (stacked) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AuraSpace.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Icon(icon, size: 17, color: AuraColors.secondary),
                const SizedBox(width: AuraSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      labelText,
                      const SizedBox(height: AuraSpace.xxs),
                      valueText,
                    ],
                  ),
                ),
                copyButton,
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: AuraSpace.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 17, color: AuraColors.secondary),
              const SizedBox(width: AuraSpace.sm),
              SizedBox(width: 150, child: labelText),
              Expanded(child: valueText),
              copyButton,
            ],
          ),
        );
      },
    );
  }
}
