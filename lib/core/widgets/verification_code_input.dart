// VerificationCodeInput coordinates code entry, paste, focus and completion across the verification
// digit fields.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A modern segmented verification-code input backed by one controller.
///
/// Each digit is presented in its own field while whole-code paste and
/// platform one-time-code autofill are accepted by the focused field and
/// distributed across all slots.
class VerificationCodeInput extends StatefulWidget {
  const VerificationCodeInput({
    super.key,
    required this.controller,
    this.enabled = true,
    this.autofocus = false,
    this.length = 6,
    this.semanticLabel = 'Verification code',
    this.onChanged,
    this.onCompleted,
    this.onSubmitted,
  }) : assert(length > 0);

  final TextEditingController controller;
  final bool enabled;
  final bool autofocus;
  final int length;
  final String semanticLabel;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;
  final ValueChanged<String>? onSubmitted;

  @override
  State<VerificationCodeInput> createState() => _VerificationCodeInputState();
}

class _VerificationCodeInputState extends State<VerificationCodeInput>
    with WidgetsBindingObserver {
  late List<TextEditingController> _slotControllers;
  late List<FocusNode> _focusNodes;
  bool _synchronizing = false;
  bool _restoreFocusOnResume = false;
  AppLifecycleState? _lastLifecycleState;
  bool _pasting = false;
  String? _pasteError;

  @override
  void initState() {
    super.initState();
    _lastLifecycleState = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    _createSlots();
    widget.controller.addListener(_syncFromController);
    _syncFromController();
  }

  @override
  void didUpdateWidget(covariant VerificationCodeInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncFromController);
      widget.controller.addListener(_syncFromController);
    }
    if (oldWidget.length != widget.length) {
      _disposeSlots();
      _createSlots();
    }
    _syncFromController();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final previousState = _lastLifecycleState;
    _lastLifecycleState = state;
    if (state == AppLifecycleState.inactive &&
        (previousState == AppLifecycleState.resumed || previousState == null)) {
      _restoreFocusOnResume = _focusNodes.any((node) => node.hasFocus);
    } else if (state == AppLifecycleState.resumed && _restoreFocusOnResume) {
      _restoreFocusOnResume = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !widget.enabled ||
            ModalRoute.of(context)?.isCurrent == false) {
          return;
        }
        final index = _digits(
          widget.controller.text,
        ).length.clamp(0, widget.length - 1);
        _focusNodes[index].requestFocus();
        // A still-focused field may have lost its platform keyboard while
        // WhatsApp was foregrounded. Reopen that existing text connection.
        SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      });
      WidgetsBinding.instance.scheduleFrame();
    }
  }

  Future<void> _pasteCode() async {
    if (!widget.enabled || _pasting) return;
    setState(() {
      _pasting = true;
      _pasteError = null;
    });
    try {
      // Read only after a user action, so returning from WhatsApp does not
      // trigger clipboard permission prompts or submit a stale code.
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted ||
          !widget.enabled ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      final text = data?.text?.trim() ?? '';
      final matches = RegExp(
        '(?<![0-9])[0-9]{${widget.length}}(?![0-9])',
      ).allMatches(text).toList();
      final compact = text.replaceAll(RegExp(r'[\s-]'), '');
      final code = RegExp('^[0-9]{${widget.length}}\$').hasMatch(compact)
          ? compact
          : matches.length == 1
          ? matches.single.group(0)
          : null;
      if (code == null) {
        setState(
          () => _pasteError =
              'Copy the ${widget.length}-digit code, then tap Paste code.',
        );
        return;
      }
      _focusNodes.last.requestFocus();
      _setCode(code);
    } on PlatformException {
      if (mounted) {
        setState(
          () => _pasteError =
              'Unable to paste. Allow paste access or enter the code manually.',
        );
      }
    } finally {
      if (mounted) setState(() => _pasting = false);
    }
  }

  void _createSlots() {
    _slotControllers = List.generate(
      widget.length,
      (_) => TextEditingController(),
    );
    _focusNodes = List.generate(
      widget.length,
      (index) =>
          FocusNode(onKeyEvent: (node, event) => _handleKeyEvent(index, event)),
    );
    for (final node in _focusNodes) {
      node.addListener(_handleFocusChange);
    }
  }

  void _disposeSlots() {
    for (final controller in _slotControllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node
        ..removeListener(_handleFocusChange)
        ..dispose();
    }
  }

  void _handleFocusChange() {
    if (mounted) setState(() {});
  }

  String _digits(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    return digits.length <= widget.length
        ? digits
        : digits.substring(0, widget.length);
  }

  void _syncFromController() {
    if (_synchronizing) return;
    final value = _digits(widget.controller.text);
    _synchronizing = true;
    for (var index = 0; index < widget.length; index++) {
      final digit = index < value.length ? value[index] : '';
      if (_slotControllers[index].text != digit) {
        _slotControllers[index].value = TextEditingValue(
          text: digit,
          selection: TextSelection.collapsed(offset: digit.length),
        );
      }
    }
    _synchronizing = false;
    if (mounted) setState(() {});
  }

  void _setCode(String value) {
    final code = _digits(value);
    final previous = _digits(widget.controller.text);
    _synchronizing = true;
    widget.controller.value = TextEditingValue(
      text: code,
      selection: TextSelection.collapsed(offset: code.length),
    );
    for (var index = 0; index < widget.length; index++) {
      final digit = index < code.length ? code[index] : '';
      _slotControllers[index].value = TextEditingValue(
        text: digit,
        selection: TextSelection.collapsed(offset: digit.length),
      );
    }
    _synchronizing = false;
    if (mounted) setState(() {});
    if (code != previous) widget.onChanged?.call(code);
    if (code.length == widget.length && code != previous) {
      widget.onCompleted?.call(code);
    }
  }

  void _handleSlotChanged(int index, String rawValue) {
    if (_synchronizing) return;
    final entered = rawValue.replaceAll(RegExp(r'\D'), '');
    final current = _digits(widget.controller.text);

    if (entered.length > 1) {
      // A full OTP can be pasted or supplied by Android/iOS autofill into any
      // slot. Treat six digits as the complete code; shorter pasted fragments
      // fill forward from the selected slot.
      if (entered.length >= widget.length) {
        _setCode(entered.substring(0, widget.length));
        _focusNodes.last.requestFocus();
        return;
      }
      final prefix = current.substring(0, index.clamp(0, current.length));
      final replacedEnd = (index + 1).clamp(0, current.length);
      final suffix = current.substring(replacedEnd);
      _setCode('$prefix$entered$suffix');
      _focusNodes[(index + entered.length).clamp(0, widget.length - 1)]
          .requestFocus();
      return;
    }

    if (entered.isEmpty) {
      if (index < current.length) {
        _setCode(current.substring(0, index) + current.substring(index + 1));
      } else {
        _syncFromController();
      }
      if (index > 0) _focusNodes[index - 1].requestFocus();
      return;
    }

    String updated;
    if (index < current.length) {
      updated =
          current.substring(0, index) + entered + current.substring(index + 1);
    } else if (index == current.length) {
      updated = '$current$entered';
    } else {
      updated = current;
    }
    _setCode(updated);
    if (index < widget.length - 1) {
      _focusNodes[index + 1].requestFocus();
    }
  }

  KeyEventResult _handleKeyEvent(int index, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.backspace ||
        _slotControllers[index].text.isNotEmpty ||
        index == 0) {
      return KeyEventResult.ignored;
    }
    final current = _digits(widget.controller.text);
    if (index - 1 < current.length) {
      _setCode(current.substring(0, index - 1) + current.substring(index));
    }
    _focusNodes[index - 1].requestFocus();
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_syncFromController);
    _disposeSlots();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      label: widget.semanticLabel,
      textField: true,
      value: _digits(widget.controller.text).split('').join(' '),
      child: Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  for (var index = 0; index < widget.length; index++) ...[
                    if (index > 0) const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 58,
                        child: TextField(
                          controller: _slotControllers[index],
                          focusNode: _focusNodes[index],
                          enabled: widget.enabled,
                          autofocus: widget.autofocus && index == 0,
                          keyboardType: TextInputType.number,
                          textInputAction: index == widget.length - 1
                              ? TextInputAction.done
                              : TextInputAction.next,
                          // Offer platform OTP autofill on whichever slot is
                          // focused; a supplied full code is distributed below.
                          autofillHints: const [AutofillHints.oneTimeCode],
                          enableSuggestions: false,
                          autocorrect: false,
                          textAlign: TextAlign.center,
                          textAlignVertical: TextAlignVertical.center,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: scheme.onSurface,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(widget.length),
                          ],
                          decoration: InputDecoration(
                            hintText: '•',
                            hintStyle: TextStyle(
                              color: scheme.onSurfaceVariant.withValues(
                                alpha: 0.35,
                              ),
                            ),
                            filled: true,
                            fillColor: _focusNodes[index].hasFocus
                                ? scheme.primary.withValues(alpha: 0.12)
                                : scheme.primary.withValues(alpha: 0.055),
                            // Roboto's numeral ink sits fractionally left of its
                            // advance box. This keeps the visual centre aligned
                            // with the centre of the surrounding slot.
                            contentPadding: const EdgeInsets.only(left: 2),
                            counterText: '',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: scheme.outlineVariant,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: scheme.outlineVariant.withValues(
                                  alpha: 0.75,
                                ),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: scheme.primary,
                                width: 2,
                              ),
                            ),
                            disabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: scheme.outlineVariant.withValues(
                                  alpha: 0.35,
                                ),
                              ),
                            ),
                          ),
                          onTap: () {
                            final text = _slotControllers[index].text;
                            _slotControllers[index].selection = TextSelection(
                              baseOffset: 0,
                              extentOffset: text.length,
                            );
                          },
                          onChanged: (value) =>
                              _handleSlotChanged(index, value),
                          onSubmitted: (_) {
                            final code = _digits(widget.controller.text);
                            if (code.length == widget.length) {
                              widget.onSubmitted?.call(code);
                            } else if (index < widget.length - 1) {
                              _focusNodes[index + 1].requestFocus();
                            }
                          },
                          onTapOutside: (_) => _focusNodes[index].unfocus(),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: widget.enabled && !_pasting ? _pasteCode : null,
                icon: const Icon(Icons.content_paste_rounded, size: 18),
                label: const Text('Paste code'),
              ),
              if (_pasteError != null)
                Text(
                  _pasteError!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
