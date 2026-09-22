import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../data/assignment_models.dart';
import '../../data/assignments_repository.dart';

/// Guruh sahifasidagi "Vazifalar" bloki: oxirgi vazifalar va "Vazifa berish" tugmasi.
class GroupAssignmentsSection extends ConsumerWidget {
  const GroupAssignmentsSection({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(groupAssignmentsProvider(groupId)).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Vazifalar', style: context.text.titleLarge)),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
              onPressed: () => context.push('/teacher/groups/$groupId/assignments/new'),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Vazifa berish'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (list == null)
          const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
        else if (list.isEmpty)
          Text(
            "Hali vazifa berilmagan. Kitobdan sahifa ko'rsating, misol rasmini yuklang yoki matn bilan yozing.",
            style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
          )
        else
          Card(
            child: Column(
              children: [
                for (final (i, a) in list.take(10).indexed) ...[
                  if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                  _AssignmentTile(a: a),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _AssignmentTile extends StatelessWidget {
  const _AssignmentTile({required this.a});

  final Assignment a;

  @override
  Widget build(BuildContext context) {
    final stats = a.stats;
    final (StatusTone tone, String label) = switch (a.status) {
      AssignmentStatus.preparing => (StatusTone.info, 'AI tayyorlamoqda'),
      AssignmentStatus.review => (StatusTone.warning, 'Tasdiqlang'),
      AssignmentStatus.failed => (StatusTone.danger, 'Xato'),
      AssignmentStatus.published => (
          (stats?.needsReview ?? 0) > 0 ? StatusTone.warning : StatusTone.success,
          (stats?.needsReview ?? 0) > 0
              ? '${stats!.needsReview} tekshirish'
              : '${stats?.submitted ?? 0}/${stats?.members ?? 0}',
        ),
    };
    final icon = switch (a.sourceType) {
      SourceType.book => Icons.menu_book_rounded,
      SourceType.images => Icons.photo_rounded,
      SourceType.text => Icons.edit_note_rounded,
    };
    return ListTile(
      onTap: () => context.push('/teacher/assignments/${a.id}'),
      leading: Icon(icon, color: context.colors.primary),
      title: Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleMedium),
      subtitle: Text(
        formatDueUz(a.dueAt),
        style: TextStyle(color: a.dueAt.isBefore(DateTime.now()) ? context.appColors.muted : null),
      ),
      trailing: StatusChip(label: label, tone: tone),
    );
  }
}
