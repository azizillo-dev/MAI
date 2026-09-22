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

/// Ustoz o'quvchi ishini ko'radi: rasmlar, AI xulosasi, va bahoni tasdiqlaydi yoki o'zgartiradi.
class SubmissionReviewScreen extends ConsumerWidget {
  const SubmissionReviewScreen({super.key, required this.submissionId});

  final String submissionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(submissionProvider(submissionId));
    final s = async.value;
    return Scaffold(
      appBar: AppBar(title: Text(s?.studentName ?? 'Ish')),
      body: s == null
          ? (async.hasError
              ? ErrorRetry(error: async.error!, onRetry: () => ref.invalidate(submissionProvider(submissionId)))
              : const Center(child: CircularProgressIndicator()))
          : _Body(s: s),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.s});

  final Submission s;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  late double _score = _initialScore();
  late final _comment = TextEditingController(text: widget.s.teacherComment ?? '');
  bool _saving = false;

  Submission get s => widget.s;

  double _initialScore() {
    if (s.finalScore != null) return s.finalScore!;
    // AI foizidan guruh shkalasiga taxminiy qiymat (ustoz o'zgartiradi)
    final p = (s.aiScorePercent ?? 0) / 100;
    return (p * s.scaleMax).roundToDouble().clamp(0, s.scaleMax.toDouble());
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(assignmentsRepositoryProvider).review(s.id, _score, _comment.text.trim());
      HapticFeedback.mediumImpact();
      ref.invalidate(submissionProvider(s.id));
      ref.invalidate(assignmentSubmissionsProvider(s.assignmentId));
      ref.invalidate(assignmentProvider(s.assignmentId));
      ref.invalidate(reviewQueueProvider);
      if (mounted) {
        showSnack(context, 'Baho saqlandi — o\'quvchi ko\'radi');
        context.pop();
      }
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = s.scaleMax;
    final lowConfidence = (s.aiConfidence ?? 1) < 0.7;
    return ListView(
      padding: Insets.screen.copyWith(top: 4, bottom: 32),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            submissionChip(s),
            StatusChip(label: formatDueUz(s.submittedAt), tone: StatusTone.neutral, icon: Icons.upload_rounded),
            if (s.isLate) const StatusChip(label: 'Kechikkan', tone: StatusTone.warning, icon: Icons.alarm_rounded),
            if (s.attempt > 1) StatusChip(label: '${s.attempt}-urinish', tone: StatusTone.neutral),
          ],
        ),
        const SizedBox(height: 16),
        if (s.fileUrls.isNotEmpty) ...[PhotoStrip(urls: s.fileUrls, height: 150), const SizedBox(height: 12)],
        if (s.textAnswer != null) ...[
          SectionCard(child: Text(s.textAnswer!, style: context.text.bodyLarge)),
          const SizedBox(height: 12),
        ],
        if (s.status == SubmissionStatus.grading)
          const InfoBanner(text: 'AI hali tekshirmoqda. Bir necha soniyadan keyin yangilang.')
        else ...[
          if (s.aiMatchesAssignment == false)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: InfoBanner(
                tone: StatusTone.danger,
                title: 'Vazifaga mos emas',
                text: 'AI fikricha, yuborilgan ish bu vazifaga tegishli emas.',
              ),
            ),
          if (s.noteTeacher != null)
            InfoBanner(
              tone: lowConfidence || s.status != SubmissionStatus.graded ? StatusTone.warning : StatusTone.info,
              icon: Icons.auto_awesome_rounded,
              title: lowConfidence ? 'AI ishonchi past (${((s.aiConfidence ?? 0) * 100).round()}%)' : 'AI xulosasi',
              text: s.noteTeacher!,
            ),
          if (s.aiItems.isNotEmpty) ...[
            const SizedBox(height: 16),
            SectionTitle(
              'Misollar bo\'yicha',
              trailing: s.aiScorePercent == null
                  ? null
                  : StatusChip(label: 'AI: ${s.aiScorePercent!.round()}%', tone: StatusTone.info),
            ),
            GradedItemsList(items: s.aiItems),
          ],
          if (s.feedbackStudent != null) ...[
            const SizedBox(height: 16),
            const SectionTitle("O'quvchiga izoh (AI)"),
            SectionCard(child: Text(s.feedbackStudent!)),
          ],
          const SizedBox(height: 22),
          const SectionTitle('Yakuniy baho'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (scale <= 10)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        for (var v = scale == 5 ? 2 : 1; v <= scale; v++)
                          ChoiceChip(
                            label: Text('$v', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                            selected: _score == v,
                            onSelected: (_) {
                              HapticFeedback.selectionClick();
                              setState(() => _score = v.toDouble());
                            },
                          ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: Slider(
                            value: _score,
                            max: 100,
                            divisions: 100,
                            label: scoreText(_score),
                            onChanged: (v) => setState(() => _score = v.roundToDouble()),
                          ),
                        ),
                        Text('${scoreText(_score)} / 100', style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _comment,
                    minLines: 2,
                    maxLines: 5,
                    maxLength: 1000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: "Sizning izohingiz (ixtiyoriy)",
                      hintText: "O'quvchi AI izohidan tashqari shuni ham ko'radi",
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 14),
                  PrimaryButton(
                    label: s.teacherScore == null ? 'Bahoni tasdiqlash' : 'Bahoni yangilash',
                    icon: Icons.check_rounded,
                    loading: _saving,
                    onPressed: _save,
                  ),
                ],
              ),
            ),
          ),
          if (s.teacherScore != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Siz qo\'ygan baho: ${scoreText(s.teacherScore!)} / $scale',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.appColors.success),
              ),
            ),
        ],
      ],
    );
  }
}

/// "Tekshirish kerak" navbati: AI ishonchi past yoki xato bergan ishlar
class ReviewQueueScreen extends ConsumerWidget {
  const ReviewQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reviewQueueProvider);
    final list = async.value;
    return Scaffold(
      appBar: AppBar(title: const Text('Tekshirish kerak')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(reviewQueueProvider);
          await ref.read(reviewQueueProvider.future);
        },
        child: list == null
            ? (async.hasError
                ? ListView(children: [ErrorRetry(error: async.error!, onRetry: () => ref.invalidate(reviewQueueProvider))])
                : const Center(child: CircularProgressIndicator()))
            : list.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 80),
                      EmptyState(
                        icon: Icons.task_alt_rounded,
                        title: 'Hammasi tekshirilgan',
                        message: "AI ishonchi past bo'lgan ishlar shu yerga tushadi.",
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
                    itemBuilder: (context, i) {
                      final s = list[i];
                      return ListTile(
                        onTap: () => context.push('/teacher/submissions/${s.id}'),
                        leading: Avatar(initials: s.studentName.split(' ').map((p) => p.isEmpty ? '' : p[0]).take(2).join()),
                        title: Text(s.studentName),
                        subtitle: Text(s.noteTeacher ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: submissionChip(s),
                      );
                    },
                  ),
      ),
    );
  }
}
