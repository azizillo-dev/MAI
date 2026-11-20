import 'package:flutter/material.dart';

/// Brend ranglari: logo va kirish videosidagi to'q fon
abstract final class BrandColors {
  /// Ochilish ekrani foni (Android colors.xml bilan bir xil): yorug' rejimda och siyohrang —
  /// to'q logo plitkasi ajralib turadi; qorong'i rejimda — juda to'q emas, logo bo'g'ilmaydi
  static const splashLight = Color(0xFFF4F5FF);
  static const splashDark = Color(0xFF141A3A);
  static const glow = Color(0xFF6D5BFF);

  static Color splash(BuildContext context) =>
      MediaQuery.platformBrightnessOf(context) == Brightness.dark ? splashDark : splashLight;
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
