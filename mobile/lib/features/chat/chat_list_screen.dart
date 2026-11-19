import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/motion.dart';
import '../auth/application/auth_controller.dart';
import '../groups/data/groups_repository.dart';
import 'chat_repository.dart';

/// Suhbatlar ro'yxati. O'quvchida — tepada ustozlari (bir bosishda yozish), ustozda — bo'sh bo'lsa
/// qanday boshlash kerakligi aytiladi.
class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(chatListProvider);
    final me = ref.watch(currentUserProvider);
    final isStudent = me?.isStudent ?? false;
    final list = async.value;

    Future<void> refresh() async {
      ref.invalidate(chatListProvider);
      ref.invalidate(chatUnreadProvider);
      await ref.read(chatListProvider.future);
    }

    Future<void> open(String path) async {
      await context.push(path);
      // Qaytganda o'qilganlar va yangi xabarlar ko'rinsin
      ref.invalidate(chatListProvider);
      ref.invalidate(chatUnreadProvider);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Xabarlar')),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: list == null
            ? (async.hasError
                ? ListView(children: [ErrorRetry(error: async.error!, onRetry: refresh)])
                : const SkeletonList(count: 5))
            : ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  if (isStudent) _MyTeachers(onOpen: (id) => open('/chat/with/$id')),
                  if (list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: EmptyState(
                        icon: Icons.forum_rounded,
                        title: "Hali xabar yo'q",
                        message: isStudent
                            ? "Savolingiz bo'lsa, yuqoridagi ustozingizni tanlab yozing."
                            : "O'quvchi profiliga kirib «Xabar yozish» tugmasini bosing.",
                      ),
                    )
                  else ...[
                    if (isStudent)
                      Padding(
                        padding: Insets.screen.copyWith(top: 8, bottom: 6),
                        child: Text('Suhbatlar', style: context.text.titleMedium),
                      ),
                    for (final (i, c) in list.indexed)
                      FadeSlideIn(index: i, child: _ConversationTile(c: c, onTap: () => open('/chats/${c.id}'))),
                  ],
                ],
              ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.c, required this.onTap});

  final Conversation c;
  final VoidCallback onTap;

  String _when(DateTime? d) {
    if (d == null) return '';
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (d.year == yesterday.year && d.month == yesterday.month && d.day == yesterday.day) return 'Kecha';
    return '${d.day}-${uzMonths[d.month - 1].substring(0, 3)}';
  }

  @override
  Widget build(BuildContext context) {
    final unread = c.unread > 0;
    final muted = context.colors.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        child: Row(
          children: [
            Avatar(initials: c.peer.initials, imageUrl: c.peer.avatarUrl, size: 54),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.peer.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.titleMedium?.copyWith(fontWeight: unread ? FontWeight.w800 : FontWeight.w600),
                        ),
                      ),
                      Text(
                        _when(c.lastAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: unread ? context.colors.primary : muted,
                          fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (c.lastFromMe) ...[
                        Icon(
                          c.peerReadAt != null && c.lastAt != null && !c.peerReadAt!.isBefore(c.lastAt!)
                              ? Icons.done_all_rounded
                              : Icons.done_rounded,
                          size: 16,
                          color: muted,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          c.lastText ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: unread ? context.colors.onSurface : muted,
                            fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (unread) ...[
                        const SizedBox(width: 8),
                        Container(
                          constraints: const BoxConstraints(minWidth: 22),
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: context.colors.primary, borderRadius: BorderRadius.circular(100)),
                          child: Text(
                            c.unread > 99 ? '99+' : '${c.unread}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// O'quvchi uchun: ustozlari gorizontal qatorda — bir bosishda yozish
class _MyTeachers extends ConsumerWidget {
  const _MyTeachers({required this.onOpen});

  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ms = ref.watch(membershipsProvider).value ?? const [];
    // Bir ustozning bir nechta guruhi bo'lishi mumkin — har ustoz bir marta
    final seen = <String>{};
    final teachers = [
      for (final m in ms)
        if (!m.isPending && m.teacherId.isNotEmpty && seen.add(m.teacherId)) m,
    ];
    if (teachers.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: Insets.screen.copyWith(bottom: 10),
            child: Text('Ustozlarim', style: context.text.titleMedium),
          ),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: Insets.screen,
              itemCount: teachers.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, i) {
                final m = teachers[i];
                final initials = m.teacherName.split(' ').where((p) => p.isNotEmpty).map((p) => p[0]).take(2).join();
                return Pressable(
                  onTap: () => onOpen(m.teacherId),
                  child: GestureDetector(
                    onTap: () => onOpen(m.teacherId),
                    child: SizedBox(
                      width: 76,
                      child: Column(
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Avatar(initials: initials, imageUrl: m.teacherAvatarUrl, size: 60),
                              Positioned(
                                right: -2,
                                bottom: -2,
                                child: Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: context.colors.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                                  ),
                                  child: const Icon(Icons.edit_rounded, size: 12, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            m.teacherName.split(' ').first,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.colors.onSurface),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Sarlavhalardagi chat tugmasi: o'qilmagan xabarlar soni belgisi bilan
class ChatButton extends ConsumerWidget {
  const ChatButton({super.key, this.onDark = false});

  final bool onDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(chatUnreadProvider).value ?? 0;
    final c = onDark ? Colors.white : context.colors.onSurface;
    return Semantics(
      button: true,
      label: unread > 0 ? 'Xabarlar, $unread ta yangi' : 'Xabarlar',
      child: Pressable(
        onTap: () => context.push('/chats'),
        child: Material(
          color: onDark ? Colors.white.withValues(alpha: 0.16) : context.colors.surfaceContainer,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () async {
              await context.push('/chats');
              ref.invalidate(chatUnreadProvider);
            },
            child: SizedBox.square(
              dimension: 46,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline_rounded, color: c, size: 22),
                  if (unread > 0)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 18),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: context.appColors.danger,
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 1.5),
                        ),
                        child: Text(
                          unread > 9 ? '9+' : '$unread',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
