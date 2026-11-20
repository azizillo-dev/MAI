import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../application/auth_controller.dart';
import '../application/sign_in_flow.dart';
import '../data/auth_models.dart';
import '../data/auth_repository.dart';

/// "Google bilan davom etish": email Google'da tasdiqlangan — kod kutilmaydi.
/// Akkaunt bo'lsa — darhol kiradi; bo'lmasa — ro'yxatdan o'tish (ism-familiya oldindan to'ladi).
class GoogleSignInButton extends ConsumerStatefulWidget {
  const GoogleSignInButton({super.key});

  @override
  ConsumerState<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends ConsumerState<GoogleSignInButton> {
  static bool _initialized = false;
  bool _loading = false;

  Future<void> _signIn() async {
    if (_loading) return;
    HapticFeedback.selectionClick();
    if (Env.googleServerClientId.isEmpty) {
      showSnack(context, "Google orqali kirish tez orada ishga tushadi. Hozircha email orqali kiring");
      return;
    }
    setState(() => _loading = true);
    try {
      final google = GoogleSignIn.instance;
      if (!_initialized) {
        await google.initialize(serverClientId: Env.googleServerClientId);
        _initialized = true;
      }
      final account = await google.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) throw const GoogleSignInException(code: GoogleSignInExceptionCode.unknownError);
      final result = await ref.read(authRepositoryProvider).signInWithGoogle(idToken);
      if (!mounted) return;
      switch (result) {
        case OtpLoggedIn(:final tokens, :final me):
          ref.read(signInFlowProvider.notifier).reset();
          await ref.read(authControllerProvider.notifier).signIn(tokens, me);
        case OtpNeedsRegistration(:final registrationToken, :final firstName, :final lastName):
          ref.read(signInFlowProvider.notifier).needsRegistration(
                registrationToken,
                firstName: firstName,
                lastName: lastName,
              );
          final role = ref.read(signInFlowProvider).role;
          context.push(switch (role) {
            UserRole.teacher => '/auth/register/teacher',
            UserRole.student => '/auth/register/student',
            _ => '/auth/role',
          });
      }
    } on GoogleSignInException catch (e) {
      // Foydalanuvchi oynani yopsa — xato ko'rsatmaymiz
      if (e.code != GoogleSignInExceptionCode.canceled && mounted) {
        showSnack(context, "Google orqali kirib bo'lmadi. Qayta urinib ko'ring", error: true);
      }
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return OutlinedButton(
      onPressed: _signIn,
      style: OutlinedButton.styleFrom(
        backgroundColor: dark ? const Color(0xFF131C31) : Colors.white,
        foregroundColor: context.colors.onSurface,
        side: BorderSide(color: context.colors.outlineVariant),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        child: _loading
            ? const SizedBox(key: ValueKey('l'), width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
            : const Row(
                key: ValueKey('t'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(dimension: 20, child: CustomPaint(painter: _GoogleGPainter())),
                  SizedBox(width: 12),
                  Text('Google bilan davom etish'),
                ],
              ),
      ),
    );
  }
}

/// "yoki" ajratgichi
class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.onSurfaceVariant;
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('yoki', style: TextStyle(color: muted, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}

/// Google'ning rangli "G" belgisi (rasm faylisiz, vektor)
class _GoogleGPainter extends CustomPainter {
  const _GoogleGPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = s * 0.2;
    final rect = Rect.fromCircle(center: Offset(s / 2, s / 2), radius: (s - stroke) / 2);
    Paint p(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    double deg(double d) => d * math.pi / 180;
    // Soat yo'nalishi bo'yicha, 0° — o'ng tomon
    canvas.drawArc(rect, deg(-40), deg(-95), false, p(const Color(0xFFEA4335))); // qizil (tepa)
    canvas.drawArc(rect, deg(-135), deg(-90), false, p(const Color(0xFFFBBC05))); // sariq (chap)
    canvas.drawArc(rect, deg(135), deg(-90), false, p(const Color(0xFF34A853))); // yashil (past)
    canvas.drawArc(rect, deg(45), deg(-45), false, p(const Color(0xFF4285F4))); // ko'k (o'ng past)
    // Ko'k gorizontal chiziq
    canvas.drawRect(
      Rect.fromLTWH(s / 2, s / 2 - stroke / 2, s / 2 - stroke * 0.1, stroke),
      Paint()..color = const Color(0xFF4285F4),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
