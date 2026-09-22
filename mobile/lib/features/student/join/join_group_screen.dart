import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/otp_field.dart';
import '../../groups/data/group_models.dart';
import '../../groups/data/groups_repository.dart';

/// Guruhga qo'shilish: 1) kod -> 2) guruhni ko'rib tasdiqlash + parol -> 3) natija.
/// QR yoki havoladan kelganda [invite] to'ldirilgan bo'ladi va parol so'ralmaydi.
class JoinGroupScreen extends ConsumerStatefulWidget {
  const JoinGroupScreen({super.key, this.invite});

  final InviteLink? invite;

  @override
  ConsumerState<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends ConsumerState<JoinGroupScreen> {
  final _code = TextEditingController();
  final _password = TextEditingController();
  InviteLink? _invite;
  JoinPreview? _preview;
  Membership? _result;
  bool _loading = false;
  String? _codeError;
  String? _passwordError;

  bool get _codeComplete => _code.text.replaceAll('-', '').length == 8;

  @override
  void initState() {
    super.initState();
    _invite = widget.invite;
    if (_invite != null) {
      _code.text = GroupCodeInputFormatter()
          .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: _invite!.code))
          .text;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadPreview());
    }
  }

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _loadPreview() async {
    if (!_codeComplete || _loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _codeError = null;
    });
    try {
      final p = await ref.read(groupsRepositoryProvider).preview(_code.text);
      setState(() => _preview = p);
    } on ApiException catch (e) {
      setState(() {
        _codeError = e.message;
        _invite = null;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _join() async {
    final viaInvite = _invite?.token != null;
    if (!viaInvite && _password.text.length != 8) {
      setState(() => _passwordError = "8 xonali parolni kiriting");
      return;
    }
    setState(() {
      _loading = true;
      _passwordError = null;
    });
    try {
      final m = await ref.read(groupsRepositoryProvider).join(
            code: _code.text,
            password: viaInvite ? null : _password.text,
            inviteToken: _invite?.token,
          );
      HapticFeedback.mediumImpact();
      ref.invalidate(membershipsProvider);
      setState(() => _result = m);
    } on ApiException catch (e) {
      setState(() {
        if (e.code == 'INVITE_EXPIRED') {
          // Eski QR/havola: parol bilan davom ettirish imkonini beramiz
          _invite = null;
          showSnack(context, e.message, error: true);
        } else if (e.code == 'GROUP_PASSWORD_INVALID' || e.code == 'JOIN_LOCKED') {
          _password.clear();
          _passwordError = e.message;
        } else {
          showSnack(context, e.message, error: true);
        }
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _scan() async {
    final link = await context.push<InviteLink>('/student/join/scan');
    if (link == null || !mounted) return;
    setState(() {
      _invite = link;
      _preview = null;
      _code.text = GroupCodeInputFormatter()
          .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: link.code))
          .text;
    });
    await _loadPreview();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Guruhga qo'shilish")),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          switchInCurve: Curves.easeOutCubic,
          child: _result != null
              ? _ResultView(key: const ValueKey('result'), membership: _result!)
              : _preview != null
                  ? _confirmStep(context)
                  : _codeStep(context),
        ),
      ),
    );
  }

  Widget _codeStep(BuildContext context) {
    return ListView(
      key: const ValueKey('code'),
      padding: Insets.screen.copyWith(top: 8, bottom: 24),
      children: [
        Text('Guruh kodini kiriting', style: context.text.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Kodni ustozingiz beradi. Masalan: K7M4-XQ9P',
          style: context.text.bodyLarge?.copyWith(color: context.colors.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _code,
          autofocus: widget.invite == null,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          enableSuggestions: false,
          inputFormatters: [GroupCodeInputFormatter()],
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 4),
          decoration: InputDecoration(hintText: 'XXXX-XXXX', errorText: _codeError, errorMaxLines: 3),
          onChanged: (_) {
            setState(() => _codeError = null);
            if (_codeComplete) _loadPreview();
          },
        ),
        const SizedBox(height: 20),
        PrimaryButton(label: 'Davom etish', loading: _loading, onPressed: _codeComplete ? _loadPreview : null),
        const SizedBox(height: 28),
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('yoki', style: TextStyle(color: context.colors.onSurfaceVariant)),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: _scan,
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: const Text('QR kodni skanerlash'),
        ),
      ],
    );
  }

  Widget _confirmStep(BuildContext context) {
    final p = _preview!;
    final viaInvite = _invite?.token != null;
    return ListView(
      key: const ValueKey('confirm'),
      padding: Insets.screen.copyWith(top: 8, bottom: 24),
      children: [
        Text("Shu guruhmi?", style: context.text.headlineSmall),
        const SizedBox(height: 16),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: context.colors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      p.subject == 'math' ? Icons.calculate_rounded : Icons.translate_rounded,
                      color: context.colors.primary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.groupName, style: context.text.titleLarge),
                        Text(subjectLabel(p.subject), style: TextStyle(color: context.colors.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _InfoRow(icon: Icons.person_rounded, label: 'Ustoz', value: p.teacherName),
              const SizedBox(height: 8),
              _InfoRow(icon: Icons.groups_rounded, label: "O'quvchilar", value: '${p.membersActive} ta'),
              const SizedBox(height: 8),
              _InfoRow(icon: Icons.tag_rounded, label: 'Kod', value: p.code),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const InfoBanner(
          icon: Icons.verified_user_rounded,
          text: "So'rovingizni ustoz tasdiqlagach guruhga kirasiz. Tasdiqlanganda bosh sahifada ko'rinadi.",
        ),
        const SizedBox(height: 24),
        if (!viaInvite) ...[
          Text('Guruh paroli', style: context.text.titleMedium),
          const SizedBox(height: 10),
          OtpField(
            controller: _password,
            length: 8,
            hasError: _passwordError != null,
            onChanged: (_) {
              if (_passwordError != null) setState(() => _passwordError = null);
            },
            onCompleted: (_) => _join(),
          ),
          if (_passwordError != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_passwordError!, style: TextStyle(color: context.appColors.danger)),
            ),
          const SizedBox(height: 24),
        ],
        PrimaryButton(label: "Qo'shilish", icon: Icons.login_rounded, loading: _loading, onPressed: _join),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _loading
              ? null
              : () => setState(() {
                    _preview = null;
                    _invite = null;
                    _password.clear();
                    _passwordError = null;
                  }),
          child: const Text('Boshqa kod kiritish'),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: context.colors.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: context.colors.onSurfaceVariant)),
        const Spacer(),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({super.key, required this.membership});

  final Membership membership;

  @override
  Widget build(BuildContext context) {
    final pending = membership.isPending;
    final (fg, bg) = pending
        ? (context.appColors.warning, context.appColors.warningContainer)
        : (context.appColors.success, context.appColors.successContainer);
    return Padding(
      padding: Insets.screen,
      child: Column(
        children: [
          const Spacer(),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.6, end: 1),
            duration: const Duration(milliseconds: 500),
            curve: Curves.elasticOut,
            builder: (context, s, child) => Transform.scale(scale: s, child: child),
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: Icon(pending ? Icons.hourglass_top_rounded : Icons.celebration_rounded, size: 54, color: fg),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            pending ? "So'rov yuborildi" : 'Tabriklaymiz! 🎉',
            style: context.text.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            pending
                ? "${membership.teacherName} so'rovingizni tasdiqlagach, «${membership.groupName}» guruhida bo'lasiz."
                : "Siz «${membership.groupName}» guruhiga qo'shildingiz. Ustozingiz: ${membership.teacherName}.",
            textAlign: TextAlign.center,
            style: context.text.bodyLarge?.copyWith(color: context.colors.onSurfaceVariant),
          ),
          const Spacer(),
          PrimaryButton(label: 'Bosh sahifaga', onPressed: () => context.go('/student')),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
