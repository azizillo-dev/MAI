import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/otp_field.dart';
import '../application/auth_controller.dart';
import '../application/sign_in_flow.dart';
import '../data/auth_models.dart';
import '../data/auth_repository.dart';

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _code = TextEditingController();
  Timer? _timer;
  int _resendIn = 0;
  bool _verifying = false;
  bool _resending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final otp = ref.read(signInFlowProvider).otp;
    _startTimer(otp?.resendIn ?? 60);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startTimer(int seconds) {
    _timer?.cancel();
    setState(() => _resendIn = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendIn <= 1) t.cancel();
      if (mounted) setState(() => _resendIn = (_resendIn - 1).clamp(0, 9999));
    });
  }

  Future<void> _verify(String code) async {
    if (_verifying) return;
    final flow = ref.read(signInFlowProvider);
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      final result = await ref.read(authRepositoryProvider).verifyOtp(flow.phone!, code, channel: flow.channel);
      switch (result) {
        case OtpLoggedIn(:final tokens, :final me):
          ref.read(signInFlowProvider.notifier).reset();
          // Router avtomatik ravishda rolga mos bosh sahifaga o'tkazadi
          await ref.read(authControllerProvider.notifier).signIn(tokens, me);
        case OtpNeedsRegistration(:final registrationToken):
          ref.read(signInFlowProvider.notifier).needsRegistration(registrationToken);
          if (!mounted) return;
          final role = ref.read(signInFlowProvider).role;
          context.pushReplacement(switch (role) {
            UserRole.teacher => '/auth/register/teacher',
            UserRole.student => '/auth/register/student',
            _ => '/auth/role',
          });
      }
    } on ApiException catch (e) {
      _code.clear();
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _resend() async {
    final flow = ref.read(signInFlowProvider);
    final phone = flow.phone!;
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      final repo = ref.read(authRepositoryProvider);
      final sent = flow.channel == OtpChannel.email ? await repo.requestEmailOtp(phone) : await repo.requestOtp(phone);
      ref.read(signInFlowProvider.notifier).otpSent(phone, sent);
      _code.clear();
      _startTimer(sent.resendIn);
      if (mounted) showSnack(context, 'Yangi kod yuborildi');
    } on ApiException catch (e) {
      if (e.retryAfter != null) _startTimer(e.retryAfter!);
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(signInFlowProvider);
    final phone = flow.phone ?? '';
    final devCode = flow.otp?.devCode;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: Insets.screen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Tasdiqlash kodi', style: context.text.headlineSmall),
              const SizedBox(height: 6),
              Text.rich(
                TextSpan(
                  style: context.text.bodyLarge?.copyWith(color: context.colors.onSurfaceVariant),
                  children: [
                    const TextSpan(text: 'Kod '),
                    TextSpan(
                      text: maskTarget(phone),
                      style: TextStyle(fontWeight: FontWeight.w700, color: context.colors.onSurface),
                    ),
                    TextSpan(
                      text: flow.channel == OtpChannel.email
                          ? " manziliga yuborildi. Xat kelmasa, «Spam» papkasini tekshiring"
                          : ' raqamiga SMS orqali yuborildi',
                    ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  onPressed: () => context.pop(),
                  child: Text(flow.channel == OtpChannel.email ? "Emailni o'zgartirish" : "Raqamni o'zgartirish"),
                ),
              ),
              const SizedBox(height: 16),
              OtpField(
                controller: _code,
                hasError: _error != null,
                enabled: !_verifying,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onCompleted: _verify,
              ),
              const SizedBox(height: 12),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                child: _error == null
                    ? const SizedBox(width: double.infinity)
                    : Text(_error!, style: TextStyle(color: context.appColors.danger, fontSize: 14)),
              ),
              if (_verifying) ...[
                const SizedBox(height: 16),
                const Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3))),
              ],
              const SizedBox(height: 20),
              Center(
                child: _resendIn > 0
                    ? Text(
                        'Yangi kodni ${_formatSeconds(_resendIn)} dan keyin olish mumkin',
                        style: context.text.bodyMedium?.copyWith(color: context.appColors.muted),
                      )
                    : TextButton.icon(
                        onPressed: _resending ? null : _resend,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Kodni qayta yuborish'),
                      ),
              ),
              if (devCode != null && kDebugMode) ...[
                const SizedBox(height: 24),
                InfoBanner(
                  tone: StatusTone.warning,
                  title: 'DEV rejim',
                  text: 'Kod yuborilmadi (sinov rejimi). Test kodi: $devCode',
                ),
                TextButton(
                  onPressed: () {
                    _code.text = devCode;
                    _verify(devCode);
                  },
                  child: const Text('Kodni avtomatik kiritish'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatSeconds(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}
