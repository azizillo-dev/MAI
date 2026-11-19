import 'package:flutter/material.dart';

import '../widgets/app_logo.dart';

/// Sessiya tekshirilayotganda: Android ochilish ekrani bilan bir xil (to'q fon, markazda plitka)
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: BrandColors.night,
        body: Center(child: AppLogo(size: 150, glowStrength: 0)),
      );
}
