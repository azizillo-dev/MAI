import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import '../data/gamification_models.dart';
import 'hex_badge.dart';

/// Nishonlar (jetonlar): toifalar bo'yicha, olinganlari rangli, olinmaganlari kulrang.
class BadgesScreen extends ConsumerWidget {
  const BadgesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(studentProgressProvider);
    final p = async.value;
    return Scaffold(
      appBar: AppBar(title: const Text('Nishonlar')),
      body: p == null
          ? (async.hasError
              ? ErrorRetry(error: async.error!, onRetry: () => ref.invalidate(studentProgressProvider))
              : const Center(child: CircularProgressIndicator()))
          : ListView(
              padding: Insets.screen.copyWith(top: 4, bottom: 32),
              children: [
                _Summary(p: p),
                if (p.medals.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _CategoryCard(
                    title: 'Oy medallari',
                    children: [
                      for (final m in p.medals.reversed)
                        _BadgeCell(
                          badge: HexBadge(tier: m.tier, icon: Icons.emoji_events_rounded, label: '${_rankOf(m)}', size: 78),
                          name: _monthLabel(m.month),
                          onTap: () => _showMedal(context, m),
                        ),
                    ],
                  ),
                ],
                for (final entry in _byCategory(p.badges).entries) ...[
                  const SizedBox(height: 14),
                  _CategoryCard(
                    title: entry.key,
                    children: [
                      for (final b in entry.value)
                        _BadgeCell(
                          badge: HexBadge(tier: b.tier, icon: badgeIcons[b.icon] ?? Icons.star_rounded, earned: b.earned, size: 78),
                          name: b.name,
                          progress: b.earned ? null : b.progress,
                          onTap: () => showBadgeSheet(context, b),
                        ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }

  static int _rankOf(Medal m) => switch (m.tier) { 'gold' => 1, 'silver' => 2, _ => 3 };

  static Map<String, List<BadgeInfo>> _byCategory(List<BadgeInfo> list) {
    final out = <String, List<BadgeInfo>>{};
    for (final b in list) {
      (out[b.categoryName] ??= []).add(b);
    }
    return out;
  }

  void _showMedal(BuildContext context, Medal m) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => _SheetBody(
        badge: HexBadge(tier: m.tier, icon: Icons.emoji_events_rounded, label: '${_rankOf(m)}', size: 120),
        title: m.name,
        subtitle: '${_monthLabel(m.month)} · ${m.groupName ?? ''}',
        body: m.points == null ? null : '${m.points} XP to\'plab, guruhda ${_rankOf(m)}-o\'rinni egalladingiz!',
      ),
    );
  }
}

String _monthLabel(String month) {
  final parts = month.split('-');
  if (parts.length != 2) return month;
  final m = int.tryParse(parts[1]) ?? 1;
  final name = uzMonths[(m - 1).clamp(0, 11)];
  return '${name[0].toUpperCase()}${name.substring(1)} ${parts[0]}';
}

void showBadgeSheet(BuildContext context, BadgeInfo b) {
  HapticFeedback.selectionClick();
  showModalBottomSheet<void>(
    context: context,
    builder: (context) => _SheetBody(
      badge: HexBadge(tier: b.tier, icon: badgeIcons[b.icon] ?? Icons.star_rounded, earned: b.earned, size: 120),
      title: b.name,
      subtitle: b.earned ? 'Olingan: ${formatDateUz(b.earnedAt!)}' : b.categoryName,
      body: b.description,
      progress: b.earned ? null : (b.value, b.target),
    ),
  );
}

class _SheetBody extends StatelessWidget {
  const _SheetBody({required this.badge, required this.title, required this.subtitle, this.body, this.progress});

  final Widget badge;
  final String title;
  final String subtitle;
  final String? body;
  final (int, int)? progress;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.7, end: 1),
              duration: const Duration(milliseconds: 450),
              curve: Curves.elasticOut,
              builder: (context, s, child) => Transform.scale(scale: s, child: child),
              child: badge,
            ),
            const SizedBox(height: 14),
            Text(title, style: context.text.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(subtitle, style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant)),
            if (body != null) ...[
              const SizedBox(height: 12),
              Text(body!, textAlign: TextAlign.center, style: context.text.bodyLarge),
            ],
            if (progress case (final v, final t)) ...[
              const SizedBox(height: 18),
              ProgressLine(value: v, target: t),
            ],
          ],
        ),
      ),
    );
  }
}

/// Cambridge'dagidek: to'q sariq chiziq + "94/100"
class ProgressLine extends StatelessWidget {
  const ProgressLine({super.key, required this.value, required this.target, this.color});

  final int value;
  final int target;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ratio = target == 0 ? 0.0 : (value / target).clamp(0.0, 1.0);
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: ratio),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 8,
                color: color ?? Palette.warning,
                backgroundColor: context.colors.surfaceContainer,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text('$value/$target', style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.p});

  final StudentProgress p;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Row(
        children: [
          const HexBadge(tier: 'gold', icon: Icons.military_tech_rounded, size: 56),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${p.badgesEarned} / ${p.badgesTotal} nishon', style: context.text.titleLarge),
                const SizedBox(height: 2),
                Text(
                  "Vazifalarni muddatida va a'lo bajarib, yangi nishonlar oching",
                  style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: context.text.titleLarge),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 0.92,
              mainAxisSpacing: 4,
              children: children,
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgeCell extends StatelessWidget {
  const _BadgeCell({required this.badge, required this.name, required this.onTap, this.progress});

  final Widget badge;
  final String name;
  final VoidCallback onTap;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          badge,
          const SizedBox(height: 6),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (progress != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(100),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  color: Palette.warning,
                  backgroundColor: context.colors.surfaceContainer,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
