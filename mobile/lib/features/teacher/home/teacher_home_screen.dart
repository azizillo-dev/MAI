import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/motion.dart';
import '../../assignments/data/assignment_models.dart' show scoreText;
import '../../assignments/data/assignments_repository.dart';
import '../../extras/report_sheet.dart';
import '../../groups/data/group_models.dart';
import '../../groups/data/groups_repository.dart';
import '../groups/create_group_sheet.dart';
import 'analytics_widgets.dart';
import 'dashboard_models.dart';
import 'teacher_home_bento.dart';

/// O'qituvchi dashboard'i ("Bugun"): nima qilish kerakligi eng tepada, keyin holat va tahlil.
class TeacherHomeScreen extends ConsumerStatefulWidget {
  const TeacherHomeScreen({super.key});

  @override
  ConsumerState<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

class _TeacherHomeScreenState extends ConsumerState<TeacherHomeScreen> {
  /// Hero blok o'tib ketgach status bar ostiga fon chiqadi (matn soat ustiga tushmasin)
  final _scrolled = ValueNotifier(false);

  @override
  void dispose() {
    _scrolled.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth == 0) _scrolled.value = n.metrics.pixels > 150;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(teacherGroupsProvider);
    final dash = ref.watch(teacherDashboardProvider);

    Future<void> refresh() async {
      ref.invalidate(teacherGroupsProvider);
      ref.invalidate(teacherDashboardProvider);
      ref.invalidate(planUsageProvider);
      ref.invalidate(reviewQueueProvider);
      await ref.read(teacherDashboardProvider.future);
    }

    final groupList = groups.value;
    final d = dash.value;

    final topInset = MediaQuery.paddingOf(context).top;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: Stack(
          children: [
            const Positioned(top: 0, left: 0, right: 0, child: BentoBackdrop()),
            NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: RefreshIndicator(
                onRefresh: refresh,
                edgeOffset: topInset,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    const SliverToBoxAdapter(child: BentoHeader()),
                    if (groupList == null || d == null)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: (groups.hasError || dash.hasError)
                            ? ErrorRetry(error: (groups.error ?? dash.error)!, onRetry: refresh)
                            : const SkeletonList(count: 4),
                      )
                    else if (groupList.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: EmptyState(
                            icon: Icons.groups_rounded,
                            title: 'Birinchi guruhingizni yarating',
                            message: "Guruh yaratilgach, o'quvchilar kod va parol yoki QR orqali qo'shiladi. Har birini siz tasdiqlaysiz.",
                            actionLabel: 'Guruh yaratish',
                            actionIcon: Icons.add_rounded,
                            onAction: () => showCreateGroupSheet(context, ref),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: Insets.screen.copyWith(top: 20, bottom: 32),
                        sliver: SliverList.list(
                          children: [
                            FadeSlideIn(
                              child: FocusCard(d: d, onNewAssignment: () => _newAssignment(context, groupList)),
                            ),
                            if (ref.watch(planUsageProvider).value case final plan?
                                when plan.isExpired || plan.endsSoon) ...[
                              const SizedBox(height: 10),
                              BentoNotice(
                                icon: Icons.workspace_premium_rounded,
                                tone: plan.isExpired ? StatusTone.danger : StatusTone.warning,
                                text: plan.isExpired
                                    ? "Tarif muddati tugagan — yangi vazifa va o'quvchi qabul qilish to'xtagan"
                                    : "${plan.isTrial ? 'Sinov davri' : 'Tarif'} tugashiga ${plan.daysLeft} kun qoldi",
                                onTap: () => context.push('/teacher/plans'),
                              ),
                            ],
                            ..._notices(context, d.stats, groupList),
                            const SizedBox(height: 22),
                            FadeSlideIn(
                              index: 1,
                              child: BentoActions(
                                actions: [
                                  BentoAction(
                                    Icons.add_task_rounded,
                                    'Yangi vazifa',
                                    context.colors.primary,
                                    () => _newAssignment(context, groupList),
                                  ),
                                  BentoAction(
                                    Icons.fact_check_rounded,
                                    'Tekshirish',
                                    Palette.warning,
                                    () => context.push('/teacher/review'),
                                    badge: d.stats.toReview,
                                  ),
                                  BentoAction(
                                    Icons.groups_rounded,
                                    'Guruhlar',
                                    Palette.success,
                                    () => context.go('/teacher/groups'),
                                  ),
                                  BentoAction(
                                    Icons.summarize_rounded,
                                    'Hisobot',
                                    const Color(0xFF7C3AED),
                                    () => showReportSheet(context, groupList),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 22),
                            FadeSlideIn(index: 2, child: BentoStats(d: d)),
                            if (d.analytics.groups.isNotEmpty) ...[
                              const SizedBox(height: 26),
                              const _Title('Guruhlar tahlili'),
                              GroupAnalyticsCarousel(groups: d.analytics.groups),
                            ],
                            if (d.analytics.totalGraded > 0) ...[
                              const SizedBox(height: 16),
                              GradeDistributionCard(analytics: d.analytics),
                            ],
                            if (d.upcoming.isNotEmpty) ...[
                              const SizedBox(height: 26),
                              const _Title('Yaqin muddatlar'),
                              _UpcomingCard(items: d.upcoming),
                            ],
                            if (d.recent.isNotEmpty) ...[
                              const SizedBox(height: 26),
                              _Title(
                                'Oxirgi ishlar',
                                action: d.stats.toReview > 0 ? ('Tekshirish', '/teacher/review') : null,
                              ),
                              _RecentCard(items: d.recent),
                            ],
                            const SizedBox(height: 26),
                            _Title('Guruhlarim', action: ('Hammasi', '/teacher/groups')),
                            _GroupsStrip(groups: groupList),
                            const SizedBox(height: 26),
                            if (ref.watch(planUsageProvider).value case final plan?) PlanCard(plan: plan),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: topInset,
              child: IgnorePointer(
                child: ValueListenableBuilder<bool>(
                  valueListenable: _scrolled,
                  builder: (context, scrolled, _) => AnimatedOpacity(
                    opacity: scrolled ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _notices(BuildContext context, DashboardStats s, List<TeacherGroup> groups) {
    final pendingGroup = groups.where((g) => g.membersPending > 0).firstOrNull;
    return [
      if (s.pendingRequests > 0 && pendingGroup != null) ...[
        const SizedBox(height: 10),
        BentoNotice(
          icon: Icons.person_add_alt_1_rounded,
          tone: StatusTone.warning,
          text: "${s.pendingRequests} ta o'quvchi guruhga qo'shilmoqchi",
          onTap: () => context.push('/teacher/groups/${pendingGroup.id}'),
        ),
      ],
      // Fokus kartada tekshirish ko'rsatilgan bo'lsa, tayyor vazifalar shu yerda
      if (s.drafts > 0 && s.toReview > 0) ...[
        const SizedBox(height: 10),
        BentoNotice(
          icon: Icons.auto_awesome_rounded,
          tone: StatusTone.info,
          text: '${s.drafts} ta vazifa tasdiqlashingizni kutmoqda',
          onTap: () => context.go('/teacher/groups'),
        ),
      ],
    ];
  }
}

/// Vazifa berish: guruh bitta bo'lsa — darhol, bir nechta bo'lsa — qaysi guruhga ekanini so'raydi
Future<void> _newAssignment(BuildContext context, List<TeacherGroup> groups) async {
  if (groups.length == 1) {
    context.push('/teacher/groups/${groups.first.id}/assignments/new');
    return;
  }
  final id = await showModalBottomSheet<String>(
    useRootNavigator: true,
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Qaysi guruhga?', style: context.text.titleLarge),
          ),
          for (final g in groups)
            ListTile(
              leading: const Icon(Icons.groups_rounded),
              title: Text(g.name),
              subtitle: Text("${subjectLabel(g.subject)} · ${g.membersActive} o'quvchi"),
              onTap: () => Navigator.pop(context, g.id),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (id != null && context.mounted) context.push('/teacher/groups/$id/assignments/new');
}

class _Title extends StatelessWidget {
  const _Title(this.text, {this.action});

  final String text;
  final (String, String)? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Expanded(child: Text(text, style: context.text.titleLarge)),
        if (action case (final label, final route))
          TextButton(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: () => route.startsWith('/teacher/groups') ? context.go(route) : context.push(route),
            child: Text(label),
          ),
      ],
    ),
  );
}

// ---------------------------------------------------------------- Yaqin muddatlar

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({required this.items});

  final List<UpcomingItem> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          for (final (i, u) in items.indexed) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            InkWell(
              onTap: () => context.push('/teacher/assignments/${u.assignmentId}'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            u.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.titleMedium,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _TimeLeft(due: u.dueAt),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${u.groupName} · ${formatDueUz(u.dueAt)}',
                      style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(100),
                            child: LinearProgressIndicator(
                              value: u.members == 0 ? 0 : u.submitted / u.members,
                              minHeight: 7,
                              backgroundColor: context.colors.surfaceContainer,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${u.submitted}/${u.members} topshirdi',
                          style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TimeLeft extends StatelessWidget {
  const _TimeLeft({required this.due});

  final DateTime due;

  @override
  Widget build(BuildContext context) {
    final soon = due.difference(DateTime.now()).inHours < 24;
    return StatusChip(
      label: timeLeftUz(due),
      tone: soon ? StatusTone.warning : StatusTone.neutral,
      icon: Icons.schedule_rounded,
    );
  }
}

// ---------------------------------------------------------------- Oxirgi ishlar

class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.items});

  final List<RecentWork> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          for (final (i, r) in items.indexed) ...[
            if (i > 0) const Divider(height: 1, indent: 72),
            ListTile(
              onTap: () => context.push('/teacher/submissions/${r.submissionId}'),
              leading: Avatar(
                initials: r.studentName.split(' ').where((p) => p.isNotEmpty).map((p) => p[0]).take(2).join(),
              ),
              title: Text(r.studentName, style: context.text.titleMedium),
              subtitle: Text(r.assignmentTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: switch (r.status) {
                'graded' => _ScoreChip(score: r.finalScore ?? 0, scale: int.tryParse(r.gradingScale) ?? 5),
                'failed' => const StatusChip(
                  label: "Qo'lda baholang",
                  tone: StatusTone.danger,
                  icon: Icons.error_outline_rounded,
                ),
                _ => const StatusChip(label: 'Tekshiring', tone: StatusTone.warning, icon: Icons.visibility_rounded),
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Baho belgisi: a'lo — yashil, yaxshi — ko'k, qoniqarli — sariq, past — qizil
class _ScoreChip extends StatelessWidget {
  const _ScoreChip({required this.score, required this.scale});

  final double score;
  final int scale;

  @override
  Widget build(BuildContext context) {
    final ratio = scale == 0 ? 0.0 : score / scale;
    final tone = ratio >= 0.86
        ? StatusTone.success
        : ratio >= 0.71
        ? StatusTone.info
        : ratio >= 0.51
        ? StatusTone.warning
        : StatusTone.danger;
    return StatusChip(label: '${scoreText(score)} / $scale', tone: tone);
  }
}

// ---------------------------------------------------------------- Guruhlar

class _GroupsStrip extends StatelessWidget {
  const _GroupsStrip({required this.groups});

  final List<TeacherGroup> groups;

  @override
  Widget build(BuildContext context) {
    // 1–2 guruh sahifaga to'liq sig'adi (surish shart emas, chetga yopishmaydi);
    // 3+ guruhda gorizontal surish, ro'yxat ekran chetigacha yoyiladi
    final fits = groups.length <= 2;
    // Har bir karta — alohida vidjet: temani o'z kontekstidan o'qiydi, tema jonli almashganda
    // (tizimda qorong'i rejim yoqilsa) darhol yangilanadi
    if (fits) {
      return SizedBox(
        height: 124,
        child: Row(
          children: [
            for (final (i, g) in groups.indexed) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: _GroupTile(g: g)),
            ],
          ],
        ),
      );
    }
    return SizedBox(
      height: 124,
      child: FullBleed(
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: Insets.screen,
          itemCount: groups.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (_, i) => SizedBox(width: 200, child: _GroupTile(g: groups[i])),
        ),
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.g});

  final TeacherGroup g;

  @override
  Widget build(BuildContext context) {
    final isMath = g.subject == 'math';
    final color = isMath ? context.colors.primary : Palette.success;
    return SectionCard(
      padding: const EdgeInsets.all(14),
      onTap: () => context.push('/teacher/groups/${g.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(isMath ? Icons.calculate_rounded : Icons.translate_rounded, color: color, size: 20),
              ),
              const Spacer(),
              Icon(
                g.joinEnabled ? Icons.lock_open_rounded : Icons.lock_rounded,
                size: 18,
                color: g.joinEnabled ? context.appColors.success : context.colors.onSurfaceVariant,
              ),
            ],
          ),
          const Spacer(),
          Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleMedium),
          const SizedBox(height: 2),
          Text(
            g.membersPending > 0
                ? "${g.membersActive} o'quvchi · +${g.membersPending} kutmoqda"
                : "${g.membersActive} o'quvchi",
            style: context.text.bodySmall?.copyWith(
              color: g.membersPending > 0 ? context.appColors.warning : context.colors.onSurfaceVariant,
              fontWeight: g.membersPending > 0 ? FontWeight.w700 : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Tarif

/// Tarif limitlari: o'qituvchi qancha joy qolganini doim ko'rib turadi
class PlanCard extends StatelessWidget {
  const PlanCard({super.key, required this.plan, this.showManage = true});

  final PlanUsage plan;

  /// Tariflar sahifasining o'zida "Boshqarish" tugmasi kerak emas
  final bool showManage;

  @override
  Widget build(BuildContext context) {
    final (chip, tone) = plan.isExpired
        ? ('Muddati tugagan', StatusTone.danger)
        : plan.isTrial
        ? ('Sinov: ${plan.daysLeft} kun', plan.endsSoon ? StatusTone.warning : StatusTone.info)
        : ('${plan.daysLeft} kun qoldi', plan.endsSoon ? StatusTone.warning : StatusTone.success);
    return SectionCard(
      onTap: showManage ? () => context.push('/teacher/plans') : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_rounded, color: Palette.gold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  plan.isTrial ? 'Sinov davri' : '${plan.planName} tarif',
                  style: context.text.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              StatusChip(label: chip, tone: tone),
            ],
          ),
          if (plan.endsAt case final end? when !plan.isExpired) ...[
            const SizedBox(height: 4),
            Text(
              '${formatDateUz(end.toLocal())} gacha',
              style: context.text.bodySmall?.copyWith(color: context.appColors.muted),
            ),
          ],
          const SizedBox(height: 16),
          _UsageBar(label: 'Guruhlar', used: plan.groupsUsed, max: plan.maxGroups),
          const SizedBox(height: 12),
          _UsageBar(label: "O'quvchilar", used: plan.studentsUsed, max: plan.maxStudents),
          if (plan.maxAssignmentsPerWeek != null) ...[
            const SizedBox(height: 12),
            Text(
              'Haftasiga ${plan.maxAssignmentsPerWeek} ta vazifa',
              style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          ],
          if (showManage) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: plan.isExpired || plan.isTrial || plan.endsSoon
                  ? FilledButton.icon(
                      onPressed: () => context.push('/teacher/plans'),
                      icon: const Icon(Icons.bolt_rounded),
                      label: Text(plan.isExpired ? 'Tarifni faollashtirish' : 'Tarif tanlash'),
                    )
                  : OutlinedButton(onPressed: () => context.push('/teacher/plans'), child: const Text('Tariflar')),
            ),
          ],
        ],
      ),
    );
  }
}

class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.label, required this.used, required this.max});

  final String label;
  final int used;
  final int max;

  @override
  Widget build(BuildContext context) {
    final ratio = max == 0 ? 0.0 : (used / max).clamp(0.0, 1.0);
    final color = ratio >= 1
        ? context.appColors.danger
        : ratio >= 0.8
        ? context.appColors.warning
        : context.colors.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: context.text.bodyMedium),
            const Spacer(),
            Text('$used / $max', style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 8,
            color: color,
            backgroundColor: context.colors.surfaceContainer,
          ),
        ),
      ],
    );
  }
}
