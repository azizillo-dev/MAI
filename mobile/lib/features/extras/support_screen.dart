import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_widgets.dart';
import 'extras_repository.dart';

const _kinds = {
  'help': ('Yordam', Icons.help_outline_rounded),
  'suggestion': ('Taklif', Icons.lightbulb_outline_rounded),
  'bug': ('Xato', Icons.bug_report_outlined),
};

/// "Yordam va taklif": foydalanuvchi jamoaga yozadi, javob shu yerda ko'rinadi
class SupportScreen extends ConsumerStatefulWidget {
  const SupportScreen({super.key});

  @override
  ConsumerState<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends ConsumerState<SupportScreen> {
  final _text = TextEditingController();
  String _kind = 'help';
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.length < 5) {
      showSnack(context, "Kamida bir-ikki so'z yozing", error: true);
      return;
    }
    setState(() => _sending = true);
    try {
      await ref.read(extrasRepositoryProvider).sendSupport(_kind, text);
      if (!mounted) return;
      _text.clear();
      FocusScope.of(context).unfocus();
      ref.invalidate(supportMessagesProvider);
      if (mounted) showSnack(context, 'Yuborildi! Javobni shu sahifada ko\'rasiz');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(supportMessagesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Yordam va taklif')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(supportMessagesProvider.future),
        child: ListView(
          padding: Insets.screen.copyWith(top: 8, bottom: 32),
          children: [
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Bizga yozing', style: context.text.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    "Savol, g'oya yoki xato — hammasini o'qiymiz va javob beramiz.",
                    style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: [
                      for (final e in _kinds.entries)
                        ButtonSegment(value: e.key, label: Text(e.value.$1), icon: Icon(e.value.$2)),
                    ],
                    selected: {_kind},
                    onSelectionChanged: (s) => setState(() => _kind = s.first),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _text,
                    minLines: 4,
                    maxLines: 8,
                    maxLength: 3000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: switch (_kind) {
                        'suggestion' => "Qaysi imkoniyat qo'shilsa qulay bo'lardi?",
                        'bug' => "Nima bo'ldi? Qaysi sahifada? Qadamlarini yozing",
                        _ => 'Savolingizni yozing',
                      },
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 12),
                  PrimaryButton(label: 'Yuborish', icon: Icons.send_rounded, loading: _sending, onPressed: _send),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text('Murojaatlarim', style: context.text.titleMedium),
            const SizedBox(height: 10),
            history.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(supportMessagesProvider)),
              data: (list) => list.isEmpty
                  ? Text(
                      "Hali murojaat yo'q",
                      style: context.text.bodyMedium?.copyWith(color: context.appColors.muted),
                    )
                  : Column(children: [for (final m in list) _MessageCard(m: m)]),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.m});

  final SupportMessage m;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (m.status) {
      'answered' => ('Javob berildi', StatusTone.success),
      'closed' => ('Yopilgan', StatusTone.neutral),
      _ => ("Ko'rib chiqilmoqda", StatusTone.warning),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_kinds[m.kind]?.$2 ?? Icons.chat_outlined, size: 18, color: context.colors.primary),
                const SizedBox(width: 6),
                Text(_kinds[m.kind]?.$1 ?? m.kind, style: context.text.labelLarge),
                const SizedBox(width: 8),
                Text(formatDateUz(m.createdAt),
                    style: context.text.bodySmall?.copyWith(color: context.appColors.muted)),
                const Spacer(),
                StatusChip(label: label, tone: tone),
              ],
            ),
            const SizedBox(height: 8),
            Text(m.text, style: context.text.bodyMedium),
            if (m.adminReply case final reply?) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.appColors.successContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Mentor AI jamoasi',
                        style: context.text.labelMedium?.copyWith(color: context.appColors.success)),
                    const SizedBox(height: 4),
                    Text(reply, style: context.text.bodyMedium),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
