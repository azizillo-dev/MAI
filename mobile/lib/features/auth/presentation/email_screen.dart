import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../application/sign_in_flow.dart';
import '../data/auth_models.dart';
import '../data/auth_repository.dart';

final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

/// Email orqali kirish/ro'yxatdan o'tish: manzilga 6 xonali kod yuboriladi
class EmailScreen extends ConsumerStatefulWidget {
  const EmailScreen({super.key});

  @override
  ConsumerState<EmailScreen> createState() => _EmailScreenState();
}

class _EmailScreenState extends ConsumerState<EmailScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  String get _email => _controller.text.trim().toLowerCase();
  bool get _valid => _emailRe.hasMatch(_email);

  @override
  void initState() {
    super.initState();
    final previous = ref.read(signInFlowProvider).phone;
    if (previous != null && previous.contains('@')) _controller.text = previous;
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
    final email = _email;
    try {
      final sent = await ref.read(authRepositoryProvider).requestEmailOtp(email);
      ref.read(signInFlowProvider.notifier).otpSent(sent.target, sent);
      if (mounted) context.push('/auth/otp');
    } on ApiException catch (e) {
      final flow = ref.read(signInFlowProvider);
      if (e.code == 'OTP_RESEND_TOO_SOON' && flow.phone == email && flow.otp != null) {
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
              Text('Email manzilingiz', style: context.text.headlineSmall),
              const SizedBox(height: 6),
              Text(subtitle, style: context.text.bodyLarge?.copyWith(color: context.colors.onSurfaceVariant)),
              const SizedBox(height: 28),
              TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.email],
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: 'Emailni kiriting',
                  errorText: _error,
                  prefixIcon: const Icon(Icons.alternate_email_rounded),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.mark_email_read_outlined, size: 16, color: context.appColors.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Shu manzilga 6 xonali tasdiqlash kodi yuboriladi',
                      style: context.text.bodySmall?.copyWith(color: context.appColors.muted),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (Env.smsEnabled || kDebugMode)
                Center(
                  child: TextButton.icon(
                    onPressed: () => context.pushReplacement('/auth/phone'),
                    icon: const Icon(Icons.phone_iphone_rounded),
                    label: const Text('Telefon raqam orqali'),
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
