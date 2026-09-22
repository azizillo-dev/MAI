import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../data/assignment_models.dart';
import '../../data/assignments_repository.dart';
import '../widgets.dart';

/// O'qituvchi uchun vazifa sahifasi. Holatga qarab: tayyorlanmoqda -> tekshirish -> nashr qilingan.
class TeacherAssignmentScreen extends ConsumerStatefulWidget {
  const TeacherAssignmentScreen({super.key, required this.assignmentId});

  final String assignmentId;

  @override
  ConsumerState<TeacherAssignmentScreen> createState() => _TeacherAssignmentScreenState();
}

class _TeacherAssignmentScreenState extends ConsumerState<TeacherAssignmentScreen> {
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// AI ishlayotganda (tayyorlash yoki baholash) har 3 soniyada yangilab turamiz
  void _schedulePoll(bool active) {
    if (active && _poll == null) {
      _poll = Timer.periodic(const Duration(seconds: 3), (_) {
        ref.invalidate(assignmentProvider(widget.assignmentId));
        ref.invalidate(assignmentSubmissionsProvider(widget.assignmentId));
      });
    } else if (!active) {
      _poll?.cancel();
      _poll = null;
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(assignmentProvider(widget.assignmentId));
    ref.invalidate(assignmentSubmissionsProvider(widget.assignmentId));
    await ref.read(assignmentProvider(widget.assignmentId).future);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(assignmentProvider(widget.assignmentId));
    final a = async.value;
    final subs = ref.watch(assignmentSubmissionsProvider(widget.assignmentId)).value ?? const [];

    final grading = subs.any((s) => s.status == SubmissionStatus.grading);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _schedulePoll(a?.status == AssignmentStatus.preparing || grading),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(a?.title ?? 'Vazifa'),
        actions: [
          if (a != null && (a.stats?.submitted ?? 0) == 0)
            IconButton(
              tooltip: "O'chirish",
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => _delete(a),
            ),
        ],
      ),
      body: a == null
          ? (async.hasError
              ? ErrorRetry(error: async.error!, onRetry: _refresh)
              : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: Insets.screen.copyWith(top: 4, bottom: 120),
                children: [
                  _Header(a: a),
                  const SizedBox(height: 16),
                  ...switch (a.status) {
                    AssignmentStatus.preparing => [const _Preparing()],
                    AssignmentStatus.failed => [_FailedBox(a: a)],
                    AssignmentStatus.review => [_ReviewContent(a: a)],
                    AssignmentStatus.published => [
                        if (a.stats != null) _StatsRow(stats: a.stats!),
                        const SizedBox(height: 18),
                        _Submissions(subs: subs),
                        const SizedBox(height: 22),
                        _ContentView(a: a),
                      ],
                  },
                ],
              ),
            ),
      bottomNavigationBar: a?.status == AssignmentStatus.review ? _PublishBar(a: a!) : null,
    );
  }

  Future<void> _delete(Assignment a) async {
    final ok = await confirmDialog(
      context,
      title: "Vazifani o'chirasizmi?",
      message: "«${a.title}» butunlay o'chiriladi.",
      confirmLabel: "O'chirish",
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(assignmentsRepositoryProvider).delete(a.id);
      ref.invalidate(groupAssignmentsProvider(a.groupId));
      if (mounted) context.pop();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.a});

  final Assignment a;

  @override
  Widget build(BuildContext context) {
    final (label, tone, icon) = switch (a.status) {
      AssignmentStatus.preparing => ('AI tayyorlamoqda', StatusTone.info, Icons.auto_awesome_rounded),
      AssignmentStatus.review => ('Tasdiqlashingiz kerak', StatusTone.warning, Icons.rate_review_rounded),
      AssignmentStatus.published => ("O'quvchilarga berilgan", StatusTone.success, Icons.check_circle_rounded),
      AssignmentStatus.failed => ('Tayyorlab bo\'lmadi', StatusTone.danger, Icons.error_outline_rounded),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            StatusChip(label: label, tone: tone, icon: icon),
            StatusChip(label: a.groupName, tone: StatusTone.neutral, icon: Icons.groups_rounded),
            StatusChip(label: formatDueUz(a.dueAt), tone: StatusTone.neutral, icon: Icons.event_rounded),
          ],
        ),
        if (a.sourceType == SourceType.book) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.menu_book_rounded, size: 18, color: context.colors.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  bookRangeLabel(bookTitle: a.book?.title, pageFrom: a.pageFrom, pageTo: a.pageTo, problems: a.problems),
                  style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
        if (a.instructions != null) ...[
          const SizedBox(height: 10),
          Text(a.instructions!, style: context.text.bodyLarge),
        ],
      ],
    );
  }
}

class _Preparing extends StatelessWidget {
  const _Preparing();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        child: Column(
          children: [
            const SizedBox(width: 44, height: 44, child: CircularProgressIndicator(strokeWidth: 3.5)),
            const SizedBox(height: 18),
            Text('AI misollarni ajratmoqda…', style: context.text.titleMedium),
            const SizedBox(height: 6),
            Text(
              "Odatda 20–60 soniya. Sahifadan chiqib ketishingiz mumkin — tayyor bo'lganda shu yerda ko'rinadi.",
              textAlign: TextAlign.center,
              style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _FailedBox extends ConsumerStatefulWidget {
  const _FailedBox({required this.a});

  final Assignment a;

  @override
  ConsumerState<_FailedBox> createState() => _FailedBoxState();
}

class _FailedBoxState extends ConsumerState<_FailedBox> {
  bool _busy = false;

  Future<void> _retry() async {
    setState(() => _busy = true);
    try {
      await ref.read(assignmentsRepositoryProvider).retry(widget.a.id);
      ref.invalidate(assignmentProvider(widget.a.id));
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoBanner(
          tone: StatusTone.danger,
          title: 'AI misollarni ajrata olmadi',
          text: widget.a.prepareError ?? 'Noma\'lum xato',
        ),
        const SizedBox(height: 14),
        PrimaryButton(label: 'Qayta urinish', icon: Icons.refresh_rounded, loading: _busy, onPressed: _retry),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => editContent(context, ref, widget.a),
          icon: const Icon(Icons.edit_rounded),
          label: Text(widget.a.sourceType == SourceType.text ? 'Mezonlarni qo\'lda yozish' : "Misollarni qo'lda kiritish"),
        ),
      ],
    );
  }
}

/// AI tayyorlagan: ustoz ko'rib chiqadi, tuzatadi, keyin nashr qiladi
class _ReviewContent extends ConsumerWidget {
  const _ReviewContent({required this.a});

  final Assignment a;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoBanner(
          tone: StatusTone.warning,
          title: a.sourceType == SourceType.text ? 'Baholash mezonlarini tekshiring' : "AI ajratgan misollarni tekshiring",
          text: a.sourceType == SourceType.text
              ? "O'quvchi ishlari shu mezonlar bo'yicha baholanadi. Kerak bo'lsa o'zgartiring."
              : "Raqam va shartlar kitobdagidek bo'lishi kerak. Xato bo'lsa, ustiga bosib tuzating.",
        ),
        if (a.prepareError != null) ...[
          const SizedBox(height: 10),
          InfoBanner(icon: Icons.sticky_note_2_outlined, title: 'AI eslatmasi', text: a.prepareError!),
        ],
        const SizedBox(height: 16),
        _ContentView(a: a, editable: true),
      ],
    );
  }
}

class _ContentView extends ConsumerWidget {
  const _ContentView({required this.a, this.editable = false});

  final Assignment a;
  final bool editable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isText = a.sourceType == SourceType.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          isText ? 'Baholash mezonlari' : 'Misollar (${a.items.length})',
          trailing: TextButton.icon(
            onPressed: () => editContent(context, ref, a),
            icon: const Icon(Icons.edit_rounded, size: 18),
            label: const Text('Tahrirlash'),
          ),
        ),
        if (a.imageUrls.isNotEmpty) ...[PhotoStrip(urls: a.imageUrls), const SizedBox(height: 12)],
        Card(
          child: Column(
            children: [
              if (isText)
                for (final (i, c) in a.rubric.indexed) ...[
                  if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    title: Text(c.name, style: context.text.titleMedium),
                    subtitle: c.description.isEmpty ? null : Text(c.description),
                    trailing: StatusChip(label: '${c.weight}%', tone: StatusTone.info),
                  ),
                ]
              else
                for (final (i, item) in a.items.indexed) ...[
                  if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundColor: context.colors.primary.withValues(alpha: 0.1),
                      child: FittedBox(
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Text(item.number, style: TextStyle(color: context.colors.primary, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                    title: Text(item.text),
                    subtitle: item.answer == null
                        ? null
                        : Text('Javob: ${item.answer}', style: TextStyle(color: context.appColors.success)),
                  ),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

Future<void> editContent(BuildContext context, WidgetRef ref, Assignment a) async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => _ContentEditor(a: a)),
  );
}

/// Misollar yoki mezonlarni tahrirlash (qo'shish, o'chirish, tartibini o'zgartirish)
class _ContentEditor extends ConsumerStatefulWidget {
  const _ContentEditor({required this.a});

  final Assignment a;

  @override
  ConsumerState<_ContentEditor> createState() => _ContentEditorState();
}

class _ContentEditorState extends ConsumerState<_ContentEditor> {
  late final bool _isText = widget.a.sourceType == SourceType.text;
  late final List<AssignmentItem> _items = [...widget.a.items];
  late final List<Criterion> _rubric = [...widget.a.rubric];
  bool _saving = false;

  int get _weightSum => _rubric.fold(0, (s, c) => s + c.weight);

  Future<void> _editItem([int? index]) async {
    final result = await showModalBottomSheet<AssignmentItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ItemSheet(item: index == null ? null : _items[index], nextNumber: _nextNumber()),
    );
    if (result == null) return;
    setState(() => index == null ? _items.add(result) : _items[index] = result);
  }

  Future<void> _editCriterion([int? index]) async {
    final result = await showModalBottomSheet<Criterion>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CriterionSheet(criterion: index == null ? null : _rubric[index]),
    );
    if (result == null) return;
    setState(() => index == null ? _rubric.add(result) : _rubric[index] = result);
  }

  String _nextNumber() {
    final last = int.tryParse(_items.isEmpty ? '0' : _items.last.number);
    return last == null ? '' : '${last + 1}';
  }

  Future<void> _save() async {
    if (_isText && _weightSum != 100) {
      showSnack(context, "Mezonlar foizi yig'indisi 100 bo'lishi kerak (hozir $_weightSum%)", error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(assignmentsRepositoryProvider).updateContent(
            widget.a.id,
            items: _isText ? null : _items,
            rubric: _isText ? _rubric : null,
          );
      ref.invalidate(assignmentProvider(widget.a.id));
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isText ? 'Mezonlar' : 'Misollar'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _saving
                ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4)))
                : TextButton(onPressed: _save, child: const Text('Saqlash')),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _isText ? _editCriterion() : _editItem(),
        icon: const Icon(Icons.add_rounded),
        label: Text(_isText ? 'Mezon' : 'Misol'),
      ),
      body: _isText ? _rubricList() : _itemsList(),
    );
  }

  Widget _itemsList() {
    if (_items.isEmpty) {
      return const EmptyState(
        icon: Icons.format_list_numbered_rounded,
        title: "Misol yo'q",
        message: "«Misol» tugmasi bilan qo'shing",
      );
    }
    return ReorderableListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: _items.length,
      onReorderItem: (from, to) => setState(() => _items.insert(to, _items.removeAt(from))),
      itemBuilder: (context, i) {
        final item = _items[i];
        return Dismissible(
          key: ValueKey('${item.number}-$i-${item.text.hashCode}'),
          direction: DismissDirection.endToStart,
          background: Container(
            color: context.appColors.danger,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            child: const Icon(Icons.delete_rounded, color: Colors.white),
          ),
          onDismissed: (_) {
            final removed = _items.removeAt(i);
            setState(() {});
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("${removed.number}-misol o'chirildi"),
                action: SnackBarAction(label: 'Qaytarish', onPressed: () => setState(() => _items.insert(i, removed))),
              ),
            );
          },
          child: ListTile(
            onTap: () => _editItem(i),
            leading: Text(item.number, style: context.text.titleMedium?.copyWith(color: context.colors.primary)),
            title: Text(item.text, maxLines: 3, overflow: TextOverflow.ellipsis),
            subtitle: item.answer == null ? null : Text('Javob: ${item.answer}'),
            trailing: const Icon(Icons.drag_handle_rounded),
          ),
        );
      },
    );
  }

  Widget _rubricList() {
    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: StatusChip(
            label: 'Jami: $_weightSum%',
            tone: _weightSum == 100 ? StatusTone.success : StatusTone.danger,
            icon: _weightSum == 100 ? Icons.check_rounded : Icons.error_outline_rounded,
          ),
        ),
        for (final (i, c) in _rubric.indexed)
          ListTile(
            onTap: () => _editCriterion(i),
            title: Text(c.name),
            subtitle: c.description.isEmpty ? null : Text(c.description),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${c.weight}%', style: const TextStyle(fontWeight: FontWeight.w700)),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => setState(() => _rubric.removeAt(i)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ItemSheet extends StatefulWidget {
  const _ItemSheet({this.item, required this.nextNumber});

  final AssignmentItem? item;
  final String nextNumber;

  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  late final _number = TextEditingController(text: widget.item?.number ?? widget.nextNumber);
  late final _text = TextEditingController(text: widget.item?.text ?? '');
  late final _answer = TextEditingController(text: widget.item?.answer ?? '');

  @override
  void dispose() {
    _number.dispose();
    _text.dispose();
    _answer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = _number.text.trim().isNotEmpty && _text.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.item == null ? 'Yangi misol' : 'Misolni tahrirlash', style: context.text.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _number,
              maxLength: 20,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Raqami', hintText: '56', counterText: ''),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              autofocus: widget.item == null,
              minLines: 2,
              maxLines: 6,
              maxLength: 2000,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Sharti', hintText: '2x + 3 = 11', counterText: ''),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _answer,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: "To'g'ri javob (ixtiyoriy)",
                helperText: 'Kiritilsa, AI shunga solishtirib aniqroq tekshiradi',
                counterText: '',
              ),
            ),
            const SizedBox(height: 18),
            PrimaryButton(
              label: 'Tayyor',
              onPressed: valid
                  ? () => Navigator.pop(
                        context,
                        AssignmentItem(
                          number: _number.text.trim(),
                          text: _text.text.trim(),
                          answer: _answer.text.trim().isEmpty ? null : _answer.text.trim(),
                        ),
                      )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _CriterionSheet extends StatefulWidget {
  const _CriterionSheet({this.criterion});

  final Criterion? criterion;

  @override
  State<_CriterionSheet> createState() => _CriterionSheetState();
}

class _CriterionSheetState extends State<_CriterionSheet> {
  late final _name = TextEditingController(text: widget.criterion?.name ?? '');
  late final _desc = TextEditingController(text: widget.criterion?.description ?? '');
  late double _weight = (widget.criterion?.weight ?? 20).toDouble();

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
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
            Text('Mezon', style: context.text.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              maxLength: 80,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Nomi', hintText: 'Mavzuga mosligi', counterText: ''),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _desc,
              maxLength: 400,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Izoh (ixtiyoriy)', counterText: ''),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Ulushi'),
                Expanded(
                  child: Slider(
                    value: _weight,
                    min: 5,
                    max: 100,
                    divisions: 19,
                    label: '${_weight.round()}%',
                    onChanged: (v) => setState(() => _weight = v),
                  ),
                ),
                Text('${_weight.round()}%', style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              label: 'Tayyor',
              onPressed: _name.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(
                        context,
                        Criterion(name: _name.text.trim(), weight: _weight.round(), description: _desc.text.trim()),
                      ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PublishBar extends ConsumerStatefulWidget {
  const _PublishBar({required this.a});

  final Assignment a;

  @override
  ConsumerState<_PublishBar> createState() => _PublishBarState();
}

class _PublishBarState extends ConsumerState<_PublishBar> {
  bool _busy = false;

  Future<void> _publish() async {
    setState(() => _busy = true);
    try {
      await ref.read(assignmentsRepositoryProvider).publish(widget.a.id);
      HapticFeedback.mediumImpact();
      ref.invalidate(assignmentProvider(widget.a.id));
      ref.invalidate(groupAssignmentsProvider(widget.a.groupId));
      if (mounted) showSnack(context, "Vazifa o'quvchilarga yuborildi");
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: BoxDecoration(
          color: context.colors.surface,
          border: Border(top: BorderSide(color: context.colors.outlineVariant)),
        ),
        child: PrimaryButton(
          label: "Tasdiqlash va o'quvchilarga yuborish",
          icon: Icons.send_rounded,
          loading: _busy,
          onPressed: _publish,
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats});

  final SubmissionStats stats;

  @override
  Widget build(BuildContext context) {
    Widget cell(String value, String label, Color color) => Expanded(
          child: Column(
            children: [
              Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
              const SizedBox(height: 2),
              Text(label, textAlign: TextAlign.center, style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
            ],
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            cell('${stats.submitted}/${stats.members}', 'topshirdi', context.colors.primary),
            cell('${stats.graded}', 'baholandi', context.appColors.success),
            cell('${stats.needsReview}', 'tekshirish kerak', stats.needsReview > 0 ? context.appColors.warning : context.appColors.muted),
          ],
        ),
      ),
    );
  }
}

class _Submissions extends StatelessWidget {
  const _Submissions({required this.subs});

  final List<Submission> subs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle("O'quvchilar ishlari"),
        if (subs.isEmpty)
          Text(
            "Hali hech kim topshirmagan. O'quvchi topshirishi bilan AI tekshiradi va shu yerda ko'rinadi.",
            style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
          )
        else
          Card(
            child: Column(
              children: [
                for (final (i, s) in subs.indexed) ...[
                  if (i > 0) const Divider(height: 1, indent: 72),
                  ListTile(
                    onTap: () => context.push('/teacher/submissions/${s.id}'),
                    leading: Avatar(initials: s.studentName.split(' ').map((p) => p.isEmpty ? '' : p[0]).take(2).join()),
                    title: Text(s.studentName, style: context.text.titleMedium),
                    subtitle: Text(
                      '${formatDueUz(s.submittedAt)}${s.isLate ? ' · kechikkan' : ''}',
                      style: TextStyle(color: s.isLate ? context.appColors.warning : null),
                    ),
                    trailing: submissionChip(s),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
