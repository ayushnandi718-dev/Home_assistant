import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/domain/pin_validation.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:aura_hub/shared/widgets/glass/glass_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shows the AYUSH PIN prompt as a keyboard-aware, non-dismissible modal.
///
/// The stronger scrim and disabled barrier dismissal keep the private-workspace
/// gate visually separated from the dashboard and prevent a stray tap from
/// discarding an in-progress PIN setup. Cancellation stays explicit via the
/// dialog's Cancel button.
Future<bool?> showAyushUnlockDialog({required BuildContext context}) {
  return showGlassDialog<bool>(
    context: context,
    width: 440,
    keyboardAware: true,
    barrierDismissible: false,
    barrierColor: const Color(0xE6120A2E),
    child: const AyushUnlockDialog(),
  );
}

/// PIN prompt shown when AYUSH is selected from the navbar workspace menu.
///
/// This is only a presentation surface. PIN setup, verification, failed-attempt
/// tracking and lockout all run through [ProfileSessionController], the same
/// controller used by the Profiles page. There is no second PIN store, verifier
/// or authentication path. Returning `false` (or `null` on a barrier tap) leaves
/// the active workspace unchanged.
class AyushUnlockDialog extends ConsumerStatefulWidget {
  const AyushUnlockDialog({super.key});

  @override
  ConsumerState<AyushUnlockDialog> createState() => _AyushUnlockDialogState();
}

class _AyushUnlockDialogState extends ConsumerState<AyushUnlockDialog> {
  final TextEditingController _pin = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  final GlobalKey _confirmFieldKey = GlobalKey();
  late final FocusNode _pinFocus;
  late final FocusNode _confirmFocus;
  bool _obscure = true;
  bool _busy = false;
  bool _allowExplicitPop = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pinFocus = FocusNode(debugLabel: 'AYUSH new PIN');
    _confirmFocus = FocusNode(debugLabel: 'AYUSH confirm PIN');
    _confirmFocus.addListener(() {
      if (_confirmFocus.hasFocus) _scrollConfirmIntoView();
    });
    _pin.addListener(_handleInputChanged);
    _confirm.addListener(_handleInputChanged);
  }

  @override
  void dispose() {
    _pin.removeListener(_handleInputChanged);
    _confirm.removeListener(_handleInputChanged);
    _pin.dispose();
    _confirm.dispose();
    _pinFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
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

  void _focusConfirm() {
    FocusScope.of(context).requestFocus(_confirmFocus);
  }

  void _dismissKeyboard() {
    final FocusScopeNode scope = FocusScope.of(context);
    if (scope.hasFocus) scope.unfocus();
  }

  /// System Back is intercepted below so it can never discard a PIN entry.
  /// Explicit Cancel/Unlock still need to pop, so they temporarily opt in and
  /// wait one frame for [PopScope.canPop] to see the change.
  Future<void> _popExplicitly(bool? result) async {
    if (!mounted) return;
    setState(() => _allowExplicitPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  /// A keystroke only rebuilds this dialog, never the workspace behind it.
  void _handleInputChanged() {
    if (!mounted) return;
    setState(() {
      if (_error != null) _error = null;
    });
  }

  List<TextInputFormatter> get _digitsOnly =>
      <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly];

  void _clearFields() {
    _pin.clear();
    _confirm.clear();
  }

  Future<void> _submit({required bool needsSetup}) async {
    final PinValidationResult validation = PinValidation.evaluate(
      pin: _pin.text,
      needsSetup: needsSetup,
      confirmation: _confirm.text,
    );
    if (!validation.isValid) {
      setState(() => _error = validation.message);
      return;
    }

    _dismissKeyboard();
    setState(() {
      _busy = true;
      _error = null;
    });

    final ProfileSessionController controller =
        ref.read(profileSessionProvider.notifier);
    try {
      final ProfileUnlockResult result = needsSetup
          ? await controller.setupPin(_pin.text)
          : await controller.unlockAyush(_pin.text);
      if (!mounted) return;
      setState(() => _busy = false);

      switch (result) {
        case ProfileUnlockResult.success:
          await _popExplicitly(true);
          break;
        case ProfileUnlockResult.invalidPin:
          final int remaining = controller.remainingAttempts;
          _clearFields();
          setState(() => _error = remaining > 0
              ? 'Incorrect PIN. $remaining attempt(s) remaining.'
              : 'Incorrect PIN.');
          break;
        case ProfileUnlockResult.rateLimited:
          _clearFields();
          setState(() => _error =
              'Too many attempts. Please wait a minute before trying again.');
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

  Future<void> _cancel() async {
    if (_busy) return;
    _dismissKeyboard();
    await _popExplicitly(false);
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AsyncValue<bool> configured = ref.watch(ayushPinConfiguredProvider);

    return PopScope<bool>(
      // System Back must not dismiss the PIN gate. It only dismisses the IME;
      // leaving the dialog always goes through the explicit Cancel button.
      canPop: _allowExplicitPop,
      onPopInvokedWithResult: (bool didPop, bool? result) {
        if (didPop) return;
        if (_allowExplicitPop && mounted) {
          setState(() => _allowExplicitPop = false);
        }
        _dismissKeyboard();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AuraColors.secondary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AuraColors.secondary.withValues(alpha: 0.35),
                  ),
                ),
                child: const Icon(Icons.lock_outline_rounded,
                    size: 20, color: AuraColors.secondary),
              ),
              const SizedBox(width: AuraSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Unlock AYUSH', style: text.titleLarge),
                    const SizedBox(height: 2),
                    const Text('Private workspace · PIN required',
                        style: TextStyle(
                            fontSize: 12, color: AuraColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AuraSpace.lg),
          configured.when(
            loading: () => const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (Object error, StackTrace stack) => Text(
              'Could not read PIN configuration. Please try again.',
              style: text.bodySmall?.copyWith(color: AuraColors.danger),
            ),
            data: (bool hasPin) {
              final bool needsSetup = !hasPin;
              final ProfileSessionController controller =
                  ref.read(profileSessionProvider.notifier);
              final PinValidationResult validation = PinValidation.evaluate(
                pin: _pin.text,
                needsSetup: needsSetup,
                confirmation: _confirm.text,
              );
              final String? message = _error ??
                  ((_pin.text.isEmpty && _confirm.text.isEmpty)
                      ? null
                      : validation.message);
              final bool canSubmit = validation.isValid && !_busy;

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    needsSetup
                        ? 'Create your AYUSH PIN'
                        : 'Enter your AYUSH PIN',
                    style: text.titleSmall,
                  ),
                  const SizedBox(height: AuraSpace.xs),
                  Text(
                    '${PinValidation.minLength}-${PinValidation.maxLength} '
                    'digits, numbers only.',
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: AuraSpace.sm),
                  TextField(
                    controller: _pin,
                    focusNode: _pinFocus,
                    obscureText: _obscure,
                    keyboardType: TextInputType.number,
                    textInputAction: needsSetup
                        ? TextInputAction.next
                        : TextInputAction.done,
                    autocorrect: false,
                    enableSuggestions: false,
                    inputFormatters: _digitsOnly,
                    maxLength: PinValidation.maxLength,
                    maxLengthEnforcement: MaxLengthEnforcement.enforced,
                    enabled: !_busy,
                    onSubmitted: (_) {
                      if (needsSetup) {
                        _focusConfirm();
                      } else if (canSubmit) {
                        _submit(needsSetup: needsSetup);
                      }
                    },
                    decoration: InputDecoration(
                      labelText: needsSetup ? 'New PIN' : 'PIN',
                      prefixIcon: const Icon(Icons.pin_outlined, size: 18),
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Show PIN' : 'Hide PIN',
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 18,
                        ),
                      ),
                      counterText:
                          '${_pin.text.length}/${PinValidation.maxLength}',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (needsSetup) ...<Widget>[
                    const SizedBox(height: AuraSpace.sm),
                    TextField(
                      key: _confirmFieldKey,
                      controller: _confirm,
                      focusNode: _confirmFocus,
                      obscureText: _obscure,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      enableSuggestions: false,
                      inputFormatters: _digitsOnly,
                      maxLength: PinValidation.maxLength,
                      maxLengthEnforcement: MaxLengthEnforcement.enforced,
                      enabled: !_busy,
                      onSubmitted: (_) {
                        if (canSubmit) _submit(needsSetup: needsSetup);
                      },
                      decoration: InputDecoration(
                        labelText: 'Confirm PIN',
                        prefixIcon: const Icon(Icons.pin_outlined, size: 18),
                        counterText:
                            '${_confirm.text.length}/${PinValidation.maxLength}',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                  FutureBuilder<void>(
                    future: controller.lockoutReady,
                    builder:
                        (BuildContext context, AsyncSnapshot<void> snapshot) {
                      if (snapshot.connectionState != ConnectionState.done ||
                          !controller.lockoutCorrupt) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AuraSpace.sm),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                              'Lockout state could not be read. A short '
                              'recovery lock is active.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AuraColors.warning,
                              ),
                            ),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      await controller
                                          .recoverFromCorruptLockout();
                                      if (mounted) setState(() {});
                                    },
                              child: const Text('Clear recovery lock'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
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
                            style: text.bodySmall?.copyWith(
                              color: AuraColors.danger,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AuraSpace.md),
                  LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                      final Widget cancelButton = TextButton(
                        onPressed: _busy ? null : _cancel,
                        child: const Text('Cancel'),
                      );
                      final Widget submitButton = FilledButton.icon(
                        onPressed: canSubmit
                            ? () => _submit(needsSetup: needsSetup)
                            : null,
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                needsSetup
                                    ? Icons.key_outlined
                                    : Icons.lock_open_outlined,
                                size: 17,
                              ),
                        label: Text(
                          needsSetup ? 'Set PIN & unlock' : 'Unlock AYUSH',
                        ),
                      );

                      // On a narrow, keyboard-sized dialog the actions stack
                      // instead of squeezing their labels into an overflow.
                      if (constraints.maxWidth < 460) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            submitButton,
                            cancelButton,
                          ],
                        );
                      }
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: <Widget>[
                          cancelButton,
                          const SizedBox(width: AuraSpace.sm),
                          submitButton,
                        ],
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
