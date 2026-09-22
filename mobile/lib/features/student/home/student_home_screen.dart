import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../assignments/data/assignments_repository.dart';
import '../../assignments/presentation/student/student_tasks_screen.dart';
import '../../auth/application/auth_controller.dart';
import '../../gamification/data/gamification_models.dart';
import '../../profile/profile_screen.dart' show StatTile;
import '../../groups/data/group_models.dart';
import '../../groups/data/groups_repository.dart';

class StudentHomeScreen extends ConsumerWidget {
  const StudentHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider);
    final memberships = ref.watch(membershipsProvider);
    final list = memberships.value;

    Future<void> refresh() async {
      ref.invalidate(membershipsProvider);
      ref.invalidate(studentAssignmentsProvider);
      ref.invalidate(studentProgressProvider);
      await ref.read(membershipsProvider.future);
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              toolbarHeight: 72,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Salom 👋',
                    style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
                  ),
                  Text(me?.firstName ?? '', style: context.text.headlineSmall),
                ],
              ),
            ),
            if (list == null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: memberships.hasError
                    ? ErrorRetry(error: memberships.error!, onRetry: refresh)
                    : const Center(child: CircularProgressIndicator()),
              )
            else if (list.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: EmptyState(
                    icon: Icons.group_add_rounded,
                    title: "Hali guruhingiz yo'q",
                    message: "Ustozingizdan guruh kodi va parolini so'rang yoki QR kodni skanerlang.",
                    actionLabel: "Guruhga qo'shilish",
                    actionIcon: Icons.add_rounded,
                    onAction: () => context.push('/student/join'),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: Insets.screen.copyWith(bottom: 24),
                sliver: SliverList.list(
                  children: [
                    const _ProgressStrip(),
                    const SizedBox(height: 20),
                    ..._todo(context, ref),
                    Text('Guruhlarim', style: context.text.titleLarge),
                    const SizedBox(height: 12),
                    for (final m in list) ...[
                      _MembershipCard(membership: m),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      onPressed: () => context.push('/student/join'),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text("Yana guruhga qo'shilish"),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// XP, reyting, seriya, nishonlar — bosh sahifada doim ko'rinadi (Cambridge "Main" uslubi)
class _ProgressStrip extends ConsumerWidget {
  const _ProgressStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(studentProgressProvider).value;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.2,
      children: [
        StatTile(icon: Icons.star_rounded, color: Palette.warning, value: '${p?.xp ?? '—'}', label: 'XP ball'),
        StatTile(
          icon: Icons.leaderboard_rounded,
          color: Palette.success,
          value: p?.bestRank == null ? '—' : '#${p!.bestRank!.rank}',
          label: 'Reyting',
          onTap: () => context.go('/student/rating'),
        ),
        StatTile(
          icon: Icons.local_fire_department_rounded,
          color: Palette.danger,
          value: '${p?.currentStreak ?? '—'}',
          label: 'Seriya',
        ),
        StatTile(
          icon: Icons.military_tech_rounded,
          color: const Color(0xFF8B5CF6),
          value: p == null ? '—' : '${p.badgesEarned}/${p.badgesTotal}',
          label: 'Nishonlar',
          onTap: () => context.push('/badges'),
        ),
      ],
    );
  }
}

/// Eng yaqin muddatli topshirilmagan vazifalar (ko'pi bilan 3 ta)
List<Widget> _todo(BuildContext context, WidgetRef ref) {
  final list = ref.watch(studentAssignmentsProvider).value ?? const [];
  final todo = list.where((a) => a.submission == null && a.canSubmit).toList()
    ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
  if (todo.isEmpty) return const [];
  return [
    Row(
      children: [
        Expanded(child: Text('Topshirish kerak', style: context.text.titleLarge)),
        if (todo.length > 3) TextButton(onPressed: () => context.go('/student/tasks'), child: Text('Hammasi (${todo.length})')),
      ],
    ),
    const SizedBox(height: 10),
    for (final a in todo.take(3)) ...[StudentTaskCard(a: a), const SizedBox(height: 10)],
    const SizedBox(height: 14),
  ];
}

class _MembershipCard extends ConsumerWidget {
  const _MembershipCard({required this.membership});

  final Membership membership;

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: "So'rovni bekor qilasizmi?",
      message: "«${membership.groupName}» guruhiga qo'shilish so'rovi bekor qilinadi.",
      confirmLabel: 'Bekor qilish',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(groupsRepositoryProvider).leave(membership.groupId);
      ref.invalidate(membershipsProvider);
    } on ApiException catch (e) {
      if (context.mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = membership;
    final isMath = m.subject == 'math';
    final color = isMath ? context.colors.primary : Palette.success;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(15)),
                child: Icon(isMath ? Icons.calculate_rounded : Icons.translate_rounded, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.groupName, style: context.text.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      '${subjectLabel(m.subject)} · ${m.teacherName}',
                      style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (m.isPending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const StatusChip(
                  label: 'Ustoz tasdiqlashi kutilmoqda',
                  tone: StatusTone.warning,
                  icon: Icons.hourglass_top_rounded,
                ),
                const Spacer(),
                TextButton(onPressed: () => _cancel(context, ref), child: const Text('Bekor qilish')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
