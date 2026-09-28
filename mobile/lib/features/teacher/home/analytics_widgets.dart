import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/math_text.dart';
import '../../../core/widgets/trend_chart.dart';
import 'dashboard_models.dart';

Color percentColor(BuildContext context, double? p) => p == null
    ? context.appColors.muted
    : p >= 86
    ? context.appColors.success
    : p >= 71
    ? Palette.info
    : p >= 51
    ? context.appColors.warning
    : context.appColors.danger;

// ---------------------------------------------------------------- Guruhlar tahlili

/// Har bir guruh uchun karta: asosiy ko'rsatkichlar, 8 haftalik trend va AI topgan "og'riqli nuqtalar"
class GroupAnalyticsCarousel extends StatefulWidget {
  const GroupAnalyticsCarousel({super.key, required this.groups});

  final List<GroupAnalytics> groups;

  @override
  State<GroupAnalyticsCarousel> createState() => _GroupAnalyticsCarouselState();
}

class _GroupAnalyticsCarouselState extends State<GroupAnalyticsCarousel> {
  // Markazlashgan karusel: ikki yonida qo'shni karta ozgina ko'rinadi (surish mumkinligini bildiradi)
  late final _controller = PageController(viewportFraction: widget.groups.length > 1 ? 0.88 : 1);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groups = widget.groups;
    return Column(
      children: [
        SizedBox(
          height: 360,
          child: groups.length > 1
              ? FullBleed(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: groups.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: _GroupCard(g: groups[i]),
                    ),
                  ),
                )
              : _GroupCard(g: groups.first),
        ),
        if (groups.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < groups.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page ? context.colors.primary : context.colors.outlineVariant,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.g});

  final GroupAnalytics g;

  @override
  Widget build(BuildContext context) {
    final points = g.weekly.whereType<double>().toList();
    final delta = points.length >= 2 ? points.last - points.first : null;
    return SectionCard(
      onTap: () => context.push('/teacher/groups/${g.groupId}'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: context.colors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(g.subject == 'english' ? Icons.translate_rounded : Icons.calculate_rounded,
                    size: 20, color: context.colors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleMedium),
                    Text(subjectLabel(g.subject),
                        style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: context.appColors.muted),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _Kpi(value: '${g.students}', label: "O'quvchi"),
              _Kpi(value: '${g.assignments}', label: 'Vazifa'),
              _Kpi(value: '${g.checked}', label: 'Tekshirilgan'),
              _Kpi(
                value: g.avgPercent == null ? '—' : '${g.avgPercent!.round()}%',
                label: "O'rtacha",
                color: percentColor(context, g.avgPercent),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text('8 haftalik natija', style: context.text.labelMedium?.copyWith(color: context.appColors.muted)),
              const Spacer(),
              if (delta != null)
                StatusChip(
                  label: '${delta >= 0 ? '+' : ''}${delta.round()}%',
                  tone: delta >= 3 ? StatusTone.success : delta <= -3 ? StatusTone.danger : StatusTone.neutral,
                  icon: delta >= 3 ? Icons.trending_up_rounded : delta <= -3 ? Icons.trending_down_rounded : Icons.trending_flat_rounded,
                ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 92,
            width: double.infinity,
            child: points.length >= 2
                ? TrendChart(values: g.weekly)
                : Center(
                    child: Text("Trend uchun kamida 2 haftalik ma'lumot kerak",
                        style: context.text.bodySmall?.copyWith(color: context.appColors.muted)),
                  ),
          ),
          const Spacer(),
          if (g.hardestTitle == null && g.mistakeText == null && g.lowPerformers == 0)
            _Insight(
              icon: Icons.hourglass_empty_rounded,
              color: context.appColors.muted,
              child: const Text("Tahlil uchun baholangan ishlar yig'ilmoqda"),
            ),
          if (g.hardestTitle case final t?)
            _Insight(
              icon: Icons.local_fire_department_rounded,
              color: context.appColors.warning,
              child: Text.rich(TextSpan(children: [
                const TextSpan(text: 'Eng qiyin: '),
                TextSpan(text: t, style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: ' · ${g.hardestPercent?.round()}%'),
              ]), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          if (g.mistakeText case final m?)
            _Insight(
              icon: Icons.error_outline_rounded,
              color: context.appColors.danger,
              child: Row(
                children: [
                  Text('${g.mistakeNumber}-misol: ', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Expanded(
                    child: ClipRect(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const NeverScrollableScrollPhysics(),
                        child: MathText(m.isEmpty ? (g.mistakeAssignment ?? '') : m),
                      ),
                    ),
                  ),
                  Text(' ${g.mistakePercent}% xato',
                      style: TextStyle(color: context.appColors.danger, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          if (g.lowPerformers > 0)
            _Insight(
              icon: Icons.person_search_rounded,
              color: Palette.info,
              child: Text("${g.lowPerformers} ta o'quvchi o'rtachasi 60% dan past"),
            ),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.value, required this.label, this.color});

  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: color)),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: context.text.labelSmall?.copyWith(color: context.appColors.muted)),
          ],
        ),
      );
}

class _Insight extends StatelessWidget {
  const _Insight({required this.icon, required this.color, required this.child});

  final IconData icon;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(child: DefaultTextStyle.merge(style: context.text.bodySmall, child: child)),
          ],
        ),
      );
}

// ---------------------------------------------------------------- Baholar taqsimoti

class GradeDistributionCard extends StatelessWidget {
  const GradeDistributionCard({super.key, required this.analytics});

  final TeacherAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final d = analytics.distribution;
    final total = analytics.totalGraded;
    final parts = [
      ("A'lo", '86–100%', d['excellent'] ?? 0, context.appColors.success),
      ('Yaxshi', '71–85%', d['good'] ?? 0, Palette.info),
      ('Qoniqarli', '51–70%', d['fair'] ?? 0, context.appColors.warning),
      ('Past', '0–50%', d['poor'] ?? 0, context.appColors.danger),
    ];
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Baholar taqsimoti', style: context.text.titleMedium),
              const Spacer(),
              Text('$total ta ish · 8 hafta',
                  style: context.text.bodySmall?.copyWith(color: context.appColors.muted)),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 14,
              // stretch: rangli bo'laklar to'liq balandlikni egallaydi (aks holda 0 px bo'lib qoladi)
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, p) in parts.where((p) => p.$3 > 0).indexed) ...[
                    if (i > 0) SizedBox(width: 2, child: ColoredBox(color: context.colors.surfaceContainerLowest)),
                    Expanded(flex: p.$3, child: ColoredBox(color: p.$4)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final p in parts)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(color: p.$4, shape: BoxShape.circle)),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(p.$1, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: context.text.labelMedium),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(total == 0 ? '—' : '${(p.$3 / total * 100).round()}%',
                          style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      Text(p.$2, style: context.text.labelSmall?.copyWith(color: context.appColors.muted)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
