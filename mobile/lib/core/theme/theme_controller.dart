import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';

/// main() da SharedPreferences yuklanib, override qilinadi (birinchi kadrda tema to'g'ri chiqishi uchun).
final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

class AppearanceState {
  const AppearanceState({required this.mode, required this.accent});

  final ThemeMode mode;
  final AccentColor accent;

  AppearanceState copyWith({ThemeMode? mode, AccentColor? accent}) =>
      AppearanceState(mode: mode ?? this.mode, accent: accent ?? this.accent);
}

final appearanceProvider = NotifierProvider<AppearanceController, AppearanceState>(AppearanceController.new);

class AppearanceController extends Notifier<AppearanceState> {
  static const _kMode = 'theme_mode';
  static const _kAccent = 'accent_color';

  SharedPreferences get _prefs => ref.read(sharedPrefsProvider);

  @override
  AppearanceState build() {
    final prefs = ref.watch(sharedPrefsProvider);
    return AppearanceState(
      mode: ThemeMode.values.asNameMap()[prefs.getString(_kMode)] ?? ThemeMode.system,
      accent: AccentColor.values.asNameMap()[prefs.getString(_kAccent)] ?? AccentColor.indigo,
    );
  }

  void setMode(ThemeMode mode) {
    state = state.copyWith(mode: mode);
    _prefs.setString(_kMode, mode.name);
  }

  void setAccent(AccentColor accent) {
    state = state.copyWith(accent: accent);
    _prefs.setString(_kAccent, accent.name);
  }
}
