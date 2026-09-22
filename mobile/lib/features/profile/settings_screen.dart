import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_widgets.dart';
import '../auth/application/auth_controller.dart';
import '../auth/data/auth_models.dart';
import '../auth/data/auth_repository.dart';
import 'profile_screen.dart' show pickAvatar;

/// Sozlamalar: profilni tahrirlash, ko'rinish (tema, rang), til, bildirishnomalar, hisob.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider);
    if (me == null) return const SizedBox.shrink();
    return Scaffold(
      appBar: AppBar(title: const Text('Sozlamalar')),
      body: ListView(
        padding: Insets.screen.copyWith(top: 4, bottom: 40),
        children: [
          const _Title('Profil'),
          _Group(children: [
            _Tile(
              leading: Avatar(initials: me.initials, imageUrl: me.avatarUrl, size: 40),
              title: 'Profil rasmi',
              subtitle: me.avatarUrl == null ? "Rasm qo'shing — reytingda shu ko'rinadi" : "O'zgartirish yoki o'chirish",
              onTap: () => pickAvatar(context, ref),
            ),
            _Tile(
              icon: Icons.badge_rounded,
              color: Palette.info,
              title: 'Ism va familiya',
              subtitle: me.fullName,
              trailing: me.isStudent && !(me.student?.canEdit ?? false)
                  ? const Icon(Icons.lock_rounded, size: 18)
                  : null,
              onTap: () => me.isTeacher
                  ? _editTeacherName(context, ref, me)
                  : (me.student?.canEdit ?? false)
                      ? context.push('/student/profile/edit')
                      : showSnack(context, "O'zgartirish uchun ustozingizdan ruxsat so'rang"),
            ),
            if (me.isStudent)
              _Tile(
                icon: Icons.cake_rounded,
                color: Palette.danger,
                title: "Tug'ilgan sana",
                subtitle: formatDateUz(me.student!.birthDate),
                trailing: const Icon(Icons.lock_rounded, size: 18),
              ),
            _Tile(
              icon: me.email != null ? Icons.alternate_email_rounded : Icons.phone_iphone_rounded,
              color: Palette.success,
              title: me.email != null ? 'Email' : 'Telefon raqam',
              subtitle: me.contact,
              trailing: Icon(Icons.verified_rounded, size: 20, color: context.colors.primary),
            ),
            if (me.isTeacher)
              _Tile(
                icon: Icons.auto_awesome_rounded,
                color: const Color(0xFF8B5CF6),
                title: 'AI profilim',
                subtitle: 'Fan, baholash tizimi, tekshiruv uslubi',
                onTap: () => context.push('/teacher/ai-profile'),
              ),
          ]),
          const SizedBox(height: 22),
          const _Title("Ko'rinish"),
          const _AppearanceCard(),
          const SizedBox(height: 22),
          const _Title('Til'),
          _Group(children: [
            for (final (code, name, flag) in const [
              ('uz', "O'zbekcha", '🇺🇿'),
              ('ru', 'Русский', '🇷🇺'),
              ('en', 'English', '🇬🇧'),
            ])
              _Tile(
                leading: Text(flag, style: const TextStyle(fontSize: 24)),
                title: name,
                subtitle: code == 'uz' ? null : 'Tez orada',
                trailing: code == 'uz' ? Icon(Icons.check_circle_rounded, color: context.colors.primary) : null,
                onTap: code == 'uz' ? null : () => showSnack(context, '$name tili keyingi yangilanishda qo\'shiladi'),
              ),
          ]),
          const SizedBox(height: 22),
          const _Title('Bildirishnomalar'),
          const _NotificationsCard(),
          const SizedBox(height: 22),
          const _Title('Hisob'),
          _Group(children: [
            _Tile(
              icon: Icons.help_outline_rounded,
              color: Palette.info,
              title: 'Yordam va taklif',
              subtitle: "Muammo yoki g'oyangiz bo'lsa yozing",
              onTap: () => showSnack(context, 'Tez orada: ilova ichidan yozish'),
            ),
            _Tile(
              icon: Icons.logout_rounded,
              color: context.appColors.danger,
              title: 'Chiqish',
              titleColor: context.appColors.danger,
              onTap: () async {
                final ok = await confirmDialog(
                  context,
                  title: 'Chiqish',
                  message: "Akkauntdan chiqasizmi? Qayta kirish uchun SMS kod kerak bo'ladi.",
                  confirmLabel: 'Chiqish',
                  destructive: true,
                );
                if (ok) await ref.read(authControllerProvider.notifier).signOut();
              },
            ),
          ]),
          const SizedBox(height: 18),
          Center(
            child: Text(
              'Mentor AI · 0.1.0',
              style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editTeacherName(BuildContext context, WidgetRef ref, Me me) async {
    final first = TextEditingController(text: me.firstName);
    final last = TextEditingController(text: me.lastName);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Ism va familiya', style: context.text.titleLarge),
            const SizedBox(height: 16),
            TextField(controller: first, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Ism')),
            const SizedBox(height: 12),
            TextField(controller: last, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Familiya')),
            const SizedBox(height: 18),
            PrimaryButton(label: 'Saqlash', onPressed: () => Navigator.pop(context, true)),
          ],
        ),
      ),
    );
    if (saved != true) return;
    try {
      final updated = await ref.read(authRepositoryProvider).updateName(
            firstName: first.text.trim(),
            lastName: last.text.trim(),
          );
      await ref.read(authControllerProvider.notifier).updateMe(updated);
      if (context.mounted) showSnack(context, 'Saqlandi');
    } on ApiException catch (e) {
      if (context.mounted) showSnack(context, e.message, error: true);
    } finally {
      first.dispose();
      last.dispose();
    }
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text, style: context.text.titleMedium?.copyWith(color: context.colors.onSurfaceVariant)),
      );
}

/// Bir nechta qatorni bitta yumaloq kartaga yig'adi (iOS/Cambridge uslubi)
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          for (final (i, c) in children.indexed) ...[
            if (i > 0) const Divider(height: 1, indent: 68),
            c,
          ],
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.title,
    this.subtitle,
    this.icon,
    this.color,
    this.leading,
    this.trailing,
    this.onTap,
    this.titleColor,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? color;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.primary;
    return ListTile(
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: leading ??
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: c, size: 22),
          ),
      title: Text(title, style: context.text.titleMedium?.copyWith(color: titleColor)),
      subtitle: subtitle == null ? null : Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailing ?? (onTap == null ? null : Icon(Icons.chevron_right_rounded, color: context.colors.onSurfaceVariant)),
    );
  }
}

class _AppearanceCard extends ConsumerWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceProvider);
    final ctrl = ref.read(appearanceProvider.notifier);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Mavzu', style: context.text.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final (mode, label, icon) in const [
                  (ThemeMode.light, "Yorug'", Icons.light_mode_rounded),
                  (ThemeMode.dark, "Qorong'i", Icons.dark_mode_rounded),
                  (ThemeMode.system, 'Tizim', Icons.brightness_auto_rounded),
                ]) ...[
                  Expanded(
                    child: _ThemeOption(
                      mode: mode,
                      label: label,
                      icon: icon,
                      selected: appearance.mode == mode,
                      onTap: () => ctrl.setMode(mode),
                    ),
                  ),
                  if (mode != ThemeMode.system) const SizedBox(width: 10),
                ],
              ],
            ),
            const SizedBox(height: 20),
            Text('Asosiy rang', style: context.text.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final accent in AccentColor.values)
                  Semantics(
                    label: accent.label,
                    selected: accent == appearance.accent,
                    button: true,
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        ctrl.setAccent(accent);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color.lerp(accent.color, Colors.white, 0.25)!, accent.color],
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: accent == appearance.accent ? context.colors.onSurface : Colors.transparent,
                            width: 3,
                          ),
                          boxShadow: [BoxShadow(color: accent.color.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 3))],
                        ),
                        child: accent == appearance.accent ? const Icon(Icons.check_rounded, color: Colors.white) : null,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Tema tanlovi: kichik "ekran" ko'rinishi bilan
class _ThemeOption extends StatelessWidget {
  const _ThemeOption({required this.mode, required this.label, required this.icon, required this.selected, required this.onTap});

  final ThemeMode mode;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = context.colors.primary;
    final (bg, fg) = switch (mode) {
      ThemeMode.light => (Palette.slate50, Palette.slate900),
      ThemeMode.dark => (Palette.slate900, Palette.slate50),
      ThemeMode.system => (Palette.slate500, Colors.white),
    };
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.md + 2),
          border: Border.all(color: selected ? primary : context.colors.outlineVariant, width: selected ? 2.2 : 1),
        ),
        child: Column(
          children: [
            Container(
              height: 60,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(Radii.sm),
                gradient: mode == ThemeMode.system
                    ? const LinearGradient(colors: [Palette.slate50, Palette.slate50, Palette.slate900, Palette.slate900], stops: [0, 0.5, 0.5, 1])
                    : null,
              ),
              child: Center(child: Icon(icon, color: mode == ThemeMode.system ? primary : fg)),
            ),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontWeight: selected ? FontWeight.w800 : FontWeight.w500, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

/// Bildirishnoma turlari (qurilmada saqlanadi; push ulangach serverga yuboriladi)
class _NotificationsCard extends ConsumerStatefulWidget {
  const _NotificationsCard();

  @override
  ConsumerState<_NotificationsCard> createState() => _NotificationsCardState();
}

class _NotificationsCardState extends ConsumerState<_NotificationsCard> {
  static const _items = [
    ('notif_new_task', 'Yangi vazifa', Icons.assignment_rounded),
    ('notif_grade', 'Baho chiqqanda', Icons.star_rounded),
    ('notif_deadline', 'Muddat yaqinlashganda', Icons.alarm_rounded),
    ('notif_rank', 'Reytingdagi o\'zgarishlar', Icons.emoji_events_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(sharedPrefsProvider);
    return Card(
      child: Column(
        children: [
          for (final (i, (key, label, icon)) in _items.indexed) ...[
            if (i > 0) const Divider(height: 1, indent: 68),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              secondary: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: context.colors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: context.colors.primary, size: 22),
              ),
              title: Text(label, style: context.text.titleMedium),
              value: prefs.getBool(key) ?? true,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                prefs.setBool(key, v);
                setState(() {});
              },
            ),
          ],
        ],
      ),
    );
  }
}
