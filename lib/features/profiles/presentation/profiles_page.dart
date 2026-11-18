import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_glass.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/domain/pin_validation.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:aura_hub/shared/widgets/aura_scroll_area.dart';
import 'package:aura_hub/shared/widgets/glass/glass_container.dart';
import 'package:aura_hub/shared/widgets/info_banner.dart';
import 'package:aura_hub/shared/widgets/page_header.dart';
import 'package:aura_hub/shared/widgets/status_pill.dart';
import 'package:aura_hub/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
              const _IsolationCard(),
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
  @override
  void initState() {
    super.initState();
    widget.pin.addListener(_handleInputChanged);
    widget.confirm.addListener(_handleInputChanged);
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
          obscureText: widget.obscure,
          keyboardType: TextInputType.number,
          inputFormatters: _digitsOnly,
          maxLength: PinValidation.maxLength,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          enabled: !widget.busy,
          onSubmitted: (_) {
            if (canSubmit) widget.onSubmit();
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
            controller: widget.confirm,
            obscureText: widget.obscure,
            keyboardType: TextInputType.number,
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
