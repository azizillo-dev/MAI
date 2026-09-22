import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_widgets.dart';
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
                : const Center(child: CircularProgressIndicator()))
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
    final todo = list.where((a) => a.submission == null).toList()..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    final checking = list
        .where((a) => a.submission != null && !a.submission!.isFinal)
        .toList();
    final done = list.where((a) => a.submission?.isFinal ?? false).toList()
      ..sort((a, b) => b.submission!.submittedAt.compareTo(a.submission!.submittedAt));

    return ListView(
      padding: Insets.screen.copyWith(top: 4, bottom: 24),
      children: [
        if (todo.isNotEmpty) ...[
          SectionTitle('Topshirish kerak', trailing: StatusChip(label: '${todo.length}', tone: StatusTone.warning)),
          for (final a in todo) ...[StudentTaskCard(a: a), const SizedBox(height: 10)],
          const SizedBox(height: 10),
        ],
        if (checking.isNotEmpty) ...[
          const SectionTitle('Tekshirilmoqda'),
          for (final a in checking) ...[StudentTaskCard(a: a), const SizedBox(height: 10)],
          const SizedBox(height: 10),
        ],
        if (done.isNotEmpty) ...[
          const SectionTitle('Baholangan'),
          for (final a in done) ...[StudentTaskCard(a: a), const SizedBox(height: 10)],
        ],
      ],
    );
  }
}

class StudentTaskCard extends StatelessWidget {
  const StudentTaskCard({super.key, required this.a});

  final StudentAssignment a;

  @override
  Widget build(BuildContext context) {
    final s = a.submission;
    final Widget status = switch (s) {
      null => a.canSubmit
          ? DueChip(due: a.dueAt)
          : const StatusChip(label: "Muddati o'tdi", tone: StatusTone.danger, icon: Icons.alarm_off_rounded),
      Submission(isFinal: true) => StatusChip(
          label: '${scoreText(s.finalScore ?? 0)} / ${s.gradingScale}',
          tone: StatusTone.success,
          icon: Icons.star_rounded,
        ),
      _ => const StatusChip(label: 'Tekshirilmoqda', tone: StatusTone.info, icon: Icons.hourglass_top_rounded),
    };
    final isMath = a.subject == 'math';
    final color = isMath ? context.colors.primary : Palette.success;
    return SectionCard(
      onTap: () => context.push('/student/tasks/${a.id}'),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
            child: Icon(isMath ? Icons.calculate_rounded : Icons.translate_rounded, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.title, style: context.text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  '${a.groupName} · ${formatDueUz(a.dueAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                status,
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: context.colors.onSurfaceVariant),
        ],
      ),
    );
  }
}
