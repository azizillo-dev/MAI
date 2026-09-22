import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../auth/application/auth_controller.dart';
import '../../groups/data/groups_repository.dart';
import '../data/gamification_models.dart';

const _gold = Color(0xFFF5B301);
const _silver = Color(0xFF9AA8BD);
const _bronze = Color(0xFFD9772B);

/// Reyting: o'quvchi o'z guruhidagi yoki ustozining barcha o'quvchilari orasidagi o'rnini ko'radi.
class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key, this.groupId, this.embedded = false});

  final String? groupId;

  /// Pastki menyu tabi ichida (orqaga tugmasi yo'q)
  final bool embedded;

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  String? _groupId;
  LeaderScope _scope = LeaderScope.group;
  LeaderPeriod _period = LeaderPeriod.month;

  /// O'quvchi: faol a'zo bo'lgan guruhlar; o'qituvchi: o'z guruhlari
  List<(String, String)> _groups() {
    final me = ref.watch(currentUserProvider);
    if (me?.isTeacher ?? false) {
      return [for (final g in ref.watch(teacherGroupsProvider).value ?? const []) (g.id, g.name)];
    }
    return [
      for (final m in ref.watch(membershipsProvider).value ?? const [])
        if (!m.isPending) (m.groupId, m.groupName),
    ];
  }

  Future<void> _openFilter(List<(String, String)> groups) async {
    final result = await showModalBottomSheet<(String?, LeaderScope, LeaderPeriod)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FilterSheet(groupId: _groupId, scope: _scope, period: _period, groups: groups),
    );
    if (result case (final g, final scope, final period)) {
      setState(() {
        _groupId = g;
        _scope = scope;
        _period = period;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups();
    final groupId = _groupId ?? widget.groupId ?? groups.firstOrNull?.$1;
    final isTeacher = ref.watch(currentUserProvider)?.isTeacher ?? false;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        title: const Text('Reyting'),
        actions: [
          if (groupId != null)
            IconButton(
              tooltip: 'Filtr',
              icon: const Icon(Icons.tune_rounded),
              onPressed: () => _openFilter(groups),
            ),
        ],
      ),
      body: groupId == null
          ? const Center(
              child: EmptyState(
                icon: Icons.emoji_events_rounded,
                title: "Reyting hali yo'q",
                message: "Guruhga qo'shilganingizdan keyin shu yerda o'rningizni ko'rasiz.",
              ),
            )
          : _Board(
              query: (groupId: groupId, scope: _scope, period: _period),
              showMe: !isTeacher,
              onFilter: () => _openFilter(groups),
            ),
    );
  }
}

class _Board extends ConsumerWidget {
  const _Board({required this.query, required this.showMe, required this.onFilter});

  final LeaderQuery query;
  final bool showMe;
  final VoidCallback onFilter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(leaderboardProvider(query));
    final b = async.value;
    if (b == null) {
      return async.hasError
          ? ErrorRetry(error: async.error!, onRetry: () => ref.invalidate(leaderboardProvider(query)))
          : const Center(child: CircularProgressIndicator());
    }
    final top = b.entries.take(3).toList();
    final rest = b.entries.skip(3).toList();
    final me = b.me;
    final meBelow = showMe && me != null && me.rank > 3;

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(leaderboardProvider(query));
            await ref.read(leaderboardProvider(query).future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: Insets.screen.copyWith(top: 0, bottom: meBelow ? 110 : 32),
            children: [
              Center(
                child: ActionChip(
                  avatar: const Icon(Icons.filter_list_rounded, size: 18),
                  label: Text(
                    '${query.scope == LeaderScope.group ? b.groupName : '${b.teacherName} o\'quvchilari'} · ${query.period.label}',
                  ),
                  onPressed: onFilter,
                ),
              ),
              const SizedBox(height: 12),
              if (b.entries.isEmpty)
                const EmptyState(
                  icon: Icons.emoji_events_rounded,
                  title: "Hali ball yo'q",
                  message: 'Vazifalar baholangach, reyting shu yerda paydo bo\'ladi.',
                )
              else ...[
                _Podium(top: top, meId: me?.studentId),
                const SizedBox(height: 18),
                for (final e in rest) ...[
                  _Row(entry: e, isMe: e.studentId == me?.studentId),
                  const SizedBox(height: 8),
                ],
              ],
            ],
          ),
        ),
        if (meBelow)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: SafeArea(top: false, child: _Row(entry: me, isMe: true, elevated: true)),
          ),
      ],
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({required this.top, this.meId});

  final List<LeaderEntry> top;
  final String? meId;

  @override
  Widget build(BuildContext context) {
    LeaderEntry? at(int i) => i < top.length ? top[i] : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: _PodiumSpot(entry: at(1), place: 2, size: 84, color: _silver, isMe: at(1)?.studentId == meId)),
        Expanded(child: _PodiumSpot(entry: at(0), place: 1, size: 108, color: _gold, isMe: at(0)?.studentId == meId)),
        Expanded(child: _PodiumSpot(entry: at(2), place: 3, size: 84, color: _bronze, isMe: at(2)?.studentId == meId)),
      ],
    );
  }
}

class _PodiumSpot extends StatelessWidget {
  const _PodiumSpot({required this.entry, required this.place, required this.size, required this.color, required this.isMe});

  final LeaderEntry? entry;
  final int place;
  final double size;
  final Color color;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    if (e == null) return const SizedBox.shrink();
    final spot = TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 450 + place * 120),
      curve: Curves.easeOutBack,
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0, 1),
        child: Transform.translate(offset: Offset(0, (1 - v) * 24), child: child),
      ),
      child: Column(
        children: [
          if (place == 1)
            Icon(Icons.workspace_premium_rounded, color: color, size: 34)
          else
            Text('$place', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 4),
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 18, offset: const Offset(0, 6))],
                ),
                child: Avatar(initials: e.initials, imageUrl: e.avatarUrl, size: size, ring: color, color: color),
              ),
              Positioned(bottom: -12, child: _PointsPill(points: e.points, color: color)),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            e.name.split(' ').first,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.titleMedium?.copyWith(
              color: isMe ? context.colors.primary : null,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/students/${e.studentId}'),
      child: spot,
    );
  }
}

class _PointsPill extends StatelessWidget {
  const _PointsPill({required this.points, required this.color});

  final int points;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: context.colors.surface, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 15, color: Colors.white),
          const SizedBox(width: 3),
          Text('$points', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5)),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.entry, required this.isMe, this.elevated = false});

  final LeaderEntry entry;
  final bool isMe;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final primary = context.colors.primary;
    final rankColor = entry.rank <= 6 ? Palette.warning : context.appColors.danger;
    final row = Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      decoration: BoxDecoration(
        color: isMe ? Color.lerp(context.colors.surface, primary, 0.08) : context.colors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: isMe ? primary.withValues(alpha: 0.6) : context.colors.outlineVariant, width: isMe ? 1.6 : 1),
        boxShadow: elevated ? [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 20, offset: const Offset(0, 8))] : null,
      ),
      child: Row(
        children: [
          Avatar(initials: entry.initials, imageUrl: entry.avatarUrl, size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMe ? '${entry.name} (siz)' : entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleMedium,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: rankColor, borderRadius: BorderRadius.circular(100)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded, size: 14, color: Colors.white),
                          const SizedBox(width: 3),
                          Text('${entry.points}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${entry.level}-daraja', style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: rankColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
            child: Text('${entry.rank}-o\'rin', style: TextStyle(color: rankColor, fontWeight: FontWeight.w800, fontSize: 13)),
          ),
        ],
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/students/${entry.studentId}'),
      child: row,
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.groupId, required this.scope, required this.period, required this.groups});

  final String? groupId;
  final LeaderScope scope;
  final LeaderPeriod period;
  final List<(String, String)> groups;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String? _groupId = widget.groupId ?? widget.groups.firstOrNull?.$1;
  late LeaderScope _scope = widget.scope;
  late LeaderPeriod _period = widget.period;

  Widget _option(String label, bool selected, VoidCallback onTap) {
    final primary = context.colors.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? primary : context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Radii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.md),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : context.colors.onSurface,
                    ),
                  ),
                ),
                Icon(
                  selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: selected ? Colors.white : context.colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const SizedBox(width: 64),
                Expanded(child: Text('Filtr', textAlign: TextAlign.center, style: context.text.titleLarge)),
                SizedBox(
                  width: 64,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, (_groupId, _scope, _period)),
                    child: const Text('Saqlash'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final p in LeaderPeriod.values) _option(p.label, _period == p, () => setState(() => _period = p)),
            const SizedBox(height: 12),
            _option('Guruhim', _scope == LeaderScope.group, () => setState(() => _scope = LeaderScope.group)),
            _option("Ustozimning barcha o'quvchilari", _scope == LeaderScope.teacher,
                () => setState(() => _scope = LeaderScope.teacher)),
            if (widget.groups.length > 1) ...[
              const SizedBox(height: 12),
              Text('Guruh', style: context.text.titleMedium),
              const SizedBox(height: 8),
              for (final (id, name) in widget.groups) _option(name, _groupId == id, () => setState(() => _groupId = id)),
            ],
          ],
        ),
      ),
    );
  }
}
