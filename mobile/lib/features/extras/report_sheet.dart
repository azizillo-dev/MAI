import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_widgets.dart';
import '../groups/data/group_models.dart';
import 'extras_repository.dart';

/// Guruh hisobotini (PDF yoki Excel) yuklab, ulashish oynasini ochadi: Telegram, email, fayllar...
Future<void> showReportSheet(BuildContext context, List<TeacherGroup> groups, {TeacherGroup? only}) async {
  if (groups.isEmpty && only == null) {
    showSnack(context, "Avval guruh yarating", error: true);
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _ReportSheet(groups: only != null ? [only] : groups),
  );
}

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({required this.groups});

  final List<TeacherGroup> groups;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  late TeacherGroup _group = widget.groups.first;
  String _format = 'pdf';
  String _period = 'month';
  bool _loading = false;

  Future<void> _download() async {
    setState(() => _loading = true);
    try {
      final bytes = await ref.read(extrasRepositoryProvider).groupReport(_group.id, _format, _period);
      final dir = await getTemporaryDirectory();
      final safe = _group.name.replaceAll(RegExp(r'[^\w\-]+', unicode: true), '_');
      final file = File('${dir.path}/${safe}_hisobot.$_format');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      Navigator.pop(context);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        subject: '${_group.name} — guruh hisoboti',
        text: '${_group.name} — Mentor AI hisoboti',
      ));
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } on FileSystemException {
      if (mounted) showSnack(context, "Faylni saqlab bo'lmadi", error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Guruh hisoboti', style: context.text.titleLarge),
          const SizedBox(height: 4),
          Text("O'quvchilar natijasi, topshirilmagan va kechikkan ishlar, vazifalar bo'yicha o'rtacha ball",
              style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant)),
          if (widget.groups.length > 1) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<TeacherGroup>(
              initialValue: _group,
              decoration: const InputDecoration(labelText: 'Guruh'),
              items: [for (final g in widget.groups) DropdownMenuItem(value: g, child: Text(g.name))],
              onChanged: (g) => setState(() => _group = g ?? _group),
            ),
          ],
          const SizedBox(height: 16),
          Text('Format', style: context.text.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'pdf', label: Text('PDF'), icon: Icon(Icons.picture_as_pdf_rounded)),
              ButtonSegment(value: 'xlsx', label: Text('Excel'), icon: Icon(Icons.table_chart_rounded)),
            ],
            selected: {_format},
            onSelectionChanged: (s) => setState(() => _format = s.first),
          ),
          const SizedBox(height: 16),
          Text('Davr', style: context.text.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'month', label: Text('Oxirgi 30 kun')),
              ButtonSegment(value: 'all', label: Text('Butun davr')),
            ],
            selected: {_period},
            onSelectionChanged: (s) => setState(() => _period = s.first),
          ),
          const SizedBox(height: 22),
          PrimaryButton(
            label: 'Yuklab olish va ulashish',
            icon: Icons.download_rounded,
            loading: _loading,
            onPressed: _download,
          ),
        ],
      ),
    );
  }
}
