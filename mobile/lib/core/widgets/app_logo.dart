import 'package:flutter/material.dart';

/// Mentor AI logotipi: oq doira ichida belgi (ilova ikonkasi bilan bir xil)
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 96, this.glow});

  final double size;
  /// Doira atrofidagi yumshoq soya rangi
  final Color? glow;

  @override
  Widget build(BuildContext context) {
    final shadow = glow ?? const Color(0xFF2E9BE0);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: shadow.withValues(alpha: 0.35), blurRadius: size * 0.3, offset: Offset(0, size * 0.12)),
        ],
      ),
      child: Image.asset(
        'assets/branding/logo.png',
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
        semanticLabel: 'Mentor AI',
      ),
    );
  }
}
