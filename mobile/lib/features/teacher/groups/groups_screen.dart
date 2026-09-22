import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../groups/data/group_models.dart';
import '../../groups/data/groups_repository.dart';
import 'create_group_sheet.dart';

class TeacherGroupsScreen extends ConsumerWidget {
  const TeacherGroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(teacherGroupsProvider);

    Future<void> refresh() async {
      ref.invalidate(teacherGroupsProvider);
      await ref.read(teacherGroupsProvider.future);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Guruhlar')),
      floatingActionButton: groups.hasValue && groups.value!.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => showCreateGroupSheet(context, ref),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Yangi guruh'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: refresh,
        child: switch (groups) {
          AsyncData(value: final list) when list.isEmpty => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 60),
                EmptyState(
                  icon: Icons.groups_rounded,
                  title: "Hali guruh yo'q",
                  message: "Guruh yarating — o'quvchilar kod va parol orqali qo'shiladi.",
                  actionLabel: 'Guruh yaratish',
                  actionIcon: Icons.add_rounded,
                  onAction: () => showCreateGroupSheet(context, ref),
                ),
              ],
            ),
          AsyncData(value: final list) => ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: Insets.screen.copyWith(top: 8, bottom: 96),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) => GroupCard(group: list[i]),
            ),
          AsyncError(:final error) => ListView(
              children: [ErrorRetry(error: error, onRetry: refresh)],
            ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class GroupCard extends StatelessWidget {
  const GroupCard({super.key, required this.group});

  final TeacherGroup group;

  @override
  Widget build(BuildContext context) {
    final isMath = group.subject == 'math';
    final color = isMath ? context.colors.primary : Palette.success;
    return SectionCard(
      onTap: () => context.push('/teacher/groups/${group.id}'),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(15)),
            child: Icon(isMath ? Icons.calculate_rounded : Icons.translate_rounded, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(group.name, style: context.text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Text(
                  "${subjectLabel(group.subject)} · ${group.membersActive} o'quvchi",
                  style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (group.membersPending > 0)
            StatusChip(
              label: '+${group.membersPending}',
              tone: StatusTone.warning,
              icon: Icons.person_add_alt_1_rounded,
            )
          else
            Icon(Icons.chevron_right_rounded, color: context.colors.onSurfaceVariant),
        ],
      ),
    );
  }
}
