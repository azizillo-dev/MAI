import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../assignments/data/assignments_repository.dart';
import '../../groups/data/group_models.dart';
import '../../assignments/presentation/teacher/group_assignments_section.dart';
import '../../groups/data/groups_repository.dart';

class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({super.key, required this.groupId, this.justCreated = false});

  final String groupId;
  final bool justCreated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(teacherGroupProvider(groupId));
    final members = ref.watch(groupMembersProvider(groupId));

    Future<void> refresh() async {
      ref.invalidate(teacherGroupProvider(groupId));
      ref.invalidate(groupMembersProvider(groupId));
      ref.invalidate(groupAssignmentsProvider(groupId));
      await ref.read(groupMembersProvider(groupId).future);
    }

    // Yangilanayotganda ham eski ma'lumot ko'rinib turadi (ekran "sakramaydi")
    final g = group.value;

    return Scaffold(
      appBar: AppBar(
        title: Text(g?.name ?? ''),
        actions: [
          if (g != null)
            IconButton(
              tooltip: 'Guruh sozlamalari',
              icon: const Icon(Icons.tune_rounded),
              onPressed: () => _showSettings(context, ref, g),
            ),
        ],
      ),
      body: g == null
          ? (group.hasError
              ? ErrorRetry(error: group.error!, onRetry: refresh)
              : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(
              onRefresh: refresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: Insets.screen.copyWith(top: 4),
                    sliver: SliverList.list(
                      children: [
                        if (justCreated) ...[
                          const InfoBanner(
                            tone: StatusTone.success,
                            title: 'Guruh yaratildi!',
                            text: "Endi o'quvchilarga kod va parolni bering yoki QR kodni ko'rsating.",
                          ),
                          const SizedBox(height: 14),
                        ],
                        _InviteCard(group: g),
                        const SizedBox(height: 24),
                        GroupAssignmentsSection(groupId: g.id),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                  ..._membersSlivers(context, g, members, refresh),
                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                ],
              ),
            ),
    );
  }

  List<Widget> _membersSlivers(
    BuildContext context,
    TeacherGroup group,
    AsyncValue<List<GroupMember>> members,
    Future<void> Function() refresh,
  ) {
    final list = members.value;
    if (list == null) {
      return [
        SliverToBoxAdapter(
          child: members.hasError
              ? ErrorRetry(error: members.error!, onRetry: refresh)
              : const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
        ),
      ];
    }
    final pending = list.where((m) => m.isPending).toList();
    final active = list.where((m) => !m.isPending).toList();
    return [
      if (pending.isNotEmpty) ...[
        SliverToBoxAdapter(child: _PendingHeader(group: group, count: pending.length)),
        SliverList.builder(
          itemCount: pending.length,
          itemBuilder: (_, i) => _MemberTile(key: ValueKey(pending[i].studentId), group: group, member: pending[i]),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
      _header(context, "O'quvchilar", active.length, null),
      if (active.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: Insets.screen,
            child: Text(
              "Hali hech kim qo'shilmagan. Kod va parolni o'quvchilarga yuboring.",
              style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          ),
        )
      else
        SliverList.builder(
          itemCount: active.length,
          itemBuilder: (_, i) => _MemberTile(key: ValueKey(active[i].studentId), group: group, member: active[i]),
        ),
    ];
  }

  Widget _header(BuildContext context, String title, int count, Color? color) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: Insets.screen.copyWith(bottom: 8),
        child: Row(
          children: [
            Text(title, style: context.text.titleLarge?.copyWith(color: color)),
            const SizedBox(width: 8),
            StatusChip(label: '$count', tone: color == null ? StatusTone.neutral : StatusTone.warning),
          ],
        ),
      ),
    );
  }

  Future<void> _showSettings(BuildContext context, WidgetRef ref, TeacherGroup g) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _GroupSettingsSheet(group: g),
    );
  }
}

class _PendingHeader extends ConsumerStatefulWidget {
  const _PendingHeader({required this.group, required this.count});

  final TeacherGroup group;
  final int count;

  @override
  ConsumerState<_PendingHeader> createState() => _PendingHeaderState();
}

class _PendingHeaderState extends ConsumerState<_PendingHeader> {
  bool _busy = false;

  Future<void> _approveAll() async {
    final ok = await confirmDialog(
      context,
      title: 'Hammasini qabul qilasizmi?',
      message: "${widget.count} ta o'quvchi guruhga qo'shiladi. Tanimagan odam bo'lsa, avval uni rad eting.",
      confirmLabel: 'Qabul qilish',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      final (approved, left) = await ref.read(groupsRepositoryProvider).approveAll(widget.group.id);
      HapticFeedback.mediumImpact();
      ref.invalidate(groupMembersProvider(widget.group.id));
      ref.invalidate(teacherGroupProvider(widget.group.id));
      ref.invalidate(teacherGroupsProvider);
      ref.invalidate(planUsageProvider);
      if (!mounted) return;
      showSnack(
        context,
        left == 0
            ? "$approved ta o'quvchi qabul qilindi"
            : "$approved ta qabul qilindi. Tarif limiti tufayli $left tasi kutishda qoldi",
        error: left > 0,
      );
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: Insets.screen.copyWith(bottom: 4),
      child: Row(
        children: [
          Flexible(
            child: Text(
              'Tasdiqlash kutilmoqda',
              style: context.text.titleLarge?.copyWith(color: context.appColors.warning),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          StatusChip(label: '${widget.count}', tone: StatusTone.warning),
          const Spacer(),
          if (widget.count > 1)
            _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
                : TextButton(onPressed: _approveAll, child: const Text('Hammasi')),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Taklif kartasi

class _InviteCard extends ConsumerStatefulWidget {
  const _InviteCard({required this.group});

  final TeacherGroup group;

  @override
  ConsumerState<_InviteCard> createState() => _InviteCardState();
}

class _InviteCardState extends ConsumerState<_InviteCard> {
  bool _showPassword = false;
  bool _rotating = false;
  bool _toggling = false;

  TeacherGroup get g => widget.group;

  void _copy(String value, String what) {
    Clipboard.setData(ClipboardData(text: value));
    HapticFeedback.selectionClick();
    showSnack(context, '$what nusxalandi');
  }

  String get _shareText => '📚 «${g.name}» guruhiga qo\'shiling!\n\n'
      '1) Mentor AI ilovasini o\'rnating\n'
      '2) «Guruhga qo\'shilish» tugmasini bosing\n'
      '3) Kod: ${g.joinCode}\n'
      '    Parol: ${g.passwordPretty}\n\n'
      'Yoki shu havolani bosing:\n${g.inviteUrl}\n\n'
      'So\'rovingizni ustoz tasdiqlagach guruhga kirasiz.';

  Future<void> _share() async {
    await SharePlus.instance.share(ShareParams(text: _shareText, subject: g.name));
  }

  Future<void> _rotate() async {
    final ok = await confirmDialog(
      context,
      title: 'Parolni yangilaysizmi?',
      message: "Eski parol, QR kod va havola darhol ishlamay qoladi. Guruhdagi o'quvchilar guruhda qoladi.",
      confirmLabel: 'Yangilash',
    );
    if (!ok) return;
    setState(() => _rotating = true);
    try {
      await ref.read(groupsRepositoryProvider).rotateCredentials(g.id);
      ref.invalidate(teacherGroupProvider(g.id));
      ref.invalidate(teacherGroupsProvider);
      if (mounted) showSnack(context, 'Yangi parol yaratildi');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _rotating = false);
    }
  }

  void _showQr() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _QrSheet(group: g),
    );
  }

  Future<void> _toggleJoin(bool enabled) async {
    if (!enabled) {
      final ok = await confirmDialog(
        context,
        title: "Qo'shilishni yopasizmi?",
        message: "Kod, parol, QR va havola ishlamay qoladi. Guruhdagi o'quvchilar guruhda qoladi. "
            "Yangi o'quvchi kerak bo'lsa, istalgan vaqtda qayta ochasiz.",
        confirmLabel: 'Yopish',
      );
      if (!ok) return;
    }
    setState(() => _toggling = true);
    try {
      await ref.read(groupsRepositoryProvider).setJoinEnabled(g.id, enabled);
      HapticFeedback.mediumImpact();
      ref.invalidate(teacherGroupProvider(g.id));
      ref.invalidate(teacherGroupsProvider);
      if (mounted) showSnack(context, enabled ? "Qo'shilish ochildi" : "Qo'shilish yopildi");
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final open = g.joinEnabled;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(open ? Icons.lock_open_rounded : Icons.lock_rounded,
                    color: open ? context.appColors.success : context.colors.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Guruhga qo'shilish", style: context.text.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        open ? "Ochiq — o'quvchilar so'rov yubora oladi" : 'Yopiq — kod va QR ishlamaydi',
                        style: context.text.bodySmall?.copyWith(
                          color: open ? context.appColors.success : context.colors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_toggling)
                  const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4)),
                  )
                else
                  Switch(value: open, onChanged: _toggleJoin),
              ],
            ),
            // Yopiq bo'lsa kod/parol yashiriladi: ekranni ko'rgan begona odam ham ko'chirib ololmaydi
            AnimatedSize(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: open ? _openBody(context) : _closedBody(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _closedBody(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, right: 6),
      child: Text(
        g.membersActive > 0
            ? "Hamma qo'shilib bo'lgan bo'lsa, shunday qoldiring. Yangi o'quvchi kerak bo'lganda ochib qo'ying."
            : "O'quvchilarni taklif qilish uchun qo'shilishni oching.",
        style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
      ),
    );
  }

  Widget _openBody(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, right: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CredentialBox(
            label: 'Guruh kodi',
            value: g.joinCode,
            onCopy: () => _copy(g.joinCode, 'Kod'),
          ),
          const SizedBox(height: 10),
          _CredentialBox(
            label: 'Parol',
            value: _showPassword ? g.passwordPretty : '•••• ••••',
            onCopy: () => _copy(g.joinPassword, 'Parol'),
            trailing: IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: _showPassword ? 'Yashirish' : "Ko'rsatish",
              onPressed: () => setState(() => _showPassword = !_showPassword),
              icon: Icon(_showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _share,
                  icon: const Icon(Icons.send_rounded, size: 20),
                  label: const Text('Ulashish'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showQr,
                  icon: const Icon(Icons.qr_code_2_rounded, size: 22),
                  label: const Text('QR kod'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _rotating ? null : _rotate,
              icon: _rotating
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('Parolni yangilash'),
            ),
          ),
          Text(
            "Har bir so'rovni siz tasdiqlaysiz. Hamma qo'shilgach, qo'shilishni yopib qo'ying.",
            style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _CredentialBox extends StatelessWidget {
  const _CredentialBox({required this.label, required this.value, required this.onCopy, this.trailing});

  final String label;
  final String value;
  final VoidCallback onCopy;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(Radii.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onCopy,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(label, style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
                  const Spacer(),
                  if (trailing != null)
                    SizedBox(height: 24, child: trailing)
                  else
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Icon(Icons.copy_rounded, size: 16, color: context.colors.onSurfaceVariant),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrSheet extends StatelessWidget {
  const _QrSheet({required this.group});

  final TeacherGroup group;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(group.name, style: context.text.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              "O'quvchilar ilovadagi «QR skanerlash» orqali qo'shiladi",
              textAlign: TextAlign.center,
              style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                // QR doim oq fonda: qorong'i temada ham kamera yaxshi o'qiydi
                color: Colors.white,
                borderRadius: BorderRadius.circular(Radii.lg),
              ),
              child: QrImageView(
                data: group.inviteUrl,
                size: 240,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Palette.slate900),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Palette.slate900,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              group.joinCode,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 3),
            ),
            const SizedBox(height: 4),
            Text(
              'Parol: ${group.passwordPretty}',
              style: context.text.titleMedium?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- A'zolar

class _MemberTile extends ConsumerStatefulWidget {
  const _MemberTile({super.key, required this.group, required this.member});

  final TeacherGroup group;
  final GroupMember member;

  @override
  ConsumerState<_MemberTile> createState() => _MemberTileState();
}

class _MemberTileState extends ConsumerState<_MemberTile> {
  bool _busy = false;

  GroupMember get m => widget.member;

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(groupMembersProvider(widget.group.id));
      ref.invalidate(teacherGroupProvider(widget.group.id));
      ref.invalidate(teacherGroupsProvider);
      ref.invalidate(planUsageProvider);
      if (mounted) showSnack(context, success);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decide(String action) {
    final repo = ref.read(groupsRepositoryProvider);
    final message = switch (action) {
      'approve' => "${m.firstName} guruhga qo'shildi",
      'reject' => "So'rov rad etildi",
      _ => "${m.firstName} guruhdan chiqarildi",
    };
    return _run(() => repo.decide(widget.group.id, m.studentId, action), message);
  }

  Future<void> _menu(String value) async {
    switch (value) {
      case 'grant':
        final ok = await confirmDialog(
          context,
          title: 'Tahrirlashga ruxsat',
          message: "${m.fullName} o'z ma'lumotlarini (ism, familiya, tug'ilgan sana) bir marta o'zgartira oladi. "
              'Ruxsat 7 kun amal qiladi.',
          confirmLabel: 'Ruxsat berish',
        );
        if (ok) {
          await _run(
            () => ref.read(groupsRepositoryProvider).grantProfileEdit(widget.group.id, m.studentId),
            'Ruxsat berildi',
          );
        }
      case 'remove':
        final ok = await confirmDialog(
          context,
          title: 'Guruhdan chiqarilsinmi?',
          message: "${m.fullName} guruhdan chiqariladi. Keyin kod va parol bilan qayta qo'shilishi mumkin.",
          confirmLabel: 'Chiqarish',
          destructive: true,
        );
        if (ok) await _decide('remove');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: () => context.push('/students/${m.studentId}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Avatar(initials: m.initials, imageUrl: m.avatarUrl, color: m.isPending ? context.appColors.warning : null),
      title: Text(m.fullName, style: context.text.titleMedium),
      subtitle: Text(
        m.isPending ? "So'rov: ${formatDateUz(m.requestedAt.toLocal())}" : m.contact,
        style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
      ),
      trailing: _busy
          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4))
          : m.isPending
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'Rad etish',
                      onPressed: () => _decide('reject'),
                      icon: Icon(Icons.close_rounded, color: context.appColors.danger),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filled(
                      tooltip: 'Qabul qilish',
                      style: IconButton.styleFrom(backgroundColor: context.appColors.success),
                      onPressed: () => _decide('approve'),
                      icon: const Icon(Icons.check_rounded, color: Colors.white),
                    ),
                  ],
                )
              : PopupMenuButton<String>(
                  onSelected: _menu,
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'grant',
                      child: ListTile(
                        leading: Icon(Icons.edit_note_rounded),
                        title: Text("Ma'lumotlarini tahrirlashga ruxsat"),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'remove',
                      child: ListTile(
                        leading: Icon(Icons.person_remove_rounded),
                        title: Text('Guruhdan chiqarish'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
    );
  }
}

// ---------------------------------------------------------------- Sozlamalar

class _GroupSettingsSheet extends ConsumerStatefulWidget {
  const _GroupSettingsSheet({required this.group});

  final TeacherGroup group;

  @override
  ConsumerState<_GroupSettingsSheet> createState() => _GroupSettingsSheetState();
}

class _GroupSettingsSheetState extends ConsumerState<_GroupSettingsSheet> {
  late final _name = TextEditingController(text: widget.group.name);
  late String _scale = widget.group.gradingScale;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(groupsRepositoryProvider).update(
            widget.group.id,
            name: _name.text.trim() == widget.group.name ? null : _name.text.trim(),
            gradingScale: _scale,
          );
      ref.invalidate(teacherGroupProvider(widget.group.id));
      ref.invalidate(teacherGroupsProvider);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Guruh sozlamalari', style: context.text.titleLarge),
            const SizedBox(height: 18),
            TextField(
              controller: _name,
              maxLength: 40,
              decoration: const InputDecoration(labelText: 'Guruh nomi', counterText: ''),
            ),
            const SizedBox(height: 18),
            Text('Baholash tizimi', style: context.text.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: '5', label: Text('5 ball')),
                ButtonSegment(value: '10', label: Text('10 ball')),
                ButtonSegment(value: '100', label: Text('100 ball')),
              ],
              selected: {_scale},
              onSelectionChanged: (s) => setState(() => _scale = s.first),
            ),
            const SizedBox(height: 24),
            PrimaryButton(label: 'Saqlash', loading: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
