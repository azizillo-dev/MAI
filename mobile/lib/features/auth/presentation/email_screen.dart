import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// O'zbekistonda eng ko'p ishlatiladigan pochta xizmatlari — bir bosishda qo'shiladi
const _domains = ['gmail.com', 'mail.ru', 'icloud.com', 'yandex.ru', 'inbox.uz'];

/// Ko'p uchraydigan xato yozilishlar → to'g'ri domen
const _typos = {
  'gmial.com': 'gmail.com', 'gmai.com': 'gmail.com', 'gmal.com': 'gmail.com', 'gamil.com': 'gmail.com',
  'gmail.co': 'gmail.com', 'gmail.con': 'gmail.com', 'gmail.cm': 'gmail.com', 'gmail.ru': 'gmail.com',
  'gmaill.com': 'gmail.com', 'gnail.com': 'gmail.com', 'mail.r': 'mail.ru', 'mail.ry': 'mail.ru',
  'mial.ru': 'mail.ru', 'yandex.r': 'yandex.ru', 'yandeks.ru': 'yandex.ru', 'icloud.co': 'icloud.com',
  'iclod.com': 'icloud.com',
};

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

  /// "ali@gmial.com" → "ali@gmail.com"
  String? get _typoFix {
    final at = _email.lastIndexOf('@');
    if (at < 1) return null;
    final fixed = _typos[_email.substring(at + 1)];
    return fixed == null ? null : '${_email.substring(0, at)}@$fixed';
  }

  /// "@" dan keyin yozilgan qismga mos keladigan domenlar (yoki "@" hali yo'q bo'lsa — hammasi)
  List<String> get _domainHints {
    final text = _email;
    if (text.isEmpty) return const [];
    final at = text.indexOf('@');
    if (at == 0) return const [];
    if (at < 0) return _domains;
    final typed = text.substring(at + 1);
    if (_domains.contains(typed)) return const [];
    return _domains.where((d) => d.startsWith(typed)).toList();
  }

  void _applyDomain(String domain) {
    final at = _email.indexOf('@');
    final name = at < 0 ? _email : _email.substring(0, at);
    _setText('$name@$domain');
  }

  void _setText(String value) {
    HapticFeedback.selectionClick();
    _controller.value = TextEditingValue(text: value, selection: TextSelection.collapsed(offset: value.length));
    setState(() => _error = null);
  }

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
    if (_loading || _email.isEmpty) return;
    if (!_valid) {
      // Tugma o'chib turmaydi — nima noto'g'riligini aniq aytamiz
      setState(() => _error = _email.contains('@')
          ? "Email to'liq yozilmagan"
          : "Email noto'g'ri kiritilgan");
      return;
    }
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

  /// Maydon ostida: xato yozilgan domen tuzatmasi, domen tugmalari yoki oddiy izoh
  Widget _buildHelper(BuildContext context) {
    final fix = _typoFix;
    if (fix != null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: ActionChip(
          avatar: Icon(Icons.auto_fix_high_rounded, size: 18, color: context.colors.primary),
          label: Text.rich(TextSpan(children: [
            const TextSpan(text: 'Balki '),
            TextSpan(text: fix, style: const TextStyle(fontWeight: FontWeight.w700)),
            const TextSpan(text: '?'),
          ])),
          onPressed: () => _setText(fix),
        ),
      );
    }
    final hints = _domainHints;
    if (hints.isNotEmpty) {
      return SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: hints.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) => ActionChip(
            label: Text('@${hints[i]}'),
            onPressed: () => _applyDomain(hints[i]),
          ),
        ),
      );
    }
    return Row(
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
    );
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
                textCapitalization: TextCapitalization.none,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.email],
                // Email'da bo'sh joy bo'lmaydi: tasodifan qo'yilgan probel xatoga sabab bo'lmasin
                inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: 'Emailni kiriting',
                  errorText: _error,
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Tozalash',
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => _setText(''),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _buildHelper(context),
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
                onPressed: _email.isEmpty ? null : _submit,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
