import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/motion.dart';
import '../../auth/application/auth_controller.dart';
import '../../chat/chat_list_screen.dart';
import 'dashboard_models.dart';

/// Yangi ("bento") ustoz dashboard'ining bloklari.
///
/// Tamoyil: kunning eng muhim ishi — bitta katta fokus kartada; asosiy raqamlar — turli
/// o'lchamdagi ranglangan bloklarda (muhimi kattaroq); chegara chiziqlari yo'q, yumaloq burchaklar.

const _weekdays = ['Dushanba', 'Seshanba', 'Chorshanba', 'Payshanba', 'Juma', 'Shanba', 'Yakshanba'];
const _weekdaysShort = ['Du', 'Se', 'Ch', 'Pa', 'Ju', 'Sh', 'Ya'];
const _tileRadius = Radii.card;

// ---------------------------------------------------------------- Sarlavha

class BentoHeader extends ConsumerWidget {
  const BentoHeader({super.key});

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 11) return 'Xayrli tong';
    if (h < 17) return 'Assalomu alaykum';
    return 'Xayrli kech';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider);
    final now = DateTime.now();
    return Padding(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 14, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_weekdays[now.weekday - 1]}, ${now.day}-${uzMonths[now.month - 1]}'.toUpperCase(),
                  style: TextStyle(
                    color: context.colors.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_greeting()},\n${me?.firstName ?? ''}',
                  style: TextStyle(
                    color: context.colors.onSurface,
                    fontSize: 28,
                    height: 1.12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                  ),
                ),
              ],
            ),
          ),
          const ChatButton(),
          const SizedBox(width: 10),
          Pressable(
            onTap: () => context.go('/teacher/profile'),
            child: GestureDetector(
              onTap: () => context.go('/teacher/profile'),
              child: Avatar(initials: me?.initials ?? '', imageUrl: me?.avatarUrl, size: 50),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sahifa tepasidagi juda yumshoq rangli "dog'lar" (blur emas — radial gradient, arzon)
class BentoBackdrop extends StatelessWidget {
  const BentoBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final p = context.colors.primary;
    Widget orb(Color c, double size, double a) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            c.withValues(alpha: a),
            c.withValues(alpha: 0),
          ],
        ),
      ),
    );
    return IgnorePointer(
      child: SizedBox(
        height: 380,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(top: -120, right: -90, child: orb(p, 340, dark ? 0.28 : 0.16)),
            Positioned(top: 40, left: -140, child: orb(Palette.info, 300, dark ? 0.18 : 0.12)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Fokus karta

/// Kunning eng muhim ishi: tekshirish → tasdiqlash → yangi vazifa (shu tartibda)
class FocusCard extends StatelessWidget {
  const FocusCard({super.key, required this.d, required this.onNewAssignment});

  final TeacherDashboard d;
  final VoidCallback onNewAssignment;

  @override
  Widget build(BuildContext context) {
    final s = d.stats;
    final waiting = d.recent.where((r) => r.status != 'graded').map((r) => r.studentName).toList();
    final (IconData icon, String title, String subtitle, String action, VoidCallback onTap) = s.toReview > 0
        ? (
            Icons.fact_check_rounded,
            '${s.toReview} ta ish tekshiruvingizni kutmoqda',
            "AI ishonchi past bo'lgan ishlar — bir qarab, bahoni tasdiqlang",
            'Tekshirish',
            () => context.push('/teacher/review'),
          )
        : s.drafts > 0
        ? (
            Icons.auto_awesome_rounded,
            '${s.drafts} ta vazifa tayyor',
            "AI tayyorladi. Ko'rib chiqib, o'quvchilarga yuboring",
            "Ko'rish",
            () => context.go('/teacher/groups'),
          )
        : (
            Icons.check_circle_rounded,
            'Hammasi joyida',
            "Tekshiriladigan ish yo'q. Yangi vazifa berasizmi?",
            'Vazifa berish',
            onNewAssignment,
          );

    final p = context.colors.primary;
    final c2 = Color.lerp(p, const Color(0xFF7C3AED), 0.55)!;
    return Pressable(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_tileRadius + 2),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [p, c2]),
          boxShadow: [BoxShadow(color: p.withValues(alpha: 0.35), blurRadius: 28, offset: const Offset(0, 12))],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(_tileRadius + 2),
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Stack(
              children: [
                // Bezak: katta yarim shaffof halqalar
                Positioned(
                  right: -40,
                  top: -50,
                  child: Container(
                    width: 170,
                    height: 170,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 26),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(icon, color: Colors.white),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          height: 1.2,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 14)),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          if (s.toReview > 0 && waiting.isNotEmpty) _AvatarStack(names: waiting),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(100)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  action,
                                  style: TextStyle(color: p, fontWeight: FontWeight.w800, fontSize: 14.5),
                                ),
                                const SizedBox(width: 4),
                                Icon(Icons.arrow_forward_rounded, color: p, size: 18),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
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

class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.names});

  final List<String> names;

  String _initials(String n) => n.split(' ').where((p) => p.isNotEmpty).map((p) => p[0]).take(2).join();

  @override
  Widget build(BuildContext context) {
    final shown = names.take(3).toList();
    final extra = names.length - shown.length;
    const size = 34.0;
    return SizedBox(
      height: size,
      width: size + (shown.length - 1 + (extra > 0 ? 1 : 0)) * (size * 0.62),
      child: Stack(
        children: [
          for (final (i, n) in shown.indexed)
            Positioned(
              left: i * size * 0.62,
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.92),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Text(
                  _initials(n),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: context.colors.primary),
                ),
              ),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * size * 0.62,
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.25),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 2),
                ),
                child: Text(
                  '+$extra',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Bento bloklar

/// Bento blok: chegarasiz, yumaloq; [tint] berilsa — shu rangda yengil bo'yalgan
class BentoTile extends StatelessWidget {
  const BentoTile({super.key, required this.child, this.tint, this.onTap, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final Color? tint;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).cardTheme.color ?? context.colors.surface;
    final bg = tint == null ? surface : Color.lerp(surface, tint, dark ? 0.16 : 0.09)!;
    final body = Material(
      color: bg,
      borderRadius: BorderRadius.circular(_tileRadius),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: Padding(padding: padding, child: child),
      ),
    );
    final shadowed = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_tileRadius),
        boxShadow: dark
            ? null
            : [BoxShadow(color: Palette.slate900.withValues(alpha: 0.05), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: body,
    );
    return onTap == null ? shadowed : Pressable(onTap: onTap, child: shadowed);
  }
}

/// Blok yuqorisidagi kichik ikonka + yorliq
class _TileLabel extends StatelessWidget {
  const _TileLabel({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 17, color: color),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );
}

class _BigNumber extends StatelessWidget {
  const _BigNumber(this.value, {this.color, this.size = 34});

  final String value;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
    value,
    style: TextStyle(
      fontSize: size,
      height: 1,
      fontWeight: FontWeight.w800,
      letterSpacing: -1,
      color: color ?? context.colors.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
}

/// Asosiy bento: chapda katta "haftalik natija" halqasi, o'ngda ikki kichik blok, pastda faollik
class BentoStats extends StatelessWidget {
  const BentoStats({super.key, required this.d});

  final TeacherDashboard d;

  @override
  Widget build(BuildContext context) {
    final s = d.stats;
    final c = context.appColors;
    return Column(
      children: [
        SizedBox(
          height: 196,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 11, child: _WeekScoreTile(stats: s)),
              const SizedBox(width: 12),
              Expanded(
                flex: 9,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: BentoTile(
                        tint: Palette.info,
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                        onTap: () => context.go('/teacher/groups'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _TileLabel(icon: Icons.people_alt_rounded, label: "O'quvchilar", color: c.info),
                            const Spacer(),
                            _BigNumber('${s.students}', size: 28),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: BentoTile(
                        tint: Palette.success,
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                        onTap: () => context.go('/teacher/groups'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _TileLabel(icon: Icons.assignment_rounded, label: 'Faol vazifa', color: c.success),
                            const Spacer(),
                            _BigNumber('${s.openAssignments}', size: 28),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ActivityTile(days: d.activity),
      ],
    );
  }
}

class _WeekScoreTile extends StatelessWidget {
  const _WeekScoreTile({required this.stats});

  final DashboardStats stats;

  @override
  Widget build(BuildContext context) {
    final avg = stats.avgPercentWeek;
    final c = context.appColors;
    final color = avg == null
        ? context.colors.primary
        : avg >= 86
        ? c.success
        : avg >= 71
        ? c.info
        : avg >= 51
        ? c.warning
        : c.danger;
    final label = avg == null
        ? 'Hali baho yo\'q'
        : avg >= 86
        ? "A'lo"
        : avg >= 71
        ? 'Yaxshi'
        : avg >= 51
        ? 'Qoniqarli'
        : 'Past';
    return BentoTile(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TileLabel(icon: Icons.insights_rounded, label: 'Shu hafta', color: context.colors.primary),
          const Spacer(),
          Center(
            child: SizedBox.square(
              dimension: 104,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: (avg ?? 0) / 100),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: avg == null ? 0 : v,
                      strokeWidth: 10,
                      strokeCap: StrokeCap.round,
                      color: color,
                      backgroundColor: color.withValues(alpha: 0.13),
                    ),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (avg == null)
                            Icon(Icons.hourglass_empty_rounded, size: 26, color: color)
                          else
                            _BigNumber('${(v * 100).round()}%', size: 26, color: color),
                          const SizedBox(height: 2),
                          Text(
                            label,
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          Center(
            child: Text(
              stats.gradedThisWeek == 0 ? 'Bu hafta ish baholanmadi' : '${stats.gradedThisWeek} ta ish baholandi',
              style: TextStyle(fontSize: 12.5, color: context.colors.onSurfaceVariant, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.days});

  final List<ActivityDay> days;

  @override
  Widget build(BuildContext context) {
    final total = days.fold<int>(0, (a, d) => a + d.count);
    final maxV = days.fold<int>(0, (a, d) => math.max(a, d.count));
    final p = context.colors.primary;
    final today = DateTime.now();
    return BentoTile(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _TileLabel(icon: Icons.bar_chart_rounded, label: 'Topshirilgan ishlar · 7 kun', color: p),
              ),
              _BigNumber('$total', size: 22),
            ],
          ),
          const SizedBox(height: 14),
          if (total == 0)
            Container(
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: p.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(16)),
              child: Text(
                'Oxirgi 7 kunda ish topshirilmadi',
                style: TextStyle(fontSize: 13, color: context.colors.onSurfaceVariant, fontWeight: FontWeight.w600),
              ),
            )
          else
            SizedBox(
              height: 64,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final d in days)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: maxV == 0 ? 0 : d.count / maxV),
                          duration: const Duration(milliseconds: 700),
                          curve: Curves.easeOutCubic,
                          builder: (context, v, _) {
                            final isToday =
                                d.day.year == today.year && d.day.month == today.month && d.day.day == today.day;
                            return Container(
                              height: math.max(6, 64 * v),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                gradient: isToday || d.count == maxV && maxV > 0
                                    ? LinearGradient(
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.topCenter,
                                        colors: [p, Color.lerp(p, const Color(0xFF7C3AED), 0.5)!],
                                      )
                                    : null,
                                color: isToday || d.count == maxV && maxV > 0 ? null : p.withValues(alpha: 0.18),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (total > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                for (final d in days)
                  Expanded(
                    child: Text(
                      _weekdaysShort[d.day.weekday - 1],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: context.colors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Tezkor amallar

class BentoAction {
  const BentoAction(this.icon, this.label, this.color, this.onTap, {this.badge = 0});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final int badge;
}

/// Bank ilovalaridagidek: yumaloq-kvadrat ikonka va ostida qisqa yorliq
class BentoActions extends StatelessWidget {
  const BentoActions({super.key, required this.actions});

  final List<BentoAction> actions;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).cardTheme.color ?? context.colors.surface;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final a in actions)
          Expanded(
            child: Pressable(
              onTap: a.onTap,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  a.onTap();
                },
                child: Column(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: Color.lerp(surface, a.color, dark ? 0.22 : 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(a.icon, color: a.color, size: 26),
                        ),
                        if (a.badge > 0)
                          Positioned(
                            right: -4,
                            top: -4,
                            child: Container(
                              constraints: const BoxConstraints(minWidth: 22),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: context.appColors.danger,
                                borderRadius: BorderRadius.circular(100),
                                border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                              ),
                              child: Text(
                                '${a.badge}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      a.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        color: context.colors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Ixcham ogohlantirish (tarif tugagan, qo'shilish so'rovlari)
class BentoNotice extends StatelessWidget {
  const BentoNotice({super.key, required this.icon, required this.text, required this.tone, this.onTap});

  final IconData icon;
  final String text;
  final StatusTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final (fg, bg) = switch (tone) {
      StatusTone.danger => (c.danger, c.dangerContainer),
      StatusTone.warning => (c.warning, c.warningContainer),
      StatusTone.success => (c.success, c.successContainer),
      _ => (c.info, c.infoContainer),
    };
    return Pressable(
      onTap: onTap,
      child: Material(
        color: bg.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              children: [
                Icon(icon, color: fg, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: context.colors.onSurface),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
