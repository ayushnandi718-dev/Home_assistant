import 'package:aura_hub/core/platform/avatar_image.dart';
import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/family/domain/family_birthday.dart';
import 'package:aura_hub/features/family/domain/family_member.dart';
import 'package:aura_hub/shared/widgets/glass/glass_badge.dart';
import 'package:aura_hub/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';

class FamilyMemberCard extends StatelessWidget {
  const FamilyMemberCard({
    super.key,
    required this.member,
    required this.onTap,
  });

  final FamilyMember member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final DateTime? birthDate = member.dateOfBirth;
    final DateTime? next = birthDate == null
        ? null
        : FamilyBirthdayService.nextOccurrence(birthDate);
    final String birthdayLine = next == null
        ? 'Birthday not saved'
        : '${FamilyBirthdayService.formatDate(next)} · '
            '${FamilyBirthdayService.daysBetween(DateTime.now(), next)} days';

    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AuraSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Avatar(member: member),
          const SizedBox(width: AuraSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  member.displayName,
                  style: text.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AuraSpace.xxs),
                Text(
                  member.relationshipDisplayName,
                  style: text.bodySmall?.copyWith(
                    color: AuraColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AuraSpace.sm),
                if (member.emergencyContact)
                  const Padding(
                    padding: EdgeInsets.only(bottom: AuraSpace.xs),
                    child: GlassStatusBadge(
                      label: 'EMERGENCY CONTACT',
                      color: AuraColors.danger,
                      dense: true,
                    ),
                  ),
                Row(
                  children: <Widget>[
                    Icon(Icons.cake_outlined,
                        size: 14, color: AuraColors.secondary),
                    const SizedBox(width: AuraSpace.xxs),
                    Expanded(
                      child: Text(
                        birthdayLine,
                        style: text.labelSmall?.copyWith(
                          color: AuraColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              size: 18, color: AuraColors.textSecondary),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.member});

  final FamilyMember member;

  @override
  Widget build(BuildContext context) {
    final ImageProvider<Object>? image = avatarImageProvider(member.photoPath);
    final String initial = member.fullName.trim().isEmpty
        ? '?'
        : member.fullName.trim()[0].toUpperCase();

    return CircleAvatar(
      radius: 24,
      backgroundColor: AuraColors.secondary.withValues(alpha: 0.18),
      backgroundImage: image,
      child: image == null
          ? Text(initial, style: const TextStyle(color: AuraColors.secondary))
          : null,
    );
  }
}
