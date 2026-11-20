import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../assignments/data/assignment_models.dart';
import '../../gamification/data/gamification_models.dart';
import '../../teacher/home/teacher_home_bento.dart';

/// O'quvchi bosh sahifasining bento qismi: chapda haftalik maqsad halqasi (asosiysi — kattaroq),
/// o'ngda eng yaqin muddat va nishonlar.
class StudentBento extends StatelessWidget {
  const StudentBento({super.key, required this.list, this.p});

  final List<StudentAssignment> list;
  final StudentProgress? p;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: bentoRowHeight(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 11, child: _WeeklyGoalTile(list: list)),
          const SizedBox(width: 12),
          Expanded(
            flex: 9,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _NextDueTile(list: list)),
                const SizedBox(height: 12),
                Expanded(child: _BadgesTile(p: p)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Toshkent vaqti bo'yicha shu haftaning dushanbasi (UTC+5)
DateTime _weekStart(DateTime now) {
  final t = now.toUtc().add(const Duration(hours: 5));
  final monday = DateTime.utc(t.year, t.month, t.day).subtract(Duration(days: t.weekday - 1));
  return monday.subtract(const Duration(hours: 5));
}

class _WeeklyGoalTile extends StatelessWidget {
  const _WeeklyGoalTile({required this.list});

  final List<StudentAssignment> list;

  @override
  Widget build(BuildContext context) {
    final start = _weekStart(DateTime.now());
    final end = start.add(const Duration(days: 7));
    final week = list.where((a) => !a.dueAt.isBefore(start) && a.dueAt.isBefore(end)).toList();
    final done = week.where((a) => a.submission != null).length;
    final ratio = week.isEmpty ? 0.0 : done / week.length;
    final c = context.appColors;
    final color = week.isEmpty ? c.warning : (ratio >= 1 ? c.success : context.colors.primary);
    final caption = week.isEmpty
        ? "Bu hafta vazifa yo'q"
        : ratio >= 1
        ? 'Hammasi topshirildi 🎉'
        : '${week.length - done} ta vazifa qoldi';
    return BentoTile(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      onTap: () => context.go('/student/tasks'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BentoLabel(icon: Icons.flag_rounded, label: 'Haftalik maqsad', color: context.colors.primary),
          const Spacer(),
          Center(
            child: SizedBox.square(
              dimension: 104,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: ratio),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: week.isEmpty ? 0 : v,
                      strokeWidth: 10,
                      strokeCap: StrokeCap.round,
                      color: color,
                      backgroundColor: color.withValues(alpha: 0.13),
                    ),
                    Center(
                      child: week.isEmpty
                          ? Icon(Icons.wb_sunny_rounded, size: 34, color: color)
                          : BentoNumber('$done/${week.length}', size: 26, color: color),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          Center(
            child: Text(
              caption,
              style: TextStyle(fontSize: 12.5, color: context.colors.onSurfaceVariant, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _NextDueTile extends StatelessWidget {
  const _NextDueTile({required this.list});

  final List<StudentAssignment> list;

  static String _left(Duration d) {
    if (d.inDays >= 1) return '${d.inDays} kun';
    if (d.inHours >= 1) return '${d.inHours} soat';
    return '${d.inMinutes.clamp(1, 59)} daq';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final next =
        (list.where((a) => a.submission == null && a.dueAt.isAfter(now)).toList()
              ..sort((a, b) => a.dueAt.compareTo(b.dueAt)))
            .firstOrNull;
    // Muddati o'tgan, lekin kechikib topshirsa bo'ladiganlar — "hammasi topshirilgan" deb aldamaslik
    final late = list.where((a) => a.canSubmit && a.isOverdue).length;
    final c = context.appColors;

    if (next == null && late > 0) {
      return BentoTile(
        tint: Palette.danger,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        onTap: () => context.go('/student/tasks'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BentoLabel(icon: Icons.history_rounded, label: 'Kechikkan', color: c.danger),
            const Spacer(),
            BentoNumber('$late ta', size: 24, color: c.danger),
            const SizedBox(height: 2),
            Text(
              "Hali topshirsa bo'ladi",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    final urgent = next != null && next.dueAt.difference(now).inHours < 24;
    final color = next == null ? c.success : (urgent ? c.danger : c.warning);
    return BentoTile(
      tint: next == null ? Palette.success : (urgent ? Palette.danger : Palette.warning),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      onTap: next == null ? null : () => context.push('/student/tasks/${next.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BentoLabel(icon: Icons.timer_rounded, label: 'Keyingi muddat', color: color),
          const Spacer(),
          if (next == null)
            Row(
              children: [
                Icon(Icons.check_circle_rounded, color: color, size: 22),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Hammasi topshirilgan',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      color: context.colors.onSurface,
                    ),
                  ),
                ),
              ],
            )
          else ...[
            BentoNumber(_left(next.dueAt.difference(now)), size: 24, color: color),
            const SizedBox(height: 2),
            Text(
              next.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: context.colors.onSurfaceVariant, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}

class _BadgesTile extends StatelessWidget {
  const _BadgesTile({this.p});

  final StudentProgress? p;

  @override
  Widget build(BuildContext context) {
    const violet = Color(0xFF7C3AED);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = dark ? const Color(0xFFA78BFA) : violet;
    return BentoTile(
      tint: violet,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      onTap: () => context.push('/badges'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BentoLabel(icon: Icons.military_tech_rounded, label: 'Nishonlar', color: color),
          const Spacer(),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: p == null ? '—' : '${p!.badgesEarned}',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: context.colors.onSurface,
                    height: 1,
                  ),
                ),
                if (p != null)
                  TextSpan(
                    text: ' / ${p!.badgesTotal}',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: context.colors.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
