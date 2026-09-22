import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../assignments/data/assignment_models.dart' show scoreText;
import '../../assignments/data/assignments_repository.dart';
import '../../auth/application/auth_controller.dart';
import '../../groups/data/group_models.dart';
import '../../groups/data/groups_repository.dart';
import '../groups/create_group_sheet.dart';
import 'dashboard_models.dart';

const _weekdays = ['Dushanba', 'Seshanba', 'Chorshanba', 'Payshanba', 'Juma', 'Shanba', 'Yakshanba'];
const _weekdaysShort = ['Du', 'Se', 'Ch', 'Pa', 'Ju', 'Sh', 'Ya'];

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
    return Scaffold(
      body: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: RefreshIndicator(
              onRefresh: refresh,
              edgeOffset: topInset,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _HeroHeader(stats: d?.stats)),
                  if (groupList == null || d == null)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: (groups.hasError || dash.hasError)
                          ? ErrorRetry(error: (groups.error ?? dash.error)!, onRetry: refresh)
                          : const Center(child: CircularProgressIndicator()),
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
                          _QuickActions(stats: d.stats, groups: groupList),
                          if (ref.watch(planUsageProvider).value case final plan?
                              when plan.isExpired || plan.endsSoon) ...[
                            const SizedBox(height: 14),
                            _AlertCard(
                              icon: Icons.workspace_premium_rounded,
                              tone: plan.isExpired ? StatusTone.danger : StatusTone.warning,
                              title: plan.isExpired
                                  ? 'Tarif muddati tugagan'
                                  : "${plan.isTrial ? 'Sinov davri' : 'Tarif'} tugashiga ${plan.daysLeft} kun qoldi",
                              subtitle: plan.isExpired
                                  ? "Yangi o'quvchi qabul qilish va vazifa berish to'xtatilgan. Tarifni faollashtiring"
                                  : 'Uzilishsiz ishlash uchun tarif tanlang',
                              onTap: () => context.push('/teacher/plans'),
                            ),
                          ],
                          ..._alerts(context, d.stats, groupList),
                          const SizedBox(height: 22),
                          _WeeklyCard(d: d),
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
    );
  }

  List<Widget> _alerts(BuildContext context, DashboardStats s, List<TeacherGroup> groups) {
    final pendingGroup = groups.where((g) => g.membersPending > 0).firstOrNull;
    return [
      if (s.pendingRequests > 0 && pendingGroup != null) ...[
        const SizedBox(height: 14),
        _AlertCard(
          icon: Icons.person_add_alt_1_rounded,
          tone: StatusTone.warning,
          title: "${s.pendingRequests} ta o'quvchi qo'shilmoqchi",
          subtitle: "Tanisangiz qabul qiling — tasdiqlamaguningizcha guruhga kirmaydi",
          onTap: () => context.push('/teacher/groups/${pendingGroup.id}'),
        ),
      ],
      if (s.drafts > 0) ...[
        const SizedBox(height: 10),
        _AlertCard(
          icon: Icons.rate_review_rounded,
          tone: StatusTone.info,
          title: '${s.drafts} ta vazifa tasdiqlashingizni kutmoqda',
          subtitle: "AI tayyorladi — ko'rib chiqib, o'quvchilarga yuboring",
          onTap: () => context.go('/teacher/groups'),
        ),
      ],
    ];
  }
}

// ---------------------------------------------------------------- Hero

class _HeroHeader extends ConsumerWidget {
  const _HeroHeader({this.stats});

  final DashboardStats? stats;

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 11) return 'Xayrli tong';
    if (h < 17) return 'Assalomu alaykum';
    return 'Xayrli kech';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider);
    final primary = context.colors.primary;
    final now = DateTime.now();
    final s = stats;
    return Container(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 16, 20, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primary, Color.lerp(primary, Palette.info, 0.55)!],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_weekdays[now.weekday - 1]}, ${now.day}-${uzMonths[now.month - 1]}',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13.5),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_greeting()}, ${me?.firstName ?? ''}!',
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => context.go('/teacher/profile'),
                child: Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    me?.initials ?? '',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _HeroStat(value: s?.students, label: "O'quvchilar", icon: Icons.people_alt_rounded),
              const SizedBox(width: 10),
              _HeroStat(value: s?.openAssignments, label: 'Faol vazifa', icon: Icons.assignment_rounded),
              const SizedBox(width: 10),
              _HeroStat(
                value: s?.toReview,
                label: 'Tekshirish',
                icon: Icons.rate_review_rounded,
                highlight: (s?.toReview ?? 0) > 0,
                onTap: () => context.push('/teacher/review'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.value, required this.label, required this.icon, this.highlight = false, this.onTap});

  final int? value;
  final String label;
  final IconData icon;
  final bool highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: highlight ? Colors.white : Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(Radii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: highlight ? Palette.warning : Colors.white.withValues(alpha: 0.9)),
                const SizedBox(height: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    value?.toString() ?? '—',
                    key: ValueKey(value),
                    style: TextStyle(
                      color: highlight ? Palette.slate900 : Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: highlight ? Palette.slate700 : Colors.white.withValues(alpha: 0.85),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
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

// ---------------------------------------------------------------- Tezkor amallar

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.stats, required this.groups});

  final DashboardStats stats;
  final List<TeacherGroup> groups;

  Future<void> _newAssignment(BuildContext context) async {
    if (groups.length == 1) {
      context.push('/teacher/groups/${groups.first.id}/assignments/new');
      return;
    }
    final id = await showModalBottomSheet<String>(
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

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ActionTile(
          icon: Icons.add_task_rounded,
          label: 'Vazifa\nberish',
          color: context.colors.primary,
          filled: true,
          onTap: () => _newAssignment(context),
        ),
        const SizedBox(width: 10),
        _ActionTile(
          icon: Icons.fact_check_rounded,
          label: 'Ishlarni\ntekshirish',
          color: Palette.warning,
          badge: stats.toReview,
          onTap: () => context.push('/teacher/review'),
        ),
        const SizedBox(width: 10),
        _ActionTile(
          icon: Icons.groups_rounded,
          label: 'Guruh-\nlarim',
          color: Palette.success,
          onTap: () => context.go('/teacher/groups'),
        ),
        const SizedBox(width: 10),
        _ActionTile(
          icon: Icons.auto_awesome_rounded,
          label: 'AI\nyordamchi',
          color: const Color(0xFF7C3AED),
          onTap: () => context.go('/teacher/ai'),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.filled = false,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool filled;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: filled ? color : context.colors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.lg),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Container(
            height: 100,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.lg),
              border: filled ? null : Border.all(color: context.colors.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: filled ? Colors.white.withValues(alpha: 0.2) : color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(icon, size: 20, color: filled ? Colors.white : color),
                    ),
                    const Spacer(),
                    if (badge > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: context.appColors.danger,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          '$badge',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    maxLines: 2,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      color: filled ? Colors.white : context.colors.onSurface,
                    ),
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

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.icon, required this.tone, required this.title, required this.subtitle, this.onTap});

  final IconData icon;
  final StatusTone tone;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final (fg, bg) = switch (tone) {
      StatusTone.warning => (c.warning, c.warningContainer),
      StatusTone.success => (c.success, c.successContainer),
      StatusTone.danger => (c.danger, c.dangerContainer),
      _ => (c.info, c.infoContainer),
    };
    return Material(
      color: bg.withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(Radii.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: fg),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.text.titleMedium?.copyWith(fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: fg),
            ],
          ),
        ),
      ),
    );
  }
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

// ---------------------------------------------------------------- Haftalik natija + faollik grafigi

class _WeeklyCard extends StatelessWidget {
  const _WeeklyCard({required this.d});

  final TeacherDashboard d;

  @override
  Widget build(BuildContext context) {
    final avg = d.stats.avgPercentWeek;
    final c = context.appColors;
    final avgColor = avg == null
        ? context.colors.onSurfaceVariant
        : avg >= 86
        ? c.success
        : avg >= 71
        ? c.info
        : avg >= 51
        ? c.warning
        : c.danger;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Shu hafta', style: context.text.titleMedium),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        avg == null ? '—' : '${avg.round()}%',
                        style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: avgColor, height: 1),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "o'rtacha natija",
                        style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${d.stats.gradedThisWeek}',
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: context.colors.onSurface,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ish baholandi',
                        style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              "Topshirilgan ishlar, oxirgi 7 kun",
              style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            _ActivityChart(days: d.activity),
          ],
        ),
      ),
    );
  }
}

/// Bitta qator ma'lumot: bir xil rang, legenda yo'q. Ustun bosilsa qiymati ko'rsatiladi,
/// bugungi ustun doim qiymati bilan (tanlab yorliqlash).
class _ActivityChart extends StatefulWidget {
  const _ActivityChart({required this.days});

  final List<ActivityDay> days;

  @override
  State<_ActivityChart> createState() => _ActivityChartState();
}

class _ActivityChartState extends State<_ActivityChart> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final days = widget.days;
    final maxCount = days.fold<int>(0, (m, d) => d.count > m ? d.count : m);
    final primary = context.colors.primary;
    const chartHeight = 84.0;
    final today = days.isEmpty ? -1 : days.length - 1;
    final shown = _selected ?? today;

    return SizedBox(
      height: chartHeight + 44,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (i, d) in days.indexed)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque, // butun ustun balandligi bosiladi (belgidan kattaroq)
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selected = _selected == i ? null : i);
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 150),
                      opacity: i == shown ? 1 : 0,
                      child: Text(
                        '${d.count}',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.colors.onSurface),
                      ),
                    ),
                    const SizedBox(height: 4),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: maxCount == 0 ? 0 : d.count / maxCount),
                      duration: Duration(milliseconds: 500 + i * 60),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, _) => Container(
                        width: 18,
                        // Qiymat 0 bo'lsa ham 3px iz qoladi: kun borligi ko'rinadi
                        height: 3 + v * (chartHeight - 3),
                        decoration: BoxDecoration(
                          color: i == shown ? primary : primary.withValues(alpha: 0.35),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _weekdaysShort[d.day.weekday - 1],
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: i == today ? FontWeight.w800 : FontWeight.w500,
                        color: i == today ? context.colors.onSurface : context.colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
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
                'graded' => StatusChip(
                  label: '${scoreText(r.finalScore ?? 0)} / ${r.gradingScale}',
                  tone: StatusTone.success,
                  icon: Icons.check_rounded,
                ),
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

// ---------------------------------------------------------------- Guruhlar

class _GroupsStrip extends StatelessWidget {
  const _GroupsStrip({required this.groups});

  final List<TeacherGroup> groups;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 124,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: groups.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final g = groups[i];
          final isMath = g.subject == 'math';
          final color = isMath ? context.colors.primary : Palette.success;
          return SizedBox(
            width: 200,
            child: SectionCard(
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
            ),
          );
        },
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
                  : OutlinedButton(
                      onPressed: () => context.push('/teacher/plans'),
                      child: const Text('Tariflar'),
                    ),
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
