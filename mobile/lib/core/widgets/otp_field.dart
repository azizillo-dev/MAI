import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// N katakli kod kiritish maydoni.
/// Ichida bitta ko'rinmas TextField bor: SMS autofill (oneTimeCode), nusxa joylash va
/// o'chirish tugmasi tabiiy ishlaydi. Xato bo'lsa kataklar qizaradi va silkinadi.
class OtpField extends StatefulWidget {
  const OtpField({
    super.key,
    required this.controller,
    this.length = 6,
    this.onCompleted,
    this.onChanged,
    this.hasError = false,
    this.autofocus = true,
    this.obscure = false,
    this.enabled = true,
  });

  final TextEditingController controller;
  final int length;
  final ValueChanged<String>? onCompleted;
  final ValueChanged<String>? onChanged;
  final bool hasError;
  final bool autofocus;
  final bool obscure;
  final bool enabled;

  @override
  State<OtpField> createState() => OtpFieldState();
}

class OtpFieldState extends State<OtpField> with SingleTickerProviderStateMixin {
  final _focus = FocusNode();
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
    _focus.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(OtpField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hasError && !oldWidget.hasError) {
      HapticFeedback.heavyImpact();
      _shake.forward(from: 0);
    }
    // Tekshiruv paytida maydon o'chiriladi va fokus yo'qoladi: qayta yoqilganda klaviaturani qaytaramiz
    if (widget.enabled && !oldWidget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) focus();
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    _focus.dispose();
    _shake.dispose();
    super.dispose();
  }

  void _onText() => setState(() {});

  /// "Orqaga" bilan yopilgan klaviaturada fokus saqlanib qoladi — requestFocus hech narsa qilmaydi.
  /// Shuning uchun fokus bor bo'lsa, klaviaturani to'g'ridan-to'g'ri ochamiz.
  void focus() {
    if (_focus.hasFocus) {
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    } else {
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        final dx = math.sin(_shake.value * math.pi * 6) * 10 * (1 - _shake.value);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? focus : null,
        child: Stack(
          children: [
            // Ko'rinmas, lekin haqiqiy input
            Positioned.fill(
              child: Opacity(
                opacity: 0,
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  autofocus: widget.autofocus,
                  enabled: widget.enabled,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  maxLength: widget.length,
                  showCursor: false,
                  enableInteractiveSelection: false,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(counterText: '', border: InputBorder.none),
                  onChanged: (v) {
                    widget.onChanged?.call(v);
                    if (v.length == widget.length) widget.onCompleted?.call(v);
                  },
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < widget.length; i++)
                  _Cell(
                    char: i < text.length ? (widget.obscure ? '•' : text[i]) : '',
                    active: _focus.hasFocus && (i == text.length || (i == widget.length - 1 && text.length == widget.length)),
                    filled: i < text.length,
                    error: widget.hasError,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.char, required this.active, required this.filled, required this.error});

  final String char;
  final bool active;
  final bool filled;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final borderColor = error
        ? context.appColors.danger
        : active
            ? scheme.primary
            : filled
                ? scheme.primary.withValues(alpha: 0.45)
                : scheme.outlineVariant;
    return Flexible(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        height: 58,
        constraints: const BoxConstraints(maxWidth: 52),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: error ? context.appColors.dangerContainer.withValues(alpha: 0.5) : scheme.surface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: borderColor, width: active || error ? 2 : 1.2),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 120),
          transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
          child: Text(
            char,
            key: ValueKey(char),
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: scheme.onSurface),
          ),
        ),
      ),
    );
  }
}
