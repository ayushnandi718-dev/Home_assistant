import 'dart:async';

import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_glass.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/domain/pin_validation.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:aura_hub/features/security/domain/ayush_security_settings.dart';
import 'package:aura_hub/features/security/presentation/security_providers.dart';
import 'package:aura_hub/shared/widgets/aura_scroll_area.dart';
import 'package:aura_hub/shared/widgets/glass/glass_container.dart';
import 'package:aura_hub/shared/widgets/info_banner.dart';
import 'package:aura_hub/shared/widgets/page_header.dart';
import 'package:aura_hub/shared/widgets/status_pill.dart';
import 'package:aura_hub/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Below this width the auto-lock control is stacked under its label instead
/// of squeezing it, matching the responsive rows in Settings.
const double _kStackBreakpoint = 620;

/// Real workspace switcher for the two supported profiles.
///
/// FAMILY opens directly. AYUSH requires a PIN that is configured on first use
/// and verified on every unlock. The active profile is shown in the app bar and
/// drives per-profile notification storage and the service access guard.
class ProfilesPage extends ConsumerWidget {
  const ProfilesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ProfileSession session = ref.watch(profileSessionProvider);
    final double padding =
        pageHorizontalPadding(MediaQuery.sizeOf(context).width);

    return AuraScrollArea(
      padding:
          EdgeInsets.fromLTRB(padding, AuraSpace.lg, padding, AuraSpace.xxl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AuraBreakpoints.content),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              PageHeader(
                eyebrow: 'Workspace',
                title: 'Profiles & Security',
                description:
                    'Two isolated workspaces: a private AYUSH profile and a shared FAMILY profile for the household.',
                icon: Icons.shield_outlined,
                accent: AuraColors.secondary,
                trailing: StatusPill(
                  label: 'ACTIVE: ${session.profile.label}',
                  color: session.privateSessionActive
                      ? AuraColors.secondary
                      : AuraColors.primary,
                  icon: session.privateSessionActive
                      ? Icons.lock_rounded
                      : Icons.family_restroom_outlined,
                ),
              ),
              const SizedBox(height: AuraSpace.lg),
              const InfoBanner(
                title: 'What this lock protects',
                message:
                    'The PIN is stored locally as a salted PBKDF2-HMAC-SHA256 '
                    'verifier and gates the private AYUSH workspace on this '
                    'device. It is not a cloud account or an OS credential '
                    'vault. Service-level checks keep private data out of the '
                    'shared FAMILY scope.',
                tone: AuraBannerTone.privacy,
              ),
              const SizedBox(height: AuraSpace.lg),
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final bool wide = constraints.maxWidth >= 900;
                  final List<Widget> cards = <Widget>[
                    const _FamilyCard(),
                    const _AyushCard(),
                  ];
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(child: cards[0]),
                        const SizedBox(width: AuraSpace.lg),
                        Expanded(child: cards[1]),
                      ],
                    );
                  }
                  return Column(
                    children: <Widget>[
                      cards[0],
                      const SizedBox(height: AuraSpace.lg),
                      cards[1],
                    ],
                  );
                },
              ),
              const SizedBox(height: AuraSpace.lg),
              if (session.privateSessionActive) ...<Widget>[
                const _PinChangeCard(),
                const SizedBox(height: AuraSpace.lg),
                const _AutoLockCard(),
                const SizedBox(height: AuraSpace.lg),
              ],
              const _IsolationCard(),
              const SizedBox(height: AuraSpace.md),
              const _SecurityInformationCard(),
            ],
          ),
        ),
      ),
    );
  }
}

class _FamilyCard extends ConsumerWidget {
  const _FamilyCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ProfileSession session = ref.watch(profileSessionProvider);
    final bool active = session.profile == AuraProfile.family;
    final TextTheme text = Theme.of(context).textTheme;

    return SurfaceCard(
      surface: active ? AuraGlassSurface.strong : AuraGlassSurface.panel,
      borderColor: active ? AuraColors.primary.withValues(alpha: 0.42) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              GlassContainer(
                width: 40,
                height: 40,
                padding: EdgeInsets.zero,
                radius: 12,
                blur: 0,
                fill: 0.5,
                showHighlight: false,
                borderColor: AuraColors.primary.withValues(alpha: 0.3),
                child: const Icon(Icons.family_restroom_outlined,
                    size: 20, color: AuraColors.primary),
              ),
              const SizedBox(width: AuraSpace.sm),
              Expanded(child: Text('FAMILY', style: text.titleLarge)),
              StatusPill(
                label: active ? 'ACTIVE' : 'AVAILABLE',
                color: active ? AuraColors.success : AuraColors.textSecondary,
                icon: active ? Icons.check_circle_outline : null,
                showDot: false,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: AuraSpace.md),
          Text(
            'Open shared workspace',
            style: text.titleMedium,
          ),
          const SizedBox(height: AuraSpace.xs),
          Text(
            'The household workspace opens directly without a PIN. It shows '
            'shared dashboard state and shared notifications only.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: AuraSpace.lg),
          SizedBox(
            width: double.infinity,
            child: active
                ? OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.check_circle_outline_rounded,
                        size: 17),
                    label: const Text('Currently active'),
                  )
                : FilledButton.icon(
                    onPressed: () =>
                        ref.read(profileSessionProvider.notifier).openFamily(),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                    label: const Text('Switch to FAMILY'),
                  ),
          ),
        ],
      ),
    );
  }
}

class _AyushCard extends ConsumerStatefulWidget {
  const _AyushCard();

  @override
  ConsumerState<_AyushCard> createState() => _AyushCardState();
}

class _AyushCardState extends ConsumerState<_AyushCard> {
  final TextEditingController _pin = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  /// The form owns its own per-keystroke rebuild. The card only needs to rebuild
  /// when a previously submitted error is no longer relevant.
  void _handleInputChanged() {
    if (!mounted || _error == null) return;
    setState(() => _error = null);
  }

  Future<void> _submit({required bool needsSetup}) async {
    final String entered = _pin.text;
    final PinValidationResult validation = PinValidation.evaluate(
      pin: entered,
      needsSetup: needsSetup,
      confirmation: _confirm.text,
    );
    if (!validation.isValid) {
      setState(() => _error = validation.message);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final ProfileSessionController controller =
        ref.read(profileSessionProvider.notifier);
    try {
      final ProfileUnlockResult result = needsSetup
          ? await controller.setupPin(entered)
          : await controller.unlockAyush(entered);
      if (!mounted) return;
      setState(() => _busy = false);

      switch (result) {
        case ProfileUnlockResult.success:
          _clearFields();
          break;
        case ProfileUnlockResult.invalidPin:
          final int remaining = controller.remainingAttempts;
          setState(() => _error = remaining > 0
              ? 'Incorrect PIN. $remaining attempt(s) remaining.'
              : 'Incorrect PIN.');
          _clearFields();
          break;
        case ProfileUnlockResult.rateLimited:
          setState(() => _error =
              'Too many attempts. Please wait a minute before trying again.');
          _clearFields();
          break;
        case ProfileUnlockResult.needsSetup:
          setState(() => _error =
              'No PIN is configured yet. Set one below to unlock AYUSH.');
          break;
        case ProfileUnlockResult.unavailable:
          setState(() => _error = 'The private workspace is unavailable.');
          break;
      }
    } on ArgumentError catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message?.toString() ?? 'Invalid PIN.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not update the workspace. Please try again.';
      });
    }
  }

  void _clearFields() {
    _pin.clear();
    _confirm.clear();
  }

  @override
  Widget build(BuildContext context) {
    final ProfileSession session = ref.watch(profileSessionProvider);
    final AsyncValue<bool> pinConfigured =
        ref.watch(ayushPinConfiguredProvider);
    final bool unlocked = session.privateSessionActive;
    final TextTheme text = Theme.of(context).textTheme;

    return SurfaceCard(
      surface: unlocked ? AuraGlassSurface.strong : AuraGlassSurface.panel,
      borderColor:
          unlocked ? AuraColors.secondary.withValues(alpha: 0.42) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              GlassContainer(
                width: 40,
                height: 40,
                padding: EdgeInsets.zero,
                radius: 12,
                blur: 0,
                fill: 0.5,
                showHighlight: false,
                borderColor: AuraColors.secondary.withValues(alpha: 0.3),
                child: const Icon(Icons.lock_outline_rounded,
                    size: 20, color: AuraColors.secondary),
              ),
              const SizedBox(width: AuraSpace.sm),
              Expanded(child: Text('AYUSH', style: text.titleLarge)),
              StatusPill(
                label: unlocked ? 'UNLOCKED' : 'LOCKED',
                color: unlocked ? AuraColors.success : AuraColors.warning,
                icon: unlocked
                    ? Icons.lock_open_outlined
                    : Icons.lock_outline_rounded,
                showDot: false,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: AuraSpace.md),
          Text('Private workspace', style: text.titleMedium),
          const SizedBox(height: AuraSpace.xs),
          Text(
            'Private integrations, AI context, tasks and logs stay in this '
            'workspace and never appear in FAMILY.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: AuraSpace.lg),
          if (unlocked)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  ref.read(profileSessionProvider.notifier).lock();
                  _clearFields();
                },
                icon: const Icon(Icons.lock_outline_rounded, size: 17),
                label: const Text('Lock private workspace'),
              ),
            )
          else
            pinConfigured.when(
              loading: () => const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (Object error, StackTrace stack) => Text(
                'Could not read PIN configuration: $error',
                style: text.bodySmall?.copyWith(color: AuraColors.danger),
              ),
              data: (bool configured) {
                final bool needsSetup = !configured;
                return _PinForm(
                  needsSetup: needsSetup,
                  pin: _pin,
                  confirm: _confirm,
                  obscure: _obscure,
                  busy: _busy,
                  error: _error,
                  onInputChanged: _handleInputChanged,
                  onToggleObscure: () => setState(() => _obscure = !_obscure),
                  onSubmit: () => _submit(needsSetup: needsSetup),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _PinForm extends StatefulWidget {
  const _PinForm({
    required this.needsSetup,
    required this.pin,
    required this.confirm,
    required this.obscure,
    required this.busy,
    required this.error,
    required this.onInputChanged,
    required this.onToggleObscure,
    required this.onSubmit,
  });

  final bool needsSetup;
  final TextEditingController pin;
  final TextEditingController confirm;
  final bool obscure;
  final bool busy;
  final String? error;
  final VoidCallback onInputChanged;
  final VoidCallback onToggleObscure;
  final VoidCallback onSubmit;

  @override
  State<_PinForm> createState() => _PinFormState();
}

/// Validation feedback and counters live here, so a keystroke only rebuilds the
/// small form instead of the surrounding glass card and profile page.
class _PinFormState extends State<_PinForm> {
  final GlobalKey _confirmFieldKey = GlobalKey();
  late final FocusNode _pinFocus;
  late final FocusNode _confirmFocus;

  @override
  void initState() {
    super.initState();
    _pinFocus = FocusNode(debugLabel: 'AYUSH profile new PIN');
    _confirmFocus = FocusNode(debugLabel: 'AYUSH profile confirm PIN');
    _confirmFocus.addListener(() {
      if (_confirmFocus.hasFocus) _scrollConfirmIntoView();
    });
    widget.pin.addListener(_handleInputChanged);
    widget.confirm.addListener(_handleInputChanged);
  }

  void _scrollConfirmIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final BuildContext? fieldContext = _confirmFieldKey.currentContext;
      if (fieldContext == null || !fieldContext.mounted) return;
      Scrollable.ensureVisible(
        fieldContext,
        alignment: 0.75,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void didUpdateWidget(_PinForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pin != widget.pin) {
      oldWidget.pin.removeListener(_handleInputChanged);
      widget.pin.addListener(_handleInputChanged);
    }
    if (oldWidget.confirm != widget.confirm) {
      oldWidget.confirm.removeListener(_handleInputChanged);
      widget.confirm.addListener(_handleInputChanged);
    }
  }

  void _handleInputChanged() {
    if (!mounted) return;
    setState(() {});
    widget.onInputChanged();
  }

  @override
  void dispose() {
    widget.pin.removeListener(_handleInputChanged);
    widget.confirm.removeListener(_handleInputChanged);
    _pinFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  List<TextInputFormatter> get _digitsOnly =>
      <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly];

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final PinValidationResult validation = PinValidation.evaluate(
      pin: widget.pin.text,
      needsSetup: widget.needsSetup,
      confirmation: widget.confirm.text,
    );
    final String? message = widget.error ??
        ((widget.pin.text.isEmpty && widget.confirm.text.isEmpty)
            ? null
            : validation.message);
    final bool canSubmit = validation.isValid && !widget.busy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          widget.needsSetup ? 'Create your AYUSH PIN' : 'Enter your AYUSH PIN',
          style: text.titleSmall,
        ),
        const SizedBox(height: AuraSpace.xs),
        Text(
          '${PinValidation.minLength}-${PinValidation.maxLength} digits, numbers only.',
          style: text.bodySmall,
        ),
        const SizedBox(height: AuraSpace.sm),
        TextField(
          controller: widget.pin,
          focusNode: _pinFocus,
          obscureText: widget.obscure,
          keyboardType: TextInputType.number,
          textInputAction:
              widget.needsSetup ? TextInputAction.next : TextInputAction.done,
          autocorrect: false,
          enableSuggestions: false,
          inputFormatters: _digitsOnly,
          maxLength: PinValidation.maxLength,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          enabled: !widget.busy,
          onSubmitted: (_) {
            if (widget.needsSetup) {
              FocusScope.of(context).requestFocus(_confirmFocus);
            } else if (canSubmit) {
              widget.onSubmit();
            }
          },
          decoration: InputDecoration(
            labelText: widget.needsSetup ? 'New PIN' : 'PIN',
            prefixIcon: const Icon(Icons.pin_outlined, size: 18),
            suffixIcon: IconButton(
              tooltip: widget.obscure ? 'Show PIN' : 'Hide PIN',
              onPressed: widget.onToggleObscure,
              icon: Icon(
                widget.obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 18,
              ),
            ),
            counterText: '${widget.pin.text.length}/${PinValidation.maxLength}',
            border: const OutlineInputBorder(),
          ),
        ),
        if (widget.needsSetup) ...<Widget>[
          const SizedBox(height: AuraSpace.sm),
          TextField(
            key: _confirmFieldKey,
            controller: widget.confirm,
            focusNode: _confirmFocus,
            obscureText: widget.obscure,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: _digitsOnly,
            maxLength: PinValidation.maxLength,
            maxLengthEnforcement: MaxLengthEnforcement.enforced,
            enabled: !widget.busy,
            onSubmitted: (_) {
              if (canSubmit) widget.onSubmit();
            },
            decoration: InputDecoration(
              labelText: 'Confirm PIN',
              prefixIcon: const Icon(Icons.pin_outlined, size: 18),
              counterText:
                  '${widget.confirm.text.length}/${PinValidation.maxLength}',
              border: const OutlineInputBorder(),
            ),
          ),
        ],
        if (message != null) ...<Widget>[
          const SizedBox(height: AuraSpace.xs),
          Row(
            children: <Widget>[
              const Icon(Icons.error_outline_rounded,
                  size: 14, color: AuraColors.danger),
              const SizedBox(width: AuraSpace.xs),
              Expanded(
                child: Text(
                  message,
                  style: text.bodySmall?.copyWith(color: AuraColors.danger),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: AuraSpace.md),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: canSubmit ? widget.onSubmit : null,
            icon: widget.busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    widget.needsSetup
                        ? Icons.key_outlined
                        : Icons.lock_open_outlined,
                    size: 17,
                  ),
            label:
                Text(widget.needsSetup ? 'Set PIN & unlock' : 'Unlock AYUSH'),
          ),
        ),
      ],
    );
  }
}

class _PinChangeCard extends ConsumerStatefulWidget {
  const _PinChangeCard();

  @override
  ConsumerState<_PinChangeCard> createState() => _PinChangeCardState();
}

class _PinChangeCardState extends ConsumerState<_PinChangeCard> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _newPin = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _newPin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final PinValidationResult currentValidation = PinValidation.evaluate(
      pin: _current.text,
      needsSetup: false,
    );
    if (!currentValidation.isValid) {
      setState(() => _error = currentValidation.message);
      return;
    }
    final PinValidationResult newValidation = PinValidation.evaluate(
      pin: _newPin.text,
      needsSetup: true,
      confirmation: _confirm.text,
    );
    if (!newValidation.isValid) {
      setState(() => _error = newValidation.message);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final PinChangeResult result =
          await ref.read(profileSessionProvider.notifier).changePin(
                currentPin: _current.text,
                newPin: _newPin.text,
                confirmation: _confirm.text,
              );
      if (!mounted) return;
      _clear();
      setState(() => _busy = false);
      switch (result) {
        case PinChangeResult.success:
          // changePin() locks AYUSH and clears private state. The card is about
          // to disappear, so use a snackbar the user can actually see.
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PIN changed. Unlock AYUSH with your new PIN.'),
            ),
          );
          break;
        case PinChangeResult.invalidCurrentPin:
          final int remaining =
              ref.read(profileSessionProvider.notifier).remainingAttempts;
          setState(() => _error = remaining > 0
              ? 'Current PIN is incorrect. $remaining attempt(s) remaining.'
              : 'Current PIN is incorrect.');
          break;
        case PinChangeResult.confirmationMismatch:
          setState(() => _error = PinValidation.mismatchMessage);
          break;
        case PinChangeResult.invalidNewPin:
          setState(() => _error = 'Choose a new PIN of 4-12 digits.');
          break;
        case PinChangeResult.rateLimited:
          setState(() => _error =
              'Too many attempts. Please wait a minute before trying again.');
          break;
        case PinChangeResult.needsSetup:
          setState(() => _error =
              'No PIN is configured yet. Set one up before changing it.');
          break;
        case PinChangeResult.profileLocked:
          setState(() =>
              _error = 'Unlock AYUSH before changing its PIN. Try again if the '
                  'workspace changed.');
          break;
      }
    } on Object catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not change the PIN. Please try again.';
      });
    }
  }

  void _clear() {
    _current.clear();
    _newPin.clear();
    _confirm.clear();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return SurfaceCard(
      surface: AuraGlassSurface.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              GlassContainer(
                width: 40,
                height: 40,
                padding: EdgeInsets.zero,
                radius: 12,
                blur: 0,
                fill: 0.5,
                showHighlight: false,
                borderColor: AuraColors.secondary.withValues(alpha: 0.3),
                child: const Icon(Icons.key_outlined,
                    size: 20, color: AuraColors.secondary),
              ),
              const SizedBox(width: AuraSpace.sm),
              Expanded(child: Text('Change AYUSH PIN', style: text.titleLarge)),
            ],
          ),
          const SizedBox(height: AuraSpace.sm),
          Text(
            'Verify your current PIN, then choose and confirm a new one. '
            'Changing the PIN locks the private workspace immediately.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: AuraSpace.md),
          _PinField(
            controller: _current,
            label: 'Current PIN',
            obscure: _obscure,
            enabled: !_busy,
            onToggleObscure: () => setState(() => _obscure = !_obscure),
          ),
          const SizedBox(height: AuraSpace.sm),
          _PinField(
            controller: _newPin,
            label: 'New PIN',
            obscure: _obscure,
            enabled: !_busy,
            onToggleObscure: () => setState(() => _obscure = !_obscure),
          ),
          const SizedBox(height: AuraSpace.sm),
          _PinField(
            controller: _confirm,
            label: 'Confirm new PIN',
            obscure: _obscure,
            enabled: !_busy,
            onToggleObscure: () => setState(() => _obscure = !_obscure),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: AuraSpace.sm),
            Text(_error!,
                style: text.bodySmall?.copyWith(color: AuraColors.danger)),
          ],
          const SizedBox(height: AuraSpace.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.password_outlined, size: 17),
              label: const Text('Change PIN'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PinField extends StatelessWidget {
  const _PinField({
    required this.controller,
    required this.label,
    required this.obscure,
    required this.enabled,
    required this.onToggleObscure,
  });

  final TextEditingController controller;
  final String label;
  final bool obscure;
  final bool enabled;
  final VoidCallback onToggleObscure;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: TextInputType.number,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
      ],
      maxLength: PinValidation.maxLength,
      maxLengthEnforcement: MaxLengthEnforcement.enforced,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.pin_outlined, size: 18),
        suffixIcon: IconButton(
          tooltip: obscure ? 'Show PIN' : 'Hide PIN',
          onPressed: onToggleObscure,
          icon: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: 18,
          ),
        ),
        counterText: '${controller.text.length}/${PinValidation.maxLength}',
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _AutoLockCard extends ConsumerStatefulWidget {
  const _AutoLockCard();

  @override
  ConsumerState<_AutoLockCard> createState() => _AutoLockCardState();
}

class _AutoLockCardState extends ConsumerState<_AutoLockCard> {
  @override
  void initState() {
    super.initState();
    // Only mounted while AYUSH is unlocked, so the private guard passes.
    unawaited(ref.read(ayushSecuritySettingsProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final AyushSecuritySettingsState state =
        ref.watch(ayushSecuritySettingsProvider);
    final TextTheme text = Theme.of(context).textTheme;
    return SurfaceCard(
      surface: AuraGlassSurface.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              GlassContainer(
                width: 40,
                height: 40,
                padding: EdgeInsets.zero,
                radius: 12,
                blur: 0,
                fill: 0.5,
                showHighlight: false,
                borderColor: AuraColors.primary.withValues(alpha: 0.3),
                child: const Icon(Icons.timer_outlined,
                    size: 20, color: AuraColors.primary),
              ),
              const SizedBox(width: AuraSpace.sm),
              Expanded(
                  child: Text('Automatic AYUSH lock', style: text.titleLarge)),
            ],
          ),
          const SizedBox(height: AuraSpace.sm),
          Text(
            'After this much inactivity, AYUSH locks and clears decrypted '
            'private memory. It also locks shortly after the app leaves the '
            'foreground, even when inactivity is set to Never. FAMILY is never '
            'affected. Defaults: 5 minutes inactivity, 30 seconds background.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: AuraSpace.md),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool stacked = constraints.maxWidth < _kStackBreakpoint;
              final Widget label = ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule_outlined),
                title: const Text('Lock after inactivity'),
                subtitle: const Text('Applies to AYUSH only.'),
              );
              final Widget control = DropdownButton<AyushAutoLock>(
                // Both the stacked and wide layouts constrain this control to
                // a bounded width, so let it ellipsize instead of overflowing.
                isExpanded: true,
                value: state.settings.autoLock,
                items: <DropdownMenuItem<AyushAutoLock>>[
                  for (final AyushAutoLock option in AyushAutoLock.values)
                    DropdownMenuItem<AyushAutoLock>(
                      value: option,
                      child: Text(option.label),
                    ),
                ],
                onChanged: (AyushAutoLock? value) {
                  if (value == null) return;
                  ref
                      .read(ayushSecuritySettingsProvider.notifier)
                      .update(value);
                },
              );
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    label,
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 56,
                        bottom: AuraSpace.xs,
                      ),
                      child: control,
                    ),
                  ],
                );
              }
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule_outlined),
                title: const Text('Lock after inactivity'),
                subtitle: const Text('Applies to AYUSH only.'),
                trailing: SizedBox(width: 170, child: control),
              );
            },
          ),
          const SizedBox(height: AuraSpace.sm),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool stacked = constraints.maxWidth < _kStackBreakpoint;
              final Widget label = ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lock_outline),
                title: const Text('Lock after backgrounding'),
                subtitle: const Text('Short grace; applies to AYUSH only.'),
              );
              final Widget control = DropdownButton<AyushBackgroundLockGrace>(
                isExpanded: true,
                value: state.settings.backgroundLockGrace,
                items: <DropdownMenuItem<AyushBackgroundLockGrace>>[
                  for (final AyushBackgroundLockGrace option
                      in AyushBackgroundLockGrace.values)
                    DropdownMenuItem<AyushBackgroundLockGrace>(
                      value: option,
                      child: Text(option.label),
                    ),
                ],
                onChanged: (AyushBackgroundLockGrace? value) {
                  if (value == null) return;
                  unawaited(
                    ref
                        .read(ayushSecuritySettingsProvider.notifier)
                        .updateBackgroundLockGrace(value),
                  );
                },
              );
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    label,
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 56,
                        bottom: AuraSpace.xs,
                      ),
                      child: control,
                    ),
                  ],
                );
              }
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lock_outline),
                title: const Text('Lock after backgrounding'),
                subtitle: const Text('Short grace; applies to AYUSH only.'),
                trailing: SizedBox(width: 170, child: control),
              );
            },
          ),
          if (state.error != null)
            InfoBanner(
              title: 'Private setting unavailable',
              message: state.error!,
              icon: Icons.warning_amber_rounded,
              tone: AuraBannerTone.warning,
            ),
        ],
      ),
    );
  }
}

class _SecurityInformationCard extends StatelessWidget {
  const _SecurityInformationCard();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return SurfaceCard(
      surface: AuraGlassSurface.panel,
      padding: const EdgeInsets.all(AuraSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          GlassContainer(
            width: 36,
            height: 36,
            padding: EdgeInsets.zero,
            radius: 10,
            blur: 0,
            fill: 0.5,
            showHighlight: false,
            borderColor: AuraColors.secondary.withValues(alpha: 0.28),
            child: const Icon(Icons.fingerprint_outlined,
                size: 18, color: AuraColors.secondary),
          ),
          const SizedBox(width: AuraSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Security information & future integration',
                    style: text.titleSmall),
                const SizedBox(height: AuraSpace.xxs),
                Text(
                  'PIN change, rate limiting and automatic lock are enforced in '
                  'the existing session controller, not only in this UI. '
                  'Windows Hello is not implemented in this release; it can be '
                  'added later behind a platform-specific authentication '
                  'abstraction that plugs into ProfileSessionController without '
                  'changing the DPAPI memory boundary. No biometric toggle is '
                  'shown because no biometric capability exists yet.',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IsolationCard extends StatelessWidget {
  const _IsolationCard();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return SurfaceCard(
      surface: AuraGlassSurface.panel,
      padding: const EdgeInsets.all(AuraSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          GlassContainer(
            width: 36,
            height: 36,
            padding: EdgeInsets.zero,
            radius: 10,
            blur: 0,
            fill: 0.5,
            showHighlight: false,
            borderColor: AuraColors.secondary.withValues(alpha: 0.28),
            child: const Icon(Icons.domain_verification_outlined,
                size: 18, color: AuraColors.secondary),
          ),
          const SizedBox(width: AuraSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Service-level isolation', style: text.titleSmall),
                const SizedBox(height: AuraSpace.xxs),
                Text(
                  'Notifications are stored in separate files per workspace, '
                  'and private data access is guarded in services rather than '
                  'only in the UI. Future private integrations and AI history '
                  'must use the same guard.',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
