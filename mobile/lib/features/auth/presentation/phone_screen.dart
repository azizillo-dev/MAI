import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import '../application/sign_in_flow.dart';
import '../data/auth_models.dart';
import '../data/auth_repository.dart';

class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  bool get _valid => digitsOnly(_controller.text).length == 9;

  @override
  void initState() {
    super.initState();
    final previous = ref.read(signInFlowProvider).phone;
    if (previous != null && previous.startsWith('+998')) {
      _controller.text = UzPhoneInputFormatter()
          .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: previous.substring(4)))
          .text;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_valid || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final phone = '+998${digitsOnly(_controller.text)}';
    try {
      final sent = await ref.read(authRepositoryProvider).requestOtp(phone);
      ref.read(signInFlowProvider.notifier).otpSent(sent.target, sent);
      if (mounted) context.push('/auth/otp');
    } on ApiException catch (e) {
      // Kod yaqinda yuborilgan bo'lsa, qayta so'ramasdan kod ekraniga o'tamiz
      final flow = ref.read(signInFlowProvider);
      if (e.code == 'OTP_RESEND_TOO_SOON' && flow.phone == phone && flow.otp != null) {
        if (mounted) context.push('/auth/otp');
      } else {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(signInFlowProvider).role;
    final subtitle = switch (role) {
      UserRole.teacher => "O'qituvchi sifatida ro'yxatdan o'tish yoki kirish",
      UserRole.student => "O'quvchi sifatida ro'yxatdan o'tish yoki kirish",
      _ => 'Akkauntingizga kirish',
    };

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: Insets.screen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Telefon raqamingiz', style: context.text.headlineSmall),
              const SizedBox(height: 6),
              Text(subtitle, style: context.text.bodyLarge?.copyWith(color: context.colors.onSurfaceVariant)),
              const SizedBox(height: 28),
              TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.telephoneNumberNational],
                inputFormatters: [UzPhoneInputFormatter()],
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: '90 123 45 67',
                  errorText: _error,
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(left: 16, right: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🇺🇿', style: TextStyle(fontSize: 20)),
                        const SizedBox(width: 8),
                        Text(
                          '+998',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: context.colors.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.lock_outline_rounded, size: 16, color: context.appColors.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Raqamingiz faqat kirish uchun ishlatiladi',
                      style: context.text.bodySmall?.copyWith(color: context.appColors.muted),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Center(
                child: TextButton.icon(
                  onPressed: () => context.pushReplacement('/auth/email'),
                  icon: const Icon(Icons.alternate_email_rounded),
                  label: const Text('Email orqali davom etish'),
                ),
              ),
              const SizedBox(height: 8),
              PrimaryButton(
                label: 'Kod olish',
                loading: _loading,
                onPressed: _valid ? _submit : null,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
