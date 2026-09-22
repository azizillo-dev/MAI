import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../auth/application/auth_controller.dart';
import '../auth/data/auth_models.dart';
import '../auth/data/auth_repository.dart';
import '../gamification/data/gamification_models.dart';
import '../gamification/presentation/badges_screen.dart';
import '../gamification/presentation/hex_badge.dart';
import '../groups/data/groups_repository.dart';
import '../teacher/home/teacher_home_screen.dart' show PlanCard;

/// Profil: o'quvchi uchun daraja, statistika, nishonlar va yutuqlar; o'qituvchi uchun ish bo'limlari.
/// Sozlamalar (tahrirlash, ranglar, til) tepadagi tishli g'ildirak orqali alohida sahifada.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider);
    if (me == null) return const SizedBox.shrink();

    Future<void> refresh() async {
      if (me.isStudent) {
        ref.invalidate(studentProgressProvider);
        await ref.read(studentProgressProvider.future);
      } else {
        ref.invalidate(planUsageProvider);
      }
      await ref.read(authControllerProvider.notifier).refreshMe();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Profil', style: context.text.headlineSmall),
        actions: [
          IconButton.filledTonal(
            tooltip: 'Sozlamalar',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_rounded),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: Insets.screen.copyWith(top: 4, bottom: 32),
          children: [
            _Header(me: me),
            const SizedBox(height: 22),
            if (me.isStudent) const _StudentSections() else const _TeacherSections(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Sarlavha (avatar, ID, ism)

Future<void> pickAvatar(BuildContext context, WidgetRef ref) async {
  final me = ref.read(currentUserProvider);
  final source = await showModalBottomSheet<ImageSource?>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_rounded),
            title: const Text('Kamera'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_rounded),
            title: const Text('Galereya'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          if (me?.avatarUrl != null)
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: context.appColors.danger),
              title: Text("Rasmni o'chirish", style: TextStyle(color: context.appColors.danger)),
              onTap: () => Navigator.pop(context, null),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  final repo = ref.read(authRepositoryProvider);
  try {
    Me updated;
    if (source == null) {
      if (me?.avatarUrl == null) return;
      updated = await repo.deleteAvatar();
    } else {
      // Kichik va siqilgan: tez yuklanadi, reytingda ham tez ko'rinadi
      final x = await ImagePicker().pickImage(source: source, maxWidth: 512, maxHeight: 512, imageQuality: 85);
      if (x == null) return;
      updated = await repo.uploadAvatar(x.path);
    }
    await ref.read(authControllerProvider.notifier).updateMe(updated);
    if (context.mounted) showSnack(context, 'Profil rasmi yangilandi');
  } on ApiException catch (e) {
    if (context.mounted) showSnack(context, e.message, error: true);
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.me});

  final Me me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primary = context.colors.primary;
    final progress = me.isStudent ? ref.watch(studentProgressProvider).value : null;
    final subtitle = me.isTeacher
        ? "O'qituvchi"
        : progress == null
            ? "O'quvchi"
            : '${progress.level}-daraja · ${progress.levelName}';
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            GestureDetector(
              onTap: () => pickAvatar(context, ref),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 10))],
                ),
                child: Avatar(initials: me.initials, imageUrl: me.avatarUrl, size: 112, ring: primary),
              ),
            ),
            Positioned(
              top: 0,
              right: -4,
              child: Material(
                color: context.colors.surface,
                shape: CircleBorder(side: BorderSide(color: context.colors.outlineVariant)),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => pickAvatar(context, ref),
                  child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: Icon(Icons.photo_camera_rounded, size: 18, color: primary),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -12,
              child: GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: me.shortId));
                  showSnack(context, 'ID nusxalandi');
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: primary,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: context.theme.scaffoldBackgroundColor, width: 2),
                  ),
                  child: Text(
                    'ID: ${me.shortId}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5, letterSpacing: 0.5),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(me.fullName, style: context.text.headlineSmall, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: 'Telefon raqam tasdiqlangan',
              child: Icon(Icons.verified_rounded, color: primary, size: 22),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(subtitle, style: context.text.bodyLarge?.copyWith(color: context.colors.onSurfaceVariant)),
      ],
    );
  }
}

// ---------------------------------------------------------------- O'quvchi

class _StudentSections extends ConsumerWidget {
  const _StudentSections();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(studentProgressProvider);
    final p = async.value;
    if (p == null) {
      return async.hasError
          ? ErrorRetry(error: async.error!, onRetry: () => ref.invalidate(studentProgressProvider))
          : const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
    }
    final earned = p.badges.where((b) => b.earned).toList();
    final showcase = [...earned.reversed, ...p.badges.where((b) => !b.earned)].take(4).toList();
    final inProgress = p.badges.where((b) => !b.earned).toList()..sort((a, b) => b.progress.compareTo(a.progress));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LevelCard(p: p),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.1,
          children: [
            StatTile(icon: Icons.star_rounded, color: Palette.warning, value: '${p.xp}', label: 'XP ball'),
            StatTile(
              icon: Icons.leaderboard_rounded,
              color: Palette.success,
              value: p.bestRank == null ? '—' : '#${p.bestRank!.rank}',
              label: 'Reyting',
              onTap: () => context.go('/student/rating'),
            ),
            StatTile(
              icon: Icons.local_fire_department_rounded,
              color: Palette.danger,
              value: '${p.currentStreak}',
              label: 'Seriya',
            ),
            StatTile(
              icon: Icons.military_tech_rounded,
              color: const Color(0xFF8B5CF6),
              value: '${p.badgesEarned}/${p.badgesTotal}',
              label: 'Nishonlar',
              onTap: () => context.push('/badges'),
            ),
          ],
        ),
        const SizedBox(height: 22),
        _SectionHeader(title: 'Nishonlar', onAll: () => context.push('/badges')),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (final b in showcase)
                  GestureDetector(
                    onTap: () => showBadgeSheet(context, b),
                    child: HexBadge(tier: b.tier, icon: badgeIcons[b.icon] ?? Icons.star_rounded, earned: b.earned, size: 66),
                  ),
              ],
            ),
          ),
        ),
        if (p.medals.isNotEmpty) ...[
          const SizedBox(height: 22),
          _SectionHeader(title: 'Oy medallari', onAll: () => context.push('/badges')),
          SizedBox(
            height: 112,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: p.medals.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final m = p.medals[p.medals.length - 1 - i];
                return Column(
                  children: [
                    HexBadge(tier: m.tier, icon: Icons.emoji_events_rounded, size: 74,
                        label: switch (m.tier) { 'gold' => '1', 'silver' => '2', _ => '3' }),
                    const SizedBox(height: 4),
                    Text(m.month, style: context.text.bodySmall),
                  ],
                );
              },
            ),
          ),
        ],
        if (inProgress.isNotEmpty) ...[
          const SizedBox(height: 22),
          _SectionHeader(title: 'Yutuqlar'),
          for (final b in inProgress.take(4)) ...[
            _AchievementCard(badge: b),
            const SizedBox(height: 10),
          ],
        ],
        const SizedBox(height: 12),
        _MenuCard(
          icon: Icons.emoji_events_rounded,
          color: Palette.gold,
          title: 'Reyting',
          subtitle: p.bestRank == null ? 'Guruhdagi o\'rningiz' : '${p.bestRank!.groupName}: ${p.bestRank!.rank}/${p.bestRank!.of}',
          onTap: () => context.go('/student/rating'),
        ),
      ],
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.p});

  final StudentProgress p;

  @override
  Widget build(BuildContext context) {
    final primary = context.colors.primary;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.lg + 2),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primary, Color.lerp(primary, Palette.info, 0.55)!],
        ),
        boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8))],
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
                    Text(p.levelName, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      'Keyingi daraja: ${p.levelSpan - p.levelXp} XP qoldi',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13.5),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(100)),
                child: Text('${p.level}-daraja', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: p.levelProgress),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 10,
                color: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.25),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Pill('${p.works} ta ish'),
              const SizedBox(width: 8),
              _Pill("O'rtacha ${p.avgPercent}%"),
              const SizedBox(width: 8),
              _Pill('Rekord: ${p.bestStreak}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Flexible(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5),
          ),
        ),
      );
}

/// Rangli ikonka pufakchasi + katta raqam (Cambridge/Ibrat uslubi)
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.icon, required this.color, required this.value, required this.label, this.onTap});

  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(Radii.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(color: context.colors.outlineVariant.withValues(alpha: 0.7)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color.lerp(color, Colors.white, 0.25)!, color],
                  ),
                  boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(value, style: context.text.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w800)),
                    ),
                    Text(label, maxLines: 1, style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
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

class _AchievementCard extends StatelessWidget {
  const _AchievementCard({required this.badge});

  final BadgeInfo badge;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
      onTap: () => showBadgeSheet(context, badge),
      child: Row(
        children: [
          HexBadge(tier: badge.tier, icon: badgeIcons[badge.icon] ?? Icons.star_rounded, size: 62),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(badge.name, style: context.text.titleMedium),
                const SizedBox(height: 2),
                Text(
                  badge.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                ProgressLine(value: badge.value, target: badge.target),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- O'qituvchi

class _TeacherSections extends ConsumerWidget {
  const _TeacherSections();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(teacherGroupsProvider).value ?? const [];
    final students = groups.fold<int>(0, (s, g) => s + g.membersActive);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.1,
          children: [
            StatTile(
              icon: Icons.groups_rounded,
              color: Palette.success,
              value: '${groups.length}',
              label: 'Guruhlar',
              onTap: () => context.go('/teacher/groups'),
            ),
            StatTile(icon: Icons.people_alt_rounded, color: Palette.info, value: '$students', label: "O'quvchilar"),
          ],
        ),
        const SizedBox(height: 16),
        _MenuCard(
          icon: Icons.auto_awesome_rounded,
          color: const Color(0xFF8B5CF6),
          title: 'AI profilim',
          subtitle: 'Fan, baholash tizimi, tekshiruv uslubi',
          onTap: () => context.push('/teacher/ai-profile'),
        ),
        const SizedBox(height: 10),
        _MenuCard(
          icon: Icons.emoji_events_rounded,
          color: Palette.gold,
          title: "O'quvchilar reytingi",
          subtitle: 'Guruhlaringizdagi eng faol o\'quvchilar',
          onTap: () => context.push('/leaderboard'),
        ),
        const SizedBox(height: 10),
        _MenuCard(
          icon: Icons.fact_check_rounded,
          color: Palette.warning,
          title: 'Tekshirish kerak',
          subtitle: 'AI ishonchi past bo\'lgan ishlar',
          onTap: () => context.push('/teacher/review'),
        ),
        const SizedBox(height: 16),
        if (ref.watch(planUsageProvider).value case final plan?) PlanCard(plan: plan),
      ],
    );
  }
}

// ---------------------------------------------------------------- Umumiy

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.onAll});

  final String title;
  final VoidCallback? onAll;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Expanded(child: Text(title, style: context.text.titleLarge)),
            if (onAll != null)
              TextButton(
                onPressed: onAll,
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [Text('Barchasi'), Icon(Icons.chevron_right_rounded, size: 20)],
                ),
              ),
          ],
        ),
      );
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.icon, required this.color, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [Color.lerp(color, Colors.white, 0.2)!, color]),
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.titleMedium),
                const SizedBox(height: 2),
                Text(subtitle, style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: context.colors.onSurfaceVariant),
        ],
      ),
    );
  }
}
