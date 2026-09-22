import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_widgets.dart';
import '../assistant/assistant_controller.dart';
import '../auth/data/auth_models.dart' show formatPhone;
import '../gamification/presentation/badges_screen.dart' show showBadgeSheet;
import '../gamification/presentation/hex_badge.dart';
import 'student_card.dart';

/// O'quvchi profili: ustoz (to'liq, ishlar ro'yxati bilan) va guruhdoshlar (XP, jetonlar, reyting) uchun
class StudentProfileScreen extends ConsumerWidget {
  const StudentProfileScreen({super.key, required this.studentId});

  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = ref.watch(studentCardProvider(studentId));
    Future<void> refresh() => ref.refresh(studentCardProvider(studentId).future);

    return Scaffold(
      body: card.when(
        loading: () => Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator())),
        error: (e, _) => Scaffold(appBar: AppBar(), body: ErrorRetry(error: e, onRetry: refresh)),
        data: (c) => RefreshIndicator(
          onRefresh: refresh,
          edgeOffset: MediaQuery.paddingOf(context).top,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _Hero(c: c)),
              SliverPadding(
                padding: Insets.screen.copyWith(top: 18, bottom: 32),
                sliver: SliverList.list(
                  children: [
                    _StatsRow(c: c),
                    if (c.progress.ranks.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _Ranks(c: c),
                    ],
                    const SizedBox(height: 22),
                    _Badges(c: c),
                    if (c.teacherView case final tv?) ...[
                      const SizedBox(height: 22),
                      _AskAi(name: c.fullName),
                      const SizedBox(height: 22),
                      _Summary(tv: tv),
                      if (tv.missing.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        _SectionTitle('Topshirilmagan', count: tv.missing.length, color: context.appColors.danger),
                        _TaskList(items: tv.missing, overdue: true),
                      ],
                      if (tv.open.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        _SectionTitle('Kutilayotgan', count: tv.open.length),
                        _TaskList(items: tv.open, overdue: false),
                      ],
                      const SizedBox(height: 22),
                      _SectionTitle('Topshirgan ishlari', count: tv.submissions.length),
                      if (tv.submissions.isEmpty)
                        const SectionCard(child: Text("Hali birorta ham ish topshirmagan"))
                      else
                        _SubmissionList(items: tv.submissions),
                      const SizedBox(height: 22),
                      _Contact(c: c, tv: tv),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Sarlavha

class _Hero extends StatelessWidget {
  const _Hero({required this.c});

  final StudentCard c;

  @override
  Widget build(BuildContext context) {
    final p = c.progress;
    final primary = context.colors.primary;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color.lerp(primary, const Color(0xFF8B5CF6), 0.5)!, primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 20, 22),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  ),
                  const Spacer(),
                ],
              ),
              Avatar(
                initials: c.initials,
                imageUrl: c.avatarUrl,
                size: 92,
                ring: Colors.white,
                color: Colors.white.withValues(alpha: 0.25),
              ),
              const SizedBox(height: 12),
              Text(
                c.isSelf ? '${c.fullName} (siz)' : c.fullName,
                textAlign: TextAlign.center,
                style: context.text.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                [for (final g in c.groups) g.$2].join(' · '),
                textAlign: TextAlign.center,
                style: context.text.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            '${p.level}-daraja · ${p.levelName}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${p.levelXp} / ${p.levelSpan} XP',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(100),
                      child: LinearProgressIndicator(
                        value: p.levelProgress,
                        minHeight: 8,
                        color: Palette.gold,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.c});

  final StudentCard c;

  @override
  Widget build(BuildContext context) {
    final p = c.progress;
    return Row(
      children: [
        _Stat(icon: Icons.bolt_rounded, color: Palette.gold, value: '${p.xp}', label: 'XP'),
        const SizedBox(width: 10),
        _Stat(
          icon: Icons.insights_rounded,
          color: context.appColors.success,
          value: p.works == 0 ? '—' : '${p.avgPercent}%',
          label: "O'rtacha",
        ),
        const SizedBox(width: 10),
        _Stat(icon: Icons.task_alt_rounded, color: context.colors.primary, value: '${p.works}', label: 'Baholangan'),
        const SizedBox(width: 10),
        _Stat(
          icon: Icons.local_fire_department_rounded,
          color: Palette.danger,
          value: '${p.currentStreak}',
          label: 'Seriya',
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.color, required this.value, required this.label});

  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            color: context.colors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.appColors.border),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 6),
              FittedBox(
                child: Text(value, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelSmall?.copyWith(color: context.appColors.muted),
              ),
            ],
          ),
        ),
      );
}

class _Ranks extends StatelessWidget {
  const _Ranks({required this.c});

  final StudentCard c;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final r in c.progress.ranks)
            ActionChip(
              avatar: Icon(
                Icons.emoji_events_rounded,
                size: 18,
                color: r.rank == 1 ? Palette.gold : r.rank <= 3 ? Palette.silver : context.colors.primary,
              ),
              label: Text("${r.groupName}: ${r.rank}-o'rin / ${r.of} (shu oy)"),
              onPressed: () => context.push('/leaderboard?group=${r.groupId}'),
            ),
        ],
      );
}

// ---------------------------------------------------------------- Jetonlar

class _Badges extends StatelessWidget {
  const _Badges({required this.c});

  final StudentCard c;

  @override
  Widget build(BuildContext context) {
    final p = c.progress;
    final cells = <Widget>[
      for (final m in p.medals.reversed)
        _BadgeCell(
          badge: HexBadge(
            tier: m.tier,
            icon: Icons.emoji_events_rounded,
            label: switch (m.tier) { 'gold' => '1', 'silver' => '2', _ => '3' },
            size: 64,
          ),
          name: m.name,
        ),
      for (final b in p.badges)
        _BadgeCell(
          badge: HexBadge(tier: b.tier, icon: badgeIcons[b.icon] ?? Icons.star_rounded, size: 64),
          name: b.name,
          onTap: () => showBadgeSheet(context, b),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('Jetonlar', count: p.badgesEarned + p.medals.length),
        SectionCard(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: cells.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Icon(Icons.hexagon_outlined, color: context.appColors.muted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "Hali jeton yo'q. Vazifalarni o'z vaqtida va yaxshi bajarib jeton yig'iladi",
                          style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                )
              : GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 0.72,
                  children: cells,
                ),
        ),
      ],
    );
  }
}

class _BadgeCell extends StatelessWidget {
  const _BadgeCell({required this.badge, required this.name, this.onTap});

  final Widget badge;
  final String name;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          children: [
            badge,
            const SizedBox(height: 6),
            Text(
              name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
}

// ---------------------------------------------------------------- Faqat ustoz uchun

class _AskAi extends ConsumerWidget {
  const _AskAi({required this.name});

  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SectionCard(
        onTap: () {
          ref.read(assistantChatProvider.notifier).send("$name qanday o'qiyapti? Batafsil tahlil qilib ber");
          context.go('/teacher/ai');
        },
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF8B5CF6)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AI tahlili', style: context.text.titleMedium),
                  Text(
                    "O'sish, pasayish va tipik xatolar bo'yicha xulosa",
                    style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.appColors.muted),
          ],
        ),
      );
}

class _Summary extends StatelessWidget {
  const _Summary({required this.tv});

  final TeacherView tv;

  @override
  Widget build(BuildContext context) {
    final avg = tv.avgPercent;
    final avgColor = avg == null
        ? context.appColors.muted
        : avg >= 80
        ? context.appColors.success
        : avg >= 60
        ? context.appColors.warning
        : context.appColors.danger;
    Widget cell(String value, String label, Color color) => Expanded(
          child: Column(
            children: [
              Text(value, style: context.text.titleLarge?.copyWith(color: color, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(label, style: context.text.labelSmall?.copyWith(color: context.appColors.muted)),
            ],
          ),
        );
    final rate = tv.assigned == 0 ? null : (tv.submitted / tv.assigned).clamp(0.0, 1.0);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Vazifalar bo\'yicha', style: context.text.titleMedium),
          const SizedBox(height: 14),
          Row(
            children: [
              cell('${tv.assigned}', 'Berilgan', context.colors.onSurface),
              cell('${tv.submitted}', 'Topshirgan', context.appColors.success),
              cell('${tv.missingCount}', 'Qoldirgan', tv.missingCount > 0 ? context.appColors.danger : context.colors.onSurface),
              cell(avg == null ? '—' : '${avg.round()}%', "O'rtacha", avgColor),
            ],
          ),
          if (rate != null) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(100),
              child: LinearProgressIndicator(
                value: rate,
                minHeight: 8,
                color: context.appColors.success,
                backgroundColor: context.colors.surfaceContainer,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              [
                'Topshirish: ${(rate * 100).round()}%',
                if (tv.late > 0) 'kechikkan: ${tv.late}',
                if (tv.waitingReview > 0) 'tekshiruv kutmoqda: ${tv.waitingReview}',
              ].join(' · '),
              style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _SubmissionList extends StatelessWidget {
  const _SubmissionList({required this.items});

  final List<CardSubmission> items;

  @override
  Widget build(BuildContext context) => SectionCard(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            for (final (i, s) in items.indexed) ...[
              if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                onTap: () => context.push('/teacher/submissions/${s.id}'),
                title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${s.groupName} · ${formatDateUz(s.submittedAt)}${s.isLate ? ' · kechikkan' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: _ScorePill(s: s),
              ),
            ],
          ],
        ),
      );
}

class _ScorePill extends StatelessWidget {
  const _ScorePill({required this.s});

  final CardSubmission s;

  @override
  Widget build(BuildContext context) {
    return switch (s.status) {
      'graded' => () {
          final p = s.percent ?? 0;
          final tone = p >= 80 ? StatusTone.success : p >= 60 ? StatusTone.warning : StatusTone.danger;
          final score = s.finalScore == null
              ? '—'
              : s.finalScore! % 1 == 0
              ? s.finalScore!.toInt().toString()
              : s.finalScore!.toStringAsFixed(1);
          return StatusChip(label: '$score / ${s.gradingScale}', tone: tone);
        }(),
      'grading' => const StatusChip(label: 'AI tekshirmoqda', tone: StatusTone.info),
      _ => const StatusChip(label: 'Tekshiring', tone: StatusTone.warning),
    };
  }
}

class _TaskList extends StatelessWidget {
  const _TaskList({required this.items, required this.overdue});

  final List<CardTask> items;
  final bool overdue;

  @override
  Widget build(BuildContext context) => SectionCard(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            for (final (i, t) in items.indexed) ...[
              if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                onTap: () => context.push('/teacher/assignments/${t.assignmentId}'),
                leading: Icon(
                  overdue ? Icons.error_outline_rounded : Icons.schedule_rounded,
                  color: overdue ? context.appColors.danger : context.appColors.warning,
                ),
                title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${t.groupName} · ${overdue ? 'muddat o\'tgan' : 'muddat'}: ${formatDateUz(t.dueAt)}'),
              ),
            ],
          ],
        ),
      );
}

class _Contact extends StatelessWidget {
  const _Contact({required this.c, required this.tv});

  final StudentCard c;
  final TeacherView tv;

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 20, color: context.appColors.muted),
              const SizedBox(width: 12),
              Text(label, style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Ma'lumotlar", style: context.text.titleMedium),
          const SizedBox(height: 8),
          if (tv.phone case final phone?) row(Icons.phone_iphone_rounded, 'Telefon', formatPhone(phone)),
          if (tv.email case final email?) row(Icons.alternate_email_rounded, 'Email', email),
          if (tv.birthDate case final bd?) row(Icons.cake_rounded, "Tug'ilgan sana", formatDateUz(bd)),
          row(Icons.event_available_rounded, "Ro'yxatdan o'tgan", formatDateUz(c.joinedAt)),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.count, this.color});

  final String title;
  final int? count;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Text(title, style: context.text.titleLarge?.copyWith(color: color)),
            if (count != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (color ?? context.colors.primary).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(color: color ?? context.colors.primary, fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ),
            ],
          ],
        ),
      );
}
