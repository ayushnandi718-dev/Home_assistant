import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/family/domain/family_member.dart';
import 'package:aura_hub/features/family/domain/family_relationship.dart';
import 'package:flutter/material.dart';

/// Add/edit form for one family member. Optional fields stay optional.
class FamilyMemberEditor extends StatefulWidget {
  const FamilyMemberEditor({super.key, this.member});

  final FamilyMember? member;

  @override
  State<FamilyMemberEditor> createState() => _FamilyMemberEditorState();
}

class _FamilyMemberEditorState extends State<FamilyMemberEditor> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullName;
  late final TextEditingController _nickname;
  late final TextEditingController _relationshipLabel;
  late final TextEditingController _addressName;
  late final TextEditingController _auraAddressName;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _address;
  late final TextEditingController _notes;
  late final TextEditingController _photoPath;
  late final TextEditingController _interests;
  late FamilyRelationship _relationship;
  DateTime? _dateOfBirth;
  bool _emergencyContact = false;

  @override
  void initState() {
    super.initState();
    final FamilyMember? member = widget.member;
    _fullName = TextEditingController(text: member?.fullName ?? '');
    _nickname = TextEditingController(text: member?.nickname ?? '');
    _relationshipLabel =
        TextEditingController(text: member?.relationshipLabel ?? '');
    _addressName = TextEditingController(text: member?.addressName ?? '');
    _auraAddressName =
        TextEditingController(text: member?.auraAddressName ?? '');
    _phone = TextEditingController(text: member?.phone ?? '');
    _email = TextEditingController(text: member?.email ?? '');
    _address = TextEditingController(text: member?.address ?? '');
    _notes = TextEditingController(text: member?.notes ?? '');
    _photoPath = TextEditingController(text: member?.photoPath ?? '');
    _interests = TextEditingController(
      text: member == null ? '' : member.interests.join(', '),
    );
    _relationship = member?.relationship ?? FamilyRelationship.other;
    _dateOfBirth = member?.dateOfBirth;
    _emergencyContact = member?.emergencyContact ?? false;
  }

  @override
  void dispose() {
    _fullName.dispose();
    _nickname.dispose();
    _relationshipLabel.dispose();
    _addressName.dispose();
    _auraAddressName.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _notes.dispose();
    _photoPath.dispose();
    _interests.dispose();
    super.dispose();
  }

  Future<void> _pickBirthday() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      helpText: 'Date of birth (optional)',
      initialDate: _dateOfBirth ?? DateTime(2000, 1, 1),
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year, now.month, now.day),
    );
    if (picked != null && mounted) setState(() => _dateOfBirth = picked);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final DateTime now = DateTime.now();
    final FamilyMember? existing = widget.member;
    final List<String> interests = _interests.text
        .split(',')
        .map((String value) => value.trim())
        .where((String value) => value.isNotEmpty)
        .toList(growable: false);

    final FamilyMember member = FamilyMember(
      id: existing?.id ?? FamilyMember.newId(),
      fullName: _fullName.text.trim(),
      relationship: _relationship,
      relationshipLabel: _relationship == FamilyRelationship.other
          ? _clean(_relationshipLabel.text)
          : null,
      nickname: _clean(_nickname.text),
      addressName: _clean(_addressName.text),
      auraAddressName: _clean(_auraAddressName.text),
      dateOfBirth: _dateOfBirth,
      phone: _clean(_phone.text),
      email: _clean(_email.text),
      address: _clean(_address.text),
      photoPath: _clean(_photoPath.text),
      notes: _clean(_notes.text),
      emergencyContact: _emergencyContact,
      interests: interests,
      importantDates: existing?.importantDates ?? const <FamilyImportantDate>[],
      customFields: existing?.customFields ?? const <String, String>{},
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    Navigator.of(context).pop<FamilyMember>(member);
  }

  String? _clean(String value) {
    final String clean = value.trim();
    return clean.isEmpty ? null : clean;
  }

  String? _validateEmail(String? value) {
    final String? clean = _clean(value ?? '');
    if (clean == null) return null;
    if (!clean.contains('@') || !clean.contains('.')) {
      return 'Enter a valid email or leave it empty.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          widget.member == null ? 'Add family member' : 'Edit family member',
          style: text.headlineSmall,
        ),
        const SizedBox(height: AuraSpace.sm),
        Text(
          'Only the name and relationship are required. Everything else can be '
          'added later.',
          style: text.bodyMedium?.copyWith(color: AuraColors.textSecondary),
        ),
        const SizedBox(height: AuraSpace.lg),
        Flexible(
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                children: <Widget>[
                  _field(
                    controller: _fullName,
                    label: 'Full name',
                    icon: Icons.person_outline,
                    validator: (String? value) =>
                        value == null || value.trim().isEmpty
                            ? 'Enter a full name.'
                            : null,
                  ),
                  const SizedBox(height: AuraSpace.sm),
                  _field(
                    controller: _nickname,
                    label: 'Nickname (optional)',
                    icon: Icons.alternate_email,
                  ),
                  const SizedBox(height: AuraSpace.sm),
                  DropdownButtonFormField<FamilyRelationship>(
                    initialValue: _relationship,
                    decoration: const InputDecoration(
                      labelText: 'Relationship',
                      border: OutlineInputBorder(),
                    ),
                    items: <DropdownMenuItem<FamilyRelationship>>[
                      for (final FamilyRelationship value
                          in FamilyRelationship.values)
                        DropdownMenuItem<FamilyRelationship>(
                          value: value,
                          child: Text(value.label),
                        ),
                    ],
                    onChanged: (FamilyRelationship? value) {
                      if (value != null) {
                        setState(() => _relationship = value);
                      }
                    },
                  ),
                  if (_relationship == FamilyRelationship.other) ...<Widget>[
                    const SizedBox(height: AuraSpace.sm),
                    _field(
                      controller: _relationshipLabel,
                      label: 'Custom relationship (e.g. neighbour)',
                      icon: Icons.group_outlined,
                      validator: (String? value) =>
                          value == null || value.trim().isEmpty
                              ? 'Enter a relationship label.'
                              : null,
                    ),
                  ],
                  const SizedBox(height: AuraSpace.sm),
                  _field(
                    controller: _addressName,
                    label: 'How Ayush addresses them (optional)',
                    icon: Icons.record_voice_over_outlined,
                  ),
                  const SizedBox(height: AuraSpace.sm),
                  _field(
                    controller: _auraAddressName,
                    label: 'How AURA should address them (optional)',
                    icon: Icons.auto_awesome_outlined,
                  ),
                  const SizedBox(height: AuraSpace.sm),
                  _birthdayRow(text),
                  const SizedBox(height: AuraSpace.sm),
                  _field(
                    controller: _phone,
                    label: 'Phone (optional)',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: AuraSpace.sm),
                  _field(
                    controller: _email,
                    label: 'Email (optional)',
                    icon: Icons.mail_outline,
                    keyboardType: TextInputType.emailAddress,
                    validator: _validateEmail,
                  ),
                  const SizedBox(height: AuraSpace.sm),
                  _field(
                    controller: _address,
                    label: 'Address (optional)',
                    icon: Icons.home_outlined,
                  ),
                  const SizedBox(height: AuraSpace.sm),
                  _field(
                    controller: _interests,
                    label: 'Interests, separated by commas (optional)',
                    icon: Icons.bookmark_border,
                  ),
                  const SizedBox(height: AuraSpace.sm),
                  _field(
                    controller: _photoPath,
                    label: 'Profile photo path (optional)',
                    icon: Icons.image_outlined,
                  ),
                  const SizedBox(height: AuraSpace.sm),
                  _field(
                    controller: _notes,
                    label: 'Important notes (optional)',
                    icon: Icons.notes_outlined,
                    maxLines: 3,
                  ),
                  const SizedBox(height: AuraSpace.xs),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Emergency contact'),
                    subtitle: const Text('Mark as important in the directory.'),
                    value: _emergencyContact,
                    onChanged: (bool value) =>
                        setState(() => _emergencyContact = value),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AuraSpace.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: AuraSpace.xs),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined, size: 16),
              label:
                  Text(widget.member == null ? 'Add member' : 'Save changes'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _birthdayRow(TextTheme text) {
    final String label = _dateOfBirth == null
        ? 'Date of birth (optional)'
        : '${_dateOfBirth!.day} ${_month(_dateOfBirth!.month)} ${_dateOfBirth!.year}';
    final Widget dateText = Text(label, style: text.bodyMedium);
    final List<Widget> actions = <Widget>[
      if (_dateOfBirth != null)
        IconButton(
          tooltip: 'Clear birthday',
          icon: const Icon(Icons.close, size: 16),
          onPressed: () => setState(() => _dateOfBirth = null),
        ),
      TextButton(
        onPressed: _pickBirthday,
        child: const Text('Pick'),
      ),
    ];
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final bool stacked = constraints.maxWidth < 620 * scale;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AuraRadius.control),
            border: Border.all(color: AuraColors.border),
          ),
          child: stacked
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AuraSpace.sm,
                    vertical: AuraSpace.xs,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const Icon(Icons.cake_outlined,
                              color: AuraColors.secondary),
                          const SizedBox(width: AuraSpace.sm),
                          Expanded(child: dateText),
                        ],
                      ),
                      const SizedBox(height: AuraSpace.xxs),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: actions,
                      ),
                    ],
                  ),
                )
              : ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: AuraSpace.sm),
                  leading: const Icon(Icons.cake_outlined,
                      color: AuraColors.secondary),
                  title: dateText,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: actions,
                  ),
                ),
        );
      },
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18),
        border: const OutlineInputBorder(),
      ),
    );
  }

  static String _month(int month) {
    const List<String> names = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return names[month - 1];
  }
}
