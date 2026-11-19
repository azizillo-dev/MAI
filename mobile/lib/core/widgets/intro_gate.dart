import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_logo.dart';

/// Ilova ochilganda brend kirishi: to'q fonda markazda logo qisqa (≈0.75 s) "nafas oladi",
/// keyin qatlam silliq yo'qolib, ilova ko'rinadi.
///
/// Android ochilish ekrani ham shu fon va shu o'lchamdagi logo — tizim splashidan
/// Flutter'ga o'tish bilinmaydi. Ilova ostida odatdagidek yuklanaveradi.
class IntroGate extends StatefulWidget {
  const IntroGate({super.key, required this.child});

  final Widget child;

  @override
  State<IntroGate> createState() => _IntroGateState();
}

const _tileAsset = 'assets/branding/logo_tile.png';

/// Android splashidagi plitka o'lchami (splash_icon.png, launch_image.png — 150dp)
const _splashTile = 150.0;

class _IntroGateState extends State<IntroGate> with TickerProviderStateMixin {
  bool _started = false;
  bool _done = false;

  /// Logo biroz kattalashadi va atrofida nur yonadi
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));

  /// Ustki qatlamning yo'qolishi
  late final _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));

  @override
  void initState() {
    super.initState();
    // Logo rasmi xotiraga yuklanmaguncha tizim splashi ushlab turiladi —
    // aks holda orada bo'sh qora kadrlar ko'rinadi
    WidgetsBinding.instance.deferFirstFrame();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    precacheImage(const AssetImage(_tileAsset), context)
        .timeout(const Duration(seconds: 2), onTimeout: () {})
        .whenComplete(() async {
      WidgetsBinding.instance.allowFirstFrame();
      if (!mounted) return;
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      if (!reduceMotion) await _pulse.forward();
      if (!mounted) return;
      await _fade.forward();
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    final scale = CurvedAnimation(parent: _pulse, curve: Curves.easeOutBack);
    final glow = CurvedAnimation(parent: _pulse, curve: const Interval(0, 0.7, curve: Curves.easeOut));
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        FadeTransition(
          opacity: ReverseAnimation(_fade),
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.light,
            child: ColoredBox(
              color: BrandColors.night,
              child: Center(
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) => Transform.scale(
                    scale: 1 + 0.08 * scale.value,
                    child: AppLogo(size: _splashTile, glowStrength: glow.value * 1.2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
