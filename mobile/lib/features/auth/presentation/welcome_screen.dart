import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_logo.dart';
import '../application/auth_controller.dart';
import '../application/sign_in_flow.dart';
import '../data/auth_models.dart';

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> with TickerProviderStateMixin {
  // Bitta kontroller: elementlar ketma-ket (stagger) paydo bo'ladi
  late final _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();
  // Logotip sekin "suzadi"
  late final _float = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = ref.read(authControllerProvider);
      if (auth is AuthGuest && auth.sessionExpired && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sessiya muddati tugadi. Iltimos, qaytadan kiring')),
        );
      }
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    _float.dispose();
    super.dispose();
  }

  void _go(UserRole? role) {
    ref.read(signInFlowProvider.notifier).start(role);
    // SMS provayder ulanguncha asosiy yo'l — email orqali kod
    context.push('/auth/email');
  }

  Widget _reveal(double start, Widget child) => _Reveal(animation: _intro, start: start, child: child);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: _Backdrop()),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: Insets.screen,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Spacer(flex: 3),
                        _reveal(0.0, Center(child: _FloatingLogo(animation: _float))),
                        const SizedBox(height: 22),
                        _reveal(
                          0.1,
                          Text(
                            'Mentor AI',
                            textAlign: TextAlign.center,
                            style: context.text.headlineMedium?.copyWith(fontSize: 34, letterSpacing: -0.5),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _reveal(
                          0.18,
                          Text(
                            "Uy vazifalarini sun'iy intellekt tekshiradi.\nUstoz — o'qitishga, o'quvchi — o'sishga.",
                            textAlign: TextAlign.center,
                            style: context.text.bodyLarge?.copyWith(color: context.colors.onSurfaceVariant),
                          ),
                        ),
                        const SizedBox(height: 18),
                        _reveal(0.26, const _FeaturePills()),
                        const Spacer(flex: 2),
                        _reveal(
                          0.36,
                          Text(
                            'Kim sifatida davom etasiz?',
                            textAlign: TextAlign.center,
                            style: context.text.titleMedium?.copyWith(color: context.colors.onSurfaceVariant),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _reveal(
                          0.44,
                          RoleCard(
                            icon: Icons.school_rounded,
                            title: "Men o'qituvchiman",
                            subtitle: 'Guruh yarating, vazifa bering — AI tekshiradi',
                            onTap: () => _go(UserRole.teacher),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _reveal(
                          0.52,
                          RoleCard(
                            icon: Icons.backpack_rounded,
                            title: "Men o'quvchiman",
                            subtitle: "Vazifalarni topshiring, baho va XP to'plang",
                            color: Palette.success,
                            onTap: () => _go(UserRole.student),
                          ),
                        ),
                        const Spacer(flex: 3),
                        _reveal(
                          0.6,
                          TextButton(
                            onPressed: () => _go(null),
                            child: Text.rich(
                              TextSpan(
                                style: TextStyle(color: context.colors.onSurfaceVariant, fontWeight: FontWeight.w500),
                                children: [
                                  const TextSpan(text: 'Akkauntingiz bormi? '),
                                  TextSpan(
                                    text: 'Kirish',
                                    style: TextStyle(color: context.colors.primary, fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fade + yuqoriga siljish, [start] (0..1) dan boshlab
class _Reveal extends StatelessWidget {
  const _Reveal({required this.animation, required this.start, required this.child});

  final Animation<double> animation;
  final double start;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Interval(start, math.min(1, start + 0.45), curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(curved),
        child: child,
      ),
    );
  }
}

/// Fondagi yumshoq rangli "dog'lar". Blur ishlatilmaydi (qimmat) — radial gradient yetarli.
class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = context.colors.primary;
    final size = MediaQuery.sizeOf(context);

    Widget blob(Color color, double diameter, double alpha) => Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)]),
          ),
        );

    return RepaintBoundary(
      child: Stack(
        children: [
          Positioned(top: -size.width * 0.45, left: -size.width * 0.35, child: blob(primary, size.width * 1.3, dark ? 0.35 : 0.22)),
          Positioned(top: size.height * 0.08, right: -size.width * 0.5, child: blob(Palette.info, size.width * 1.1, dark ? 0.22 : 0.16)),
          Positioned(bottom: -size.width * 0.6, left: -size.width * 0.2, child: blob(Palette.success, size.width * 1.2, dark ? 0.14 : 0.10)),
        ],
      ),
    );
  }
}

class _FloatingLogo extends StatelessWidget {
  const _FloatingLogo({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, math.sin(animation.value * math.pi) * -6),
        child: child,
      ),
      child: const RepaintBoundary(child: AppLogo(size: 116)),
    );
  }
}

class _FeaturePills extends StatelessWidget {
  const _FeaturePills();

  @override
  Widget build(BuildContext context) {
    Widget pill(IconData icon, String text, Color color) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: context.colors.surface.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: context.colors.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.colors.onSurface)),
            ],
          ),
        );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        pill(Icons.auto_awesome_rounded, 'AI tekshiradi', context.colors.primary),
        pill(Icons.bolt_rounded, '1 daqiqada baho', Palette.warning),
        pill(Icons.emoji_events_rounded, 'XP va medallar', Palette.gold),
      ],
    );
  }
}

/// Rol kartasi: gradient ikonka, bosilganda biroz kichrayadi (jonli his).
class RoleCard extends StatefulWidget {
  const RoleCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? color;

  @override
  State<RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<RoleCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.color ?? context.colors.primary;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedScale(
      scale: _pressed ? 0.97 : 1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.surface.withValues(alpha: dark ? 0.85 : 1),
          borderRadius: BorderRadius.circular(Radii.lg + 2),
          border: Border.all(color: c.withValues(alpha: dark ? 0.35 : 0.22), width: 1.4),
          boxShadow: [
            BoxShadow(color: c.withValues(alpha: dark ? 0.18 : 0.10), blurRadius: 24, offset: const Offset(0, 10)),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.lg + 2),
            onHighlightChanged: (v) => setState(() => _pressed = v),
            onTap: () {
              HapticFeedback.lightImpact();
              widget.onTap();
            },
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [c, Color.lerp(c, Colors.white, 0.3)!],
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [BoxShadow(color: c.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 6))],
                    ),
                    child: Icon(widget.icon, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title, style: context.text.titleMedium?.copyWith(fontSize: 17)),
                        const SizedBox(height: 4),
                        Text(
                          widget.subtitle,
                          style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: c.withValues(alpha: 0.12), shape: BoxShape.circle),
                    child: Icon(Icons.arrow_forward_rounded, size: 18, color: c),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
