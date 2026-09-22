import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';

/// Android 12+ da ro'yxat chetiga yetganda kontent "cho'ziladi" (stretch overscroll).
/// Ta'lim ilovasida bu chalg'ituvchi va "buzilgan"dek ko'rinadi: effektni o'chirib,
/// tekis, barqaror scroll qoldiramiz (pull-to-refresh baribir ishlaydi).
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => const ClampingScrollPhysics();
}

class MentorApp extends ConsumerWidget {
  const MentorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final appearance = ref.watch(appearanceProvider);

    return MaterialApp.router(
      title: 'Mentor AI',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      scrollBehavior: const _AppScrollBehavior(),
      themeMode: appearance.mode,
      theme: buildTheme(Brightness.light, appearance.accent.color),
      darkTheme: buildTheme(Brightness.dark, appearance.accent.color),
      themeAnimationDuration: const Duration(milliseconds: 250),
      // Kalendar, tugmalar va boshqa tizim matnlari o'zbekcha
      locale: const Locale('uz'),
      supportedLocales: const [Locale('uz'), Locale('ru'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) {
        // Tizim shrift o'lchamini hurmat qilamiz, lekin dizayn buzilmasligi uchun chegaralaymiz
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.3)),
          child: child!,
        );
      },
    );
  }
}
