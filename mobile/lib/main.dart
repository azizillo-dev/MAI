import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Ekran chetidan chetigacha: status va navigatsiya paneli shaffof
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final (prefs, _) = await (SharedPreferences.getInstance(), _enableHighRefreshRate()).wait;

  runApp(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const MentorApp(),
    ),
  );
}

/// Ko'p Android telefonlar Flutter ilovalarini standart holatda 60 Hz'da ochadi.
/// Ekran qo'llasa, 90/120 Hz rejimni yoqamiz (animatsiya va scroll silliq bo'ladi).
Future<void> _enableHighRefreshRate() async {
  if (!Platform.isAndroid) return;
  try {
    await FlutterDisplayMode.setHighRefreshRate();
  } on Object {
    // Eski qurilmalar/emulyator: standart chastotada qoladi
  }
}
