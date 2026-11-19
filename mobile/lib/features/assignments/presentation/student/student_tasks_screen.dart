import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../../../core/widgets/motion.dart';
import '../../data/assignment_models.dart';
import '../../data/assignments_repository.dart';
import '../widgets.dart';

/// O'quvchining "Vazifalar" tabi: nima qilish kerakligi eng tepada.
class StudentTasksScreen extends ConsumerWidget {
  const StudentTasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(studentAssignmentsProvider);
    final list = async.value;

    Future<void> refresh() async {
      ref.invalidate(studentAssignmentsProvider);
      await ref.read(studentAssignmentsProvider.future);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Vazifalar')),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: list == null
            ? (async.hasError
                ? ListView(children: [ErrorRetry(error: async.error!, onRetry: refresh)])
                : const SkeletonList())
            : list.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 80),
                      EmptyState(
                        icon: Icons.assignment_turned_in_rounded,
                        title: "Hozircha vazifa yo'q",
                        message: 'Ustozingiz vazifa berishi bilan shu yerda paydo bo\'ladi.',
                      ),
                    ],
                  )
                : _Sections(list: list),
      ),
    );
  }
}

class _Sections extends StatelessWidget {
  const _Sections({required this.list});

  final List<StudentAssignment> list;

  @override
  Widget build(BuildContext context) {
    // Topshirsa bo'ladiganlar — eng yaqin muddat tepada
    final todo = list.where((a) => a.canSubmit).toList()..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    final checking = list.where((a) => a.submission != null && !a.submission!.isFinal).toList();
    final done = list.where((a) => a.submission?.isFinal ?? false).toList()
      ..sort((a, b) => b.submission!.submittedAt.compareTo(a.submission!.submittedAt));
    // Muddati o'tib, topshirib bo'lmaydiganlar "Topshirish kerak" sanog'iga kirmaydi — pastda, alohida
    final missed = list.where((a) => a.submission == null && !a.canSubmit).toList()
      ..sort((a, b) => b.dueAt.compareTo(a.dueAt));

    var index = 0;
    List<Widget> cards(List<StudentAssignment> items) => [
          for (final a in items) ...[
            FadeSlideIn(index: index++, child: StudentTaskCard(a: a)),
            const SizedBox(height: 10),
          ],
        ];

    return ListView(
      padding: Insets.screen.copyWith(top: 4, bottom: 24),
      children: [
        if (todo.isNotEmpty) ...[
          SectionTitle('Topshirish kerak', trailing: StatusChip(label: '${todo.length}', tone: StatusTone.warning)),
          ...cards(todo),
          const SizedBox(height: 10),
        ],
        if (checking.isNotEmpty) ...[
          const SectionTitle('Tekshirilmoqda'),
          ...cards(checking),
          const SizedBox(height: 10),
        ],
        if (done.isNotEmpty) ...[
          const SectionTitle('Baholangan'),
          ...cards(done),
          const SizedBox(height: 10),
        ],
        if (missed.isNotEmpty) ...[
          const SectionTitle("Muddati o'tgan"),
          ...cards(missed),
        ],
      ],
    );
  }
}

/// Vazifa kartasi. Holat bir qarashda ajraladi:
/// * chap chiziq — shoshilinch (sariq), muddati o'tgan (qizil), baholangan (yashil);
/// * o'ngda — baholangan bo'lsa baho doirasi, aks holda strelka;
/// * muddati o'tgan va topshirilmagan karta xira ko'rinadi.
class StudentTaskCard extends StatelessWidget {
  const StudentTaskCard({super.key, required this.a});

  final StudentAssignment a;

  @override
  Widget build(BuildContext context) {
    final s = a.submission;
    final c = context.appColors;
    final missed = s == null && !a.canSubmit;
    final urgent = s == null && a.canSubmit && !a.isOverdue && a.dueAt.difference(DateTime.now()).inHours < 24;
    final graded = s?.isFinal ?? false;

    final Widget status;
    if (s == null) {
      status = missed
          ? const StatusChip(label: 'Topshirilmagan', tone: StatusTone.danger, icon: Icons.alarm_off_rounded)
          : a.isOverdue
              ? const StatusChip(label: 'Kechikib topshirish mumkin', tone: StatusTone.warning, icon: Icons.history_rounded)
              : DueChip(due: a.dueAt);
    } else if (s.isFinal) {
      status = StatusChip(
        label: s.teacherScore != null ? 'Ustoz baholadi' : 'AI tekshirdi',
        tone: StatusTone.success,
        icon: Icons.check_circle_rounded,
      );
    } else {
      status = const StatusChip(label: 'Tekshirilmoqda', tone: StatusTone.info, icon: Icons.hourglass_top_rounded);
    }
    // Baholanganda doira o'zi yetarli — chiziq faqat e'tibor kerak bo'lganda
    final late = s == null && a.canSubmit && a.isOverdue;
    final accent = missed
        ? c.danger
        : (urgent || late)
            ? c.warning
            : null;

    final isMath = a.subject == 'math';
    final tint = missed ? c.muted : (isMath ? context.colors.primary : Palette.success);
    final muted = context.colors.onSurfaceVariant;

    final card = SectionCard(
      accent: accent,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      onTap: () => context.push('/student/tasks/${a.id}'),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [tint.withValues(alpha: 0.18), tint.withValues(alpha: 0.08)],
              ),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(isMath ? Icons.functions_rounded : Icons.translate_rounded, color: tint, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.title,
                  style: context.text.titleMedium?.copyWith(height: 1.25),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.groups_2_outlined, size: 14, color: muted),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        a.groupName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall?.copyWith(color: muted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    status,
                    Text(formatDueUz(a.dueAt), style: context.text.bodySmall?.copyWith(color: muted)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (graded)
            ScoreRing(score: s!.finalScore ?? 0, scale: s.scaleMax)
          else
            Icon(Icons.chevron_right_rounded, color: muted),
        ],
      ),
    );
    return missed ? Opacity(opacity: 0.72, child: card) : card;
  }
}
