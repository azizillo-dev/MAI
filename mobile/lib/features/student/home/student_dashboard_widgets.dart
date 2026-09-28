import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/trend_chart.dart';
import '../../assignments/data/assignment_models.dart';
import '../../auth/application/auth_controller.dart';
import '../../gamification/data/gamification_models.dart';
import '../../gamification/presentation/badges_screen.dart' show showGiftAwardSheet;
import '../../gamification/presentation/hex_badge.dart';

/// Daraja, XP va keyingi darajagacha qolgan yo'l — bosh sahifaning "yuragi"
class StudentHeroCard extends ConsumerWidget {
  const StudentHeroCard({super.key, required this.p});

  final StudentProgress? p;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider);
    final p = this.p;
    final primary = context.colors.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color.lerp(primary, const Color(0xFF8B5CF6), 0.45)!, primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Avatar(
                initials: me?.initials ?? '',
                imageUrl: me?.avatarUrl,
                size: 48,
                ring: Colors.white,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p == null ? 'Daraja' : '${p.level}-daraja',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w600)),
                    Text(p?.levelName ?? '—',
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => context.push('/badges'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.military_tech_rounded, color: Colors.white, size: 18),
                      const SizedBox(width: 4),
                      Text(p == null ? '—' : '${p.badgesEarned + p.gifts.length}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('${p?.levelXp ?? 0} / ${p?.levelSpan ?? 0} XP',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (p != null)
                Text('keyingi darajagacha ${math.max(0, p.levelSpan - p.levelXp)} XP',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(
              value: p?.levelProgress ?? 0,
              minHeight: 9,
              color: Palette.gold,
              backgroundColor: Colors.white.withValues(alpha: 0.22),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _HeroStat(icon: Icons.bolt_rounded, value: '${p?.xp ?? '—'}', label: 'XP'),
              _HeroStat(
                icon: Icons.leaderboard_rounded,
                value: p?.bestRank == null ? '—' : '#${p!.bestRank!.rank}',
                label: 'Reyting',
                onTap: () => context.go('/student/rating'),
              ),
              _HeroStat(icon: Icons.local_fire_department_rounded, value: '${p?.currentStreak ?? '—'}', label: 'Seriya'),
              _HeroStat(
                icon: Icons.insights_rounded,
                value: p == null || p.works == 0 ? '—' : '${p.avgPercent}%',
                label: "O'rtacha",
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.icon, required this.value, required this.label, this.onTap});

  final IconData icon;
  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Column(
            children: [
              Icon(icon, color: Colors.white.withValues(alpha: 0.9), size: 20),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
              Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11)),
            ],
          ),
        ),
      );
}

// ---------------------------------------------------------------- Haftalik maqsad va eng yaqin muddat

/// Toshkent vaqti bo'yicha shu haftaning dushanbasi
DateTime _weekStart(DateTime now) {
  final d = DateTime(now.year, now.month, now.day);
  return d.subtract(Duration(days: d.weekday - 1));
}

class WeeklyGoalCard extends StatelessWidget {
  const WeeklyGoalCard({super.key, required this.list});

  final List<StudentAssignment> list;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = _weekStart(now);
    final end = start.add(const Duration(days: 7));
    final week = list.where((a) => !a.dueAt.isBefore(start) && a.dueAt.isBefore(end)).toList();
    final done = week.where((a) => a.submission != null).length;
    final next = (list.where((a) => a.submission == null && a.dueAt.isAfter(now)).toList()
          ..sort((a, b) => a.dueAt.compareTo(b.dueAt)))
        .firstOrNull;
    final ratio = week.isEmpty ? 0.0 : done / week.length;
    final ringColor = ratio >= 1 ? context.appColors.success : context.colors.primary;

    return SectionCard(
      child: Row(
        children: [
          SizedBox(
            width: 76,
            height: 76,
            child: Stack(
              fit: StackFit.expand,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: ratio),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => CircularProgressIndicator(
                    value: week.isEmpty ? 0 : v,
                    strokeWidth: 8,
                    strokeCap: StrokeCap.round,
                    color: ringColor,
                    backgroundColor: context.colors.surfaceContainer,
                  ),
                ),
                Center(
                  child: Text(week.isEmpty ? '—' : '$done/${week.length}',
                      style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Haftalik maqsad', style: context.text.titleMedium),
                const SizedBox(height: 2),
                Text(
                  week.isEmpty
                      ? "Bu haftaga vazifa berilmagan"
                      : ratio >= 1
                      ? "Barakalla! Bu haftaning hammasi topshirildi 🎉"
                      : "Bu haftaning ${week.length - done} ta vazifasi qoldi",
                  style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                ),
                if (next != null) ...[
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () => context.push('/student/tasks/${next.id}'),
                    borderRadius: BorderRadius.circular(10),
                    child: Row(
                      children: [
                        Icon(Icons.timer_outlined, size: 18, color: context.appColors.warning),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(text: _left(next.dueAt.difference(now)),
                                  style: TextStyle(color: context.appColors.warning, fontWeight: FontWeight.w800)),
                              TextSpan(text: ' · ${next.title}'),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _left(Duration d) {
    if (d.inDays >= 1) return '${d.inDays} kun ${d.inHours % 24} soat';
    if (d.inHours >= 1) return '${d.inHours} soat ${d.inMinutes % 60} daqiqa';
    return '${math.max(1, d.inMinutes)} daqiqa';
  }
}

// ---------------------------------------------------------------- Natijalar trendi

class ResultsTrendCard extends StatelessWidget {
  const ResultsTrendCard({super.key, required this.list});

  final List<StudentAssignment> list;

  @override
  Widget build(BuildContext context) {
    final graded = list
        .where((a) => a.submission?.isFinal == true && a.submission?.finalScore != null)
        .toList()
      ..sort((a, b) => a.submission!.submittedAt.compareTo(b.submission!.submittedAt));
    if (graded.isEmpty) return const SizedBox.shrink();
    final last = graded.length > 10 ? graded.sublist(graded.length - 10) : graded;
    final percents = [for (final a in last) a.submission!.finalScore! / a.submission!.scaleMax * 100];
    final avg = percents.reduce((a, b) => a + b) / percents.length;
    final delta = percents.length >= 2 ? percents.last - percents.first : 0.0;
    final feedback = graded.last.submission!.feedbackStudent;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Natijalarim', style: context.text.titleMedium),
              const Spacer(),
              if (percents.length >= 2)
                StatusChip(
                  label: '${delta >= 0 ? '+' : ''}${delta.round()}%',
                  tone: delta >= 3 ? StatusTone.success : delta <= -3 ? StatusTone.danger : StatusTone.neutral,
                  icon: delta >= 3 ? Icons.trending_up_rounded : delta <= -3 ? Icons.trending_down_rounded : Icons.trending_flat_rounded,
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text("Oxirgi ${percents.length} ta ish · o'rtacha ${avg.round()}%",
              style: context.text.bodySmall?.copyWith(color: context.appColors.muted)),
          const SizedBox(height: 12),
          SizedBox(height: 64, width: double.infinity, child: TrendChart(values: percents)),
          if (feedback != null && feedback.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.colors.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.format_quote_rounded, color: context.colors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('So\'nggi izoh · ${graded.last.title}',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: context.text.labelMedium?.copyWith(color: context.colors.primary)),
                        const SizedBox(height: 2),
                        Text(feedback, maxLines: 3, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Ustoz sovg'asi

/// So'nggi 7 kunda ustoz sovg'a qilgan jeton — quvonchli xabar
class GiftBanner extends StatelessWidget {
  const GiftBanner({super.key, required this.p});

  final StudentProgress? p;

  @override
  Widget build(BuildContext context) {
    final recent = p?.gifts.where((g) => DateTime.now().difference(g.awardedAt).inDays < 7).toList() ?? const [];
    if (recent.isEmpty) return const SizedBox.shrink();
    final g = recent.reduce((a, b) => a.awardedAt.isAfter(b.awardedAt) ? a : b);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: SectionCard(
        onTap: () => showGiftAwardSheet(context, g),
        child: Row(
          children: [
            HexBadge(tier: g.tier, icon: badgeIcons[g.icon] ?? Icons.star_rounded, size: 52),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Sizga sovg'a! 🎁", style: context.text.titleSmall?.copyWith(color: const Color(0xFFEA580C))),
                  Text("${g.teacher ?? 'Ustozingiz'} sizga «${g.name}» jetonini sovg'a qildi",
                      style: context.text.bodySmall),
                  if (g.note case final n?)
                    Text('“$n”', maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
