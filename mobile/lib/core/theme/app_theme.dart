import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

abstract final class Insets {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;

  /// Ekran chetidan standart masofa
  static const screen = EdgeInsets.symmetric(horizontal: 20);
}

abstract final class Radii {
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 20.0;
  static const xl = 28.0;
}

ThemeData buildTheme(Brightness brightness, Color accent) {
  final isDark = brightness == Brightness.dark;
  final base = ColorScheme.fromSeed(seedColor: accent, brightness: brightness);
  final scheme = base.copyWith(
    primary: isDark ? Color.lerp(accent, Colors.white, 0.25) : accent,
    surface: isDark ? Palette.slate900 : Colors.white,
    surfaceContainerLowest: isDark ? Palette.slate950 : Colors.white,
    surfaceContainerLow: isDark ? const Color(0xFF131C31) : Palette.slate50,
    surfaceContainer: isDark ? Palette.slate800 : Palette.slate100,
    onSurface: isDark ? Palette.slate50 : Palette.slate900,
    onSurfaceVariant: isDark ? const Color(0xFF94A3B8) : Palette.slate500,
    outlineVariant: isDark ? Palette.slate700 : Palette.slate200,
    error: isDark ? const Color(0xFFF87171) : Palette.danger,
  );
  final appColors = isDark ? AppColors.dark : AppColors.light;
  final background = isDark ? Palette.slate950 : Palette.slate50;

  final textTheme = Typography.material2021(platform: TargetPlatform.android)
      .englishLike
      .merge(isDark ? Typography.whiteMountainView : Typography.blackMountainView)
      .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface)
      .copyWith(
        headlineMedium: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, height: 1.2, color: scheme.onSurface),
        headlineSmall: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.25, color: scheme.onSurface),
        titleLarge: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: scheme.onSurface),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: scheme.onSurface),
        bodyLarge: TextStyle(fontSize: 16, height: 1.45, color: scheme.onSurface),
        bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: scheme.onSurface),
        labelLarge: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      );

  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(Radii.md),
    borderSide: BorderSide(color: scheme.outlineVariant),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    textTheme: textTheme,
    extensions: [appColors],
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()},
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      elevation: 0,
      titleTextStyle: textTheme.titleLarge,
      systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    ),
    // Yumshoq kartalar: ingichka ochiq chegara + yorug' temada juda nozik soya
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: isDark ? 0 : 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: isDark ? 0.8 : 0.55)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
        textStyle: textTheme.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
        side: BorderSide(color: scheme.outlineVariant),
        textStyle: textTheme.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(textStyle: textTheme.labelLarge?.copyWith(fontSize: 15)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(borderSide: BorderSide(color: scheme.primary, width: 1.6)),
      errorBorder: inputBorder.copyWith(borderSide: BorderSide(color: scheme.error)),
      focusedErrorBorder: inputBorder.copyWith(borderSide: BorderSide(color: scheme.error, width: 1.6)),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      errorMaxLines: 2,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primary.withValues(alpha: 0.14),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md))),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
  );
}
