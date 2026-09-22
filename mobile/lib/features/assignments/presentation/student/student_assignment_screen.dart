import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../data/assignment_models.dart';
import '../../data/assignments_repository.dart';
import '../widgets.dart';

class StudentAssignmentScreen extends ConsumerStatefulWidget {
  const StudentAssignmentScreen({super.key, required this.assignmentId});

  final String assignmentId;

  @override
  ConsumerState<StudentAssignmentScreen> createState() => _StudentAssignmentScreenState();
}

class _StudentAssignmentScreenState extends ConsumerState<StudentAssignmentScreen> {
  Timer? _poll;
  final List<XFile> _pages = [];
  final _text = TextEditingController();
  bool _resubmitting = false;
  bool _sending = false;
  double _progress = 0;

  @override
  void dispose() {
    _poll?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _schedulePoll(bool grading) {
    if (grading && _poll == null) {
      _poll = Timer.periodic(const Duration(seconds: 3), (_) => ref.invalidate(studentAssignmentProvider(widget.assignmentId)));
    } else if (!grading && _poll != null) {
      _poll!.cancel();
      _poll = null;
      HapticFeedback.mediumImpact(); // natija keldi
      ref.invalidate(studentAssignmentsProvider);
    }
  }

  Future<void> _addPage(ImageSource source) async {
    final picker = ImagePicker();
    if (source == ImageSource.camera) {
      final x = await picker.pickImage(source: source, imageQuality: 82, maxWidth: 2200, maxHeight: 2200);
      if (x != null) setState(() => _pages.add(x));
    } else {
      final xs = await picker.pickMultiImage(imageQuality: 82, maxWidth: 2200, maxHeight: 2200, limit: 10);
      setState(() => _pages.addAll(xs.take(10 - _pages.length)));
    }
  }

  Future<void> _send(StudentAssignment a) async {
    if (_pages.isEmpty && _text.text.trim().isEmpty) {
      showSnack(context, 'Ishingizni rasmga oling', error: true);
      return;
    }
    if (a.isOverdue) {
      final ok = await confirmDialog(
        context,
        title: "Muddati o'tgan",
        message: a.latePenaltyPercent > 0
            ? 'Kechikib topshirilgan ish uchun baho ${a.latePenaltyPercent}% kamaytiriladi.'
            : "Ish kechikkan deb belgilanadi.",
        confirmLabel: 'Topshirish',
      );
      if (!ok) return;
    }
    setState(() {
      _sending = true;
      _progress = 0;
    });
    try {
      await ref.read(assignmentsRepositoryProvider).submit(
            a.id,
            imagePaths: [for (final p in _pages) p.path],
            textAnswer: _text.text.trim(),
            onProgress: (p) => mounted ? setState(() => _progress = p) : null,
          );
      HapticFeedback.mediumImpact();
      _pages.clear();
      _text.clear();
      _resubmitting = false;
      ref.invalidate(studentAssignmentProvider(a.id));
      ref.invalidate(studentAssignmentsProvider);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(studentAssignmentProvider(widget.assignmentId));
    final a = async.value;
    final grading = a?.submission?.status == SubmissionStatus.grading;
    WidgetsBinding.instance.addPostFrameCallback((_) => _schedulePoll(grading));

    return Scaffold(
      appBar: AppBar(title: Text(a?.title ?? 'Vazifa')),
      body: a == null
          ? (async.hasError
              ? ErrorRetry(error: async.error!, onRetry: () => ref.invalidate(studentAssignmentProvider(widget.assignmentId)))
              : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(studentAssignmentProvider(widget.assignmentId));
                await ref.read(studentAssignmentProvider(widget.assignmentId).future);
              },
              child: ListView(
                padding: Insets.screen.copyWith(top: 4, bottom: 32),
                children: [
                  _TaskHeader(a: a),
                  const SizedBox(height: 18),
                  _TaskContent(a: a),
                  const SizedBox(height: 22),
                  if (a.submission == null || _resubmitting)
                    _submitSection(a)
                  else
                    _ResultSection(
                      a: a,
                      onResubmit: _canResubmit(a) ? () => setState(() => _resubmitting = true) : null,
                    ),
                ],
              ),
            ),
    );
  }

  bool _canResubmit(StudentAssignment a) {
    final s = a.submission!;
    return !a.isOverdue && s.teacherScore == null && s.status != SubmissionStatus.grading && s.attempt < 3;
  }

  Widget _submitSection(StudentAssignment a) {
    if (!a.canSubmit && !_resubmitting) {
      return const InfoBanner(
        tone: StatusTone.danger,
        title: "Muddati o'tdi",
        text: 'Ustoz bu vazifani kechikib topshirishga ruxsat bermagan.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(_resubmitting ? 'Qayta topshirish' : 'Ishingizni topshiring'),
        Text(
          "Daftaringizni har bir sahifasini alohida, yorug' joyda, tekis qilib rasmga oling. Rasm xira bo'lsa, AI to'g'ri tekshira olmaydi.",
          style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        if (_pages.isNotEmpty) ...[
          SizedBox(
            height: 130,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _pages.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) => Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.md),
                    child: Image.file(File(_pages[i].path), width: 100, height: 130, fit: BoxFit.cover, cacheWidth: 300),
                  ),
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: StatusChip(label: '${i + 1}-bet', tone: StatusTone.neutral),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => setState(() => _pages.removeAt(i)),
                        child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.close_rounded, size: 16, color: Colors.white)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _pages.length >= 10 || _sending ? null : () => _addPage(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_rounded),
                label: Text(_pages.isEmpty ? 'Rasmga olish' : 'Yana bet'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pages.length >= 10 || _sending ? null : () => _addPage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_rounded),
                label: const Text('Galereya'),
              ),
            ),
          ],
        ),
        if (a.sourceType == SourceType.text) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            minLines: 3,
            maxLines: 8,
            maxLength: 8000,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Matn bilan javob (ixtiyoriy)', counterText: ''),
          ),
        ],
        const SizedBox(height: 18),
        if (_sending && _progress > 0 && _progress < 1) ...[
          LinearProgressIndicator(value: _progress, minHeight: 6, borderRadius: BorderRadius.circular(8)),
          const SizedBox(height: 10),
        ],
        PrimaryButton(
          label: 'Topshirish',
          icon: Icons.send_rounded,
          loading: _sending,
          onPressed: _pages.isEmpty && _text.text.isEmpty ? null : () => _send(a),
        ),
        if (_resubmitting)
          TextButton(onPressed: () => setState(() => _resubmitting = false), child: const Text('Bekor qilish')),
      ],
    );
  }
}

class _TaskHeader extends StatelessWidget {
  const _TaskHeader({required this.a});

  final StudentAssignment a;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            DueChip(due: a.dueAt, done: a.submission != null),
            StatusChip(label: a.groupName, tone: StatusTone.neutral, icon: Icons.groups_rounded),
          ],
        ),
        const SizedBox(height: 10),
        Text('Ustoz: ${a.teacherName} · Muddat: ${formatDueUz(a.dueAt)}',
            style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant)),
        if (a.latePenaltyPercent > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Kechiksangiz, baho ${a.latePenaltyPercent}% kamayadi',
                style: context.text.bodySmall?.copyWith(color: context.appColors.warning)),
          ),
      ],
    );
  }
}

class _TaskContent extends StatelessWidget {
  const _TaskContent({required this.a});

  final StudentAssignment a;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (a.sourceType == SourceType.book)
          InfoBanner(
            icon: Icons.menu_book_rounded,
            title: a.bookTitle ?? 'Kitob',
            text: bookRangeLabel(pageFrom: a.pageFrom, pageTo: a.pageTo, problems: a.problems),
          ),
        if (a.instructions != null) ...[
          const SizedBox(height: 12),
          SectionCard(child: Text(a.instructions!, style: context.text.bodyLarge)),
        ],
        if (a.imageUrls.isNotEmpty) ...[const SizedBox(height: 12), PhotoStrip(urls: a.imageUrls, height: 140)],
        if (a.items.isNotEmpty) ...[
          const SizedBox(height: 18),
          SectionTitle('Misollar (${a.items.length})'),
          Card(
            child: Column(
              children: [
                for (final (i, item) in a.items.indexed) ...[
                  if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: Text(item.number,
                        style: context.text.titleMedium?.copyWith(color: context.colors.primary)),
                    title: Text(item.text),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (a.rubric.isNotEmpty) ...[
          const SizedBox(height: 18),
          const SectionTitle('Nimaga qarab baholanadi'),
          Card(
            child: Column(
              children: [
                for (final c in a.rubric)
                  ListTile(
                    title: Text(c.name),
                    subtitle: c.description.isEmpty ? null : Text(c.description),
                    trailing: Text('${c.weight}%', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ResultSection extends StatelessWidget {
  const _ResultSection({required this.a, this.onResubmit});

  final StudentAssignment a;
  final VoidCallback? onResubmit;

  @override
  Widget build(BuildContext context) {
    final s = a.submission!;
    if (s.status == SubmissionStatus.grading) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
          child: Column(
            children: [
              const SizedBox(width: 44, height: 44, child: CircularProgressIndicator(strokeWidth: 3.5)),
              const SizedBox(height: 16),
              Text('AI ishingizni tekshirmoqda…', style: context.text.titleMedium),
              const SizedBox(height: 6),
              Text(
                "Odatda 1 daqiqagacha. Natija tayyor bo'lganda shu yerda chiqadi.",
                textAlign: TextAlign.center,
                style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }
    if (!s.isFinal) {
      return const InfoBanner(
        tone: StatusTone.warning,
        icon: Icons.visibility_rounded,
        title: 'Ustoz tekshirmoqda',
        text: "Ishingizni ustozingiz shaxsan ko'rib chiqadi. Baho tez orada chiqadi.",
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                ScoreBadge(score: s.finalScore ?? 0, scale: s.scaleMax),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Bahoingiz', style: context.text.titleLarge),
                      const SizedBox(height: 4),
                      Text(
                        s.teacherScore != null ? 'Ustoz tasdiqlagan' : 'AI tekshirdi',
                        style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
                      ),
                      if (s.isLate)
                        Text('Kechikib topshirilgan',
                            style: context.text.bodySmall?.copyWith(color: context.appColors.warning)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (s.feedbackStudent != null) ...[
          const SizedBox(height: 12),
          InfoBanner(icon: Icons.auto_awesome_rounded, tone: StatusTone.info, title: 'Izoh', text: s.feedbackStudent!),
        ],
        if (s.teacherComment != null) ...[
          const SizedBox(height: 10),
          InfoBanner(icon: Icons.school_rounded, tone: StatusTone.success, title: 'Ustoz izohi', text: s.teacherComment!),
        ],
        if (s.aiItems.isNotEmpty) ...[
          const SizedBox(height: 18),
          const SectionTitle("Misollar bo'yicha"),
          GradedItemsList(items: s.aiItems),
        ],
        if (s.fileUrls.isNotEmpty) ...[
          const SizedBox(height: 18),
          const SectionTitle('Yuborgan ishingiz'),
          PhotoStrip(urls: s.fileUrls),
        ],
        if (onResubmit != null) ...[
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: onResubmit,
            icon: const Icon(Icons.refresh_rounded),
            label: Text('Xatolarni tuzatib qayta topshirish (${3 - s.attempt} ta imkoniyat)'),
          ),
        ],
      ],
    );
  }
}
