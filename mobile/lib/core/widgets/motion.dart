import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Bosilganda biroz kichrayadi (0.97) — karta "javob beradi". Haptik bilan.
///
/// Ripple (InkWell) ichkarida qoladi; bu faqat masshtab va haptikani qo'shadi.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.scale = 0.97, this.haptic = true});

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final bool haptic;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: Duration(milliseconds: _down ? 90 : 160),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

/// Ro'yxat elementlari ketma-ket (stagger) paydo bo'ladi: pastdan biroz ko'tarilib, ochilib.
///
/// Faqat birinchi chizilishda o'ynaydi (qayta qurilganda takrorlanmaydi). [index] katta bo'lsa
/// kechikish cheklanadi — uzun ro'yxatda oxirgi kartalar kutib qolmaydi.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({super.key, required this.child, this.index = 0, this.offset = 14});

  final Widget child;
  final int index;
  final double offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    final delay = Duration(milliseconds: 45 * widget.index.clamp(0, 8));
    Future.delayed(delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // "Harakatni kamaytirish" yoqilgan bo'lsa — animatsiyasiz
    if (MediaQuery.disableAnimationsOf(context)) _c.value = 1;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(offset: Offset(0, widget.offset * (1 - _t.value)), child: child),
      ),
      child: widget.child,
    );
  }
}

/// Yuklanish "soyasi": kontent shakli ko'rinadi, bloklar ustidan yumshoq yorug'lik o'tadi.
/// Karta foni o'zgarmaydi — faqat [SkeletonBox] bloklari yaltiraydi.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, required this.child});

  /// Kul rang bloklardan ([SkeletonBox]) tuzilgan shakl
  final Widget child;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Yuklanmoqda',
      child: _SkeletonScope(animation: _c, child: ExcludeSemantics(child: widget.child)),
    );
  }
}

class _SkeletonScope extends InheritedNotifier<Animation<double>> {
  const _SkeletonScope({required Animation<double> animation, required super.child}) : super(notifier: animation);

  static Animation<double>? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SkeletonScope>()?.notifier;
}

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 8, this.circle = false});

  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? const Color(0xFF1E293B) : const Color(0xFFEDF1F7);
    final shine = dark ? const Color(0xFF2A3A55) : const Color(0xFFF8FAFD);
    final t = _SkeletonScope.of(context)?.value ?? 0;
    final x = -2.0 + 4 * t; // yorug'lik chapdan o'ngga o'tadi
    return Container(
      width: circle ? height : width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(x - 1, 0),
          end: Alignment(x + 1, 0),
          colors: [base, shine, base],
        ),
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
      ),
    );
  }
}

/// Ro'yxat ekranlari uchun tayyor skelet: [count] ta karta shakli
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 5, this.padding});

  final int count;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final card = context.theme.cardTheme;
    // ListView emas: SliverFillRemaining kabi joylar balandlikni oldindan so'raydi (intrinsic),
    // ListView buni bera olmaydi va xato beradi. Oddiy ustun — har qanday joyda xavfsiz
    return Skeleton(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: padding ?? Insets.screen.copyWith(top: 12, bottom: 24),
        child: Column(
          children: [
            for (var i = 0; i < count; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(Insets.lg),
                decoration: ShapeDecoration(
                  shape: card.shape ?? RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
                  color: card.color ?? context.colors.surface,
                ),
                child: Row(
                  children: [
                    const SkeletonBox(width: 46, height: 46, radius: 14),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FractionallySizedBox(widthFactor: i.isEven ? 0.7 : 0.55, child: const SkeletonBox(height: 15)),
                          const SizedBox(height: 8),
                          const FractionallySizedBox(widthFactor: 0.45, child: SkeletonBox(height: 11)),
                          const SizedBox(height: 10),
                          const SkeletonBox(width: 84, height: 22, radius: 100),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}


/// Sahifa pastga aylantirilganda status bar (soat) ostiga fon chiqaradi — matn soat ustiga
/// tushmaydi. Tepada (aylantirilmaganda) shaffof: sahifa foni ko'rinib turadi.
class StatusBarScrim extends StatefulWidget {
  const StatusBarScrim({super.key, required this.child, this.threshold = 40});

  /// Aylantiriladigan sahifa (CustomScrollView va h.k.)
  final Widget child;
  final double threshold;

  @override
  State<StatusBarScrim> createState() => _StatusBarScrimState();
}

class _StatusBarScrimState extends State<StatusBarScrim> {
  final _scrolled = ValueNotifier(false);

  @override
  void dispose() {
    _scrolled.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.depth == 0) _scrolled.value = n.metrics.pixels > widget.threshold;
            return false;
          },
          child: widget.child,
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: top,
          child: IgnorePointer(
            child: ValueListenableBuilder<bool>(
              valueListenable: _scrolled,
              builder: (context, scrolled, _) => AnimatedOpacity(
                opacity: scrolled ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
