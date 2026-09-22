import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../auth/application/auth_controller.dart';
import 'onboarding_repository.dart';

const _icons = <String, IconData>{
  'book': Icons.menu_book_rounded,
  'users': Icons.groups_rounded,
  'building': Icons.apartment_rounded,
  'star': Icons.star_rounded,
  'scale': Icons.balance_rounded,
  'chat': Icons.chat_bubble_rounded,
  'edit': Icons.edit_note_rounded,
};

/// O'qituvchini AI o'rganishi uchun savollar.
/// [editMode] = true: sozlamalardan ochilgan, javoblar oldindan to'ldiriladi.
class TeacherOnboardingScreen extends ConsumerWidget {
  const TeacherOnboardingScreen({super.key, this.editMode = false});

  final bool editMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final questions = ref.watch(onboardingQuestionsProvider);
    final answers = editMode ? ref.watch(onboardingAnswersProvider) : const AsyncData(<String, dynamic>{});

    return Scaffold(
      body: SafeArea(
        child: switch ((questions, answers)) {
          (AsyncData(value: final qs), AsyncData(value: final initial)) =>
            _Wizard(questions: qs, initial: initial, editMode: editMode),
          (AsyncError(:final error), _) || (_, AsyncError(:final error)) => Center(
              child: ErrorRetry(
                error: error,
                onRetry: () {
                  ref.invalidate(onboardingQuestionsProvider);
                  ref.invalidate(onboardingAnswersProvider);
                },
              ),
            ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _Wizard extends ConsumerStatefulWidget {
  const _Wizard({required this.questions, required this.initial, required this.editMode});

  final List<OnboardingQuestion> questions;
  final Map<String, dynamic> initial;
  final bool editMode;

  @override
  ConsumerState<_Wizard> createState() => _WizardState();
}

class _WizardState extends ConsumerState<_Wizard> {
  final _pages = PageController();
  late final Map<String, dynamic> _answers = Map.of(widget.initial);
  final Map<String, TextEditingController> _text = {};
  int _index = 0;
  bool _saving = false;
  bool _done = false;

  List<OnboardingQuestion> get _qs => widget.questions;
  bool get _isLast => _index == _qs.length - 1;

  @override
  void initState() {
    super.initState();
    for (final q in _qs.where((q) => q.type == QuestionType.text)) {
      _text[q.id] = TextEditingController(text: _answers[q.id] as String? ?? '');
    }
    // Birinchi marta: ro'yxatdan o'tishdan keyin tanlangan fan yo'q, hech narsa oldindan tanlanmaydi
  }

  @override
  void dispose() {
    _pages.dispose();
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool _answered(OnboardingQuestion q) {
    final v = q.type == QuestionType.text ? _text[q.id]!.text.trim() : _answers[q.id];
    if (v == null) return false;
    if (v is String) return v.isNotEmpty;
    if (v is List) return v.isNotEmpty;
    return true;
  }

  void _goTo(int i) {
    FocusScope.of(context).unfocus();
    setState(() => _index = i);
    _pages.animateToPage(i, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  Future<void> _next() async {
    if (!_isLast) return _goTo(_index + 1);
    for (final q in _qs.where((q) => q.type == QuestionType.text)) {
      final t = _text[q.id]!.text.trim();
      if (t.isEmpty) {
        _answers.remove(q.id);
      } else {
        _answers[q.id] = t;
      }
    }
    setState(() => _saving = true);
    try {
      await ref.read(onboardingRepositoryProvider).save(_answers);
      HapticFeedback.mediumImpact();
      if (widget.editMode) {
        ref.invalidate(onboardingAnswersProvider);
        await ref.read(authControllerProvider.notifier).refreshMe();
        if (mounted) {
          showSnack(context, 'AI profilingiz yangilandi');
          context.pop();
        }
      } else {
        setState(() => _done = true);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      final firstBad = _qs.indexWhere((q) => e.fieldErrors.containsKey(q.id));
      if (firstBad >= 0) _goTo(firstBad);
      showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _finish() async {
    // /me yangilanadi: next_step = home bo'ladi va router bosh sahifaga o'tkazadi
    setState(() => _saving = true);
    try {
      await ref.read(authControllerProvider.notifier).refreshMe();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return _DoneView(onContinue: _finish, loading: _saving);

    final q = _qs[_index];
    final canContinue = !q.required || _answered(q);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
          child: Row(
            children: [
              IconButton(
                onPressed: _index == 0
                    ? (widget.editMode ? () => context.pop() : null)
                    : () => _goTo(_index - 1),
                icon: Icon(_index == 0 && widget.editMode ? Icons.close_rounded : Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: (_index + 1) / _qs.length),
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => ClipRRect(
                    borderRadius: BorderRadius.circular(100),
                    child: LinearProgressIndicator(value: v, minHeight: 8),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${_index + 1}/${_qs.length}',
                style: context.text.labelLarge?.copyWith(color: context.colors.onSurfaceVariant, fontSize: 14),
              ),
            ],
          ),
        ),
        Expanded(
          child: PageView.builder(
            controller: _pages,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _qs.length,
            itemBuilder: (context, i) => _QuestionPage(
              question: _qs[i],
              value: _answers[_qs[i].id],
              textController: _text[_qs[i].id],
              isFirst: i == 0 && !widget.editMode,
              onChanged: (v) => setState(() => _answers[_qs[i].id] = v),
              onTextChanged: () => setState(() {}),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            children: [
              PrimaryButton(
                label: _isLast ? (widget.editMode ? 'Saqlash' : 'Yakunlash') : 'Keyingi',
                loading: _saving,
                onPressed: canContinue ? _next : null,
              ),
              if (!q.required && !_answered(q))
                TextButton(onPressed: _saving ? null : _next, child: const Text("O'tkazib yuborish")),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuestionPage extends StatelessWidget {
  const _QuestionPage({
    required this.question,
    required this.value,
    required this.onChanged,
    required this.onTextChanged,
    required this.isFirst,
    this.textController,
  });

  final OnboardingQuestion question;
  final Object? value;
  final ValueChanged<Object> onChanged;
  final VoidCallback onTextChanged;
  final TextEditingController? textController;
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    final q = question;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      children: [
        if (isFirst) ...[
          const InfoBanner(
            icon: Icons.auto_awesome_rounded,
            text: "Bir necha savol — AI vazifalarni aynan sizning uslubingizda tekshirishi uchun. "
                "Javoblarni keyin sozlamalardan o'zgartirishingiz mumkin.",
          ),
          const SizedBox(height: 24),
        ],
        // ListView farzandlarni to'liq kenglikka cho'zadi: Align bilan 56x56 kvadrat saqlanadi
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: context.colors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(_icons[q.icon] ?? Icons.help_outline_rounded, color: context.colors.primary, size: 30),
          ),
        ),
        const SizedBox(height: 16),
        Text(q.title, style: context.text.headlineSmall),
        if (q.hint != null) ...[
          const SizedBox(height: 6),
          Text(q.hint!, style: context.text.bodyLarge?.copyWith(color: context.colors.onSurfaceVariant)),
        ],
        const SizedBox(height: 20),
        ...switch (q.type) {
          QuestionType.single => [
              for (final o in q.options)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _OptionTile(
                    option: o,
                    selected: value == o.id,
                    multi: false,
                    onTap: () => onChanged(o.id),
                  ),
                ),
            ],
          QuestionType.multi => [
              for (final o in q.options)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _OptionTile(
                    option: o,
                    selected: (value as List?)?.contains(o.id) ?? false,
                    multi: true,
                    onTap: () {
                      final current = List<String>.from((value as List?) ?? const []);
                      current.contains(o.id) ? current.remove(o.id) : current.add(o.id);
                      onChanged(current);
                    },
                  ),
                ),
            ],
          QuestionType.text => [
              TextField(
                controller: textController,
                maxLength: q.maxLength,
                minLines: 4,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => onTextChanged(),
                decoration: const InputDecoration(hintText: 'Yozing...'),
              ),
            ],
        },
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.option, required this.selected, required this.multi, required this.onTap});

  final OnboardingOption option;
  final bool selected;
  final bool multi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = context.colors.primary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: selected ? primary.withValues(alpha: 0.08) : context.colors.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: selected ? primary : context.colors.outlineVariant, width: selected ? 2 : 1.2),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.md),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(option.label, style: context.text.titleMedium),
                      if (option.description != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          option.description!,
                          style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: Icon(
                    key: ValueKey(selected),
                    selected
                        ? (multi ? Icons.check_box_rounded : Icons.radio_button_checked_rounded)
                        : (multi ? Icons.check_box_outline_blank_rounded : Icons.radio_button_off_rounded),
                    color: selected ? primary : context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DoneView extends StatelessWidget {
  const _DoneView({required this.onContinue, required this.loading});

  final VoidCallback onContinue;
  final bool loading;

  @override
  Widget build(BuildContext context) {
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
              decoration: BoxDecoration(color: context.appColors.successContainer, shape: BoxShape.circle),
              child: Icon(Icons.check_rounded, size: 60, color: context.appColors.success),
            ),
          ),
          const SizedBox(height: 28),
          Text('Tayyor!', style: context.text.headlineMedium),
          const SizedBox(height: 10),
          Text(
            "AI endi sizning uslubingizni biladi. Keyingi qadam — birinchi guruhingizni yarating "
            "va o'quvchilarni taklif qiling.",
            textAlign: TextAlign.center,
            style: context.text.bodyLarge?.copyWith(color: context.colors.onSurfaceVariant),
          ),
          const Spacer(),
          PrimaryButton(
            label: 'Boshlash',
            icon: Icons.arrow_forward_rounded,
            loading: loading,
            onPressed: onContinue,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
