import 'package:flutter/material.dart';

/// Brend ranglari: logo va kirish videosidagi to'q fon
abstract final class BrandColors {
  /// Splash, kirish videosi va Android ochilish ekrani foni (colors.xml bilan bir xil)
  static const night = Color(0xFF03041A);
  static const glow = Color(0xFF6D5BFF);
}

/// Mentor AI logotipi: yumaloq kvadrat plitka (ilova ikonkasi bilan bir xil)
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 96, this.glow, this.glowStrength = 1});

  final double size;

  /// Plitka atrofidagi yumshoq nur rangi
  final Color? glow;

  /// Nur kuchi (0 — nursiz), animatsiyada o'zgartiriladi
  final double glowStrength;

  /// Plitka burchagi radiusining o'lchamga nisbati (rasmdagidek)
  static const cornerRatio = 0.315;

  @override
  Widget build(BuildContext context) {
    final shadow = glow ?? BrandColors.glow;
    return Container(
      width: size,
      height: size,
      decoration: glowStrength <= 0
          ? null
          : BoxDecoration(
              borderRadius: BorderRadius.circular(size * cornerRatio),
              boxShadow: [
                BoxShadow(
                  color: shadow.withValues(alpha: 0.38 * glowStrength.clamp(0, 1.5)),
                  blurRadius: size * 0.32,
                  offset: Offset(0, size * 0.1),
                ),
              ],
            ),
      child: Image.asset(
        'assets/branding/logo_tile.png',
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
        cacheWidth: (size * 3).round(),
        semanticLabel: 'Mentor AI',
      ),
    );
  }
}
