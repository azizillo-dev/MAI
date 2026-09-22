import 'package:flutter/material.dart';

/// Ta'lim uchun palitra: tinch, ishonchli, ko'zni charchatmaydigan.
abstract final class Palette {
  static const indigo = Color(0xFF4F46E5);
  static const success = Color(0xFF16A34A);
  static const info = Color(0xFF0EA5E9);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFDC2626);
  static const gold = Color(0xFFEAB308);
  static const silver = Color(0xFF94A3B8);
  static const bronze = Color(0xFFB45309);

  // Neytral (slate)
  static const slate50 = Color(0xFFF8FAFC);
  static const slate100 = Color(0xFFF1F5F9);
  static const slate200 = Color(0xFFE2E8F0);
  static const slate500 = Color(0xFF64748B);
  static const slate700 = Color(0xFF334155);
  static const slate800 = Color(0xFF1E293B);
  static const slate900 = Color(0xFF0F172A);
  static const slate950 = Color(0xFF020617);
}

/// Sozlamalarda tanlanadigan asosiy ranglar.
enum AccentColor {
  indigo('Indigo', Color(0xFF4F46E5)),
  blue("Ko'k", Color(0xFF2563EB)),
  emerald('Yashil', Color(0xFF059669)),
  violet('Binafsha', Color(0xFF7C3AED)),
  pink('Pushti', Color(0xFFDB2777)),
  orange("To'q sariq", Color(0xFFEA580C));

  const AccentColor(this.label, this.color);
  final String label;
  final Color color;
}

/// Semantik ranglar: holatlar (muvaffaqiyat, ogohlantirish...) doim rang + ikonka + matn bilan ko'rsatiladi.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.success,
    required this.successContainer,
    required this.warning,
    required this.warningContainer,
    required this.danger,
    required this.dangerContainer,
    required this.info,
    required this.infoContainer,
    required this.muted,
    required this.border,
  });

  final Color success;
  final Color successContainer;
  final Color warning;
  final Color warningContainer;
  final Color danger;
  final Color dangerContainer;
  final Color info;
  final Color infoContainer;
  final Color muted;
  final Color border;

  static const light = AppColors(
    success: Palette.success,
    successContainer: Color(0xFFDCFCE7),
    warning: Color(0xFFB45309),
    warningContainer: Color(0xFFFEF3C7),
    danger: Palette.danger,
    dangerContainer: Color(0xFFFEE2E2),
    info: Color(0xFF0284C7),
    infoContainer: Color(0xFFE0F2FE),
    muted: Palette.slate500,
    border: Palette.slate200,
  );

  static const dark = AppColors(
    success: Color(0xFF4ADE80),
    successContainer: Color(0xFF14532D),
    warning: Color(0xFFFBBF24),
    warningContainer: Color(0xFF451A03),
    danger: Color(0xFFF87171),
    dangerContainer: Color(0xFF450A0A),
    info: Color(0xFF38BDF8),
    infoContainer: Color(0xFF082F49),
    muted: Color(0xFF94A3B8),
    border: Color(0xFF334155),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      success: l(success, other.success),
      successContainer: l(successContainer, other.successContainer),
      warning: l(warning, other.warning),
      warningContainer: l(warningContainer, other.warningContainer),
      danger: l(danger, other.danger),
      dangerContainer: l(dangerContainer, other.dangerContainer),
      info: l(info, other.info),
      infoContainer: l(infoContainer, other.infoContainer),
      muted: l(muted, other.muted),
      border: l(border, other.border),
    );
  }
}

extension AppThemeX on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
  TextTheme get text => Theme.of(this).textTheme;
}
