import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/media_cache.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/math_text.dart';
import '../data/assignment_models.dart';
import '../data/assignments_repository.dart';

/// Tarmoqdagi rasm: yuklanayotganda skelet, xato bo'lsa ikonka (ekran "sakramaydi").
class NetImage extends StatelessWidget {
  const NetImage(this.url, {super.key, this.fit = BoxFit.cover});

  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      cacheKey: mediaCacheKey(url),
      cacheManager: mediaCache,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (context, _) => ColoredBox(
        color: context.colors.surfaceContainer,
        child: const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
      ),
      errorWidget: (context, _, _) => ColoredBox(
        color: context.colors.surfaceContainer,
        child: Icon(Icons.broken_image_outlined, color: context.colors.onSurfaceVariant),
      ),
    );
  }
}

/// Rasmlar qatori; bosilsa to'liq ekranda (kattalashtirish mumkin) ochiladi.
class PhotoStrip extends StatelessWidget {
  const PhotoStrip({super.key, required this.urls, this.height = 110});

  final List<String> urls;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => GestureDetector(
          onTap: () => Navigator.of(context).push(
            PageRouteBuilder<void>(
              opaque: false,
              pageBuilder: (_, _, _) => PhotoViewer(urls: urls, initial: i),
              transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
            ),
          ),
          child: Hero(
            tag: urls[i],
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.md),
              child: SizedBox(width: height * 0.78, height: height, child: NetImage(urls[i])),
            ),
          ),
        ),
      ),
    );
  }
}

class PhotoViewer extends StatefulWidget {
  const PhotoViewer({super.key, required this.urls, this.initial = 0});

  final List<String> urls;
  final int initial;

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late final _page = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1} / ${widget.urls.length}', style: const TextStyle(color: Colors.white)),
      ),
      body: PageView.builder(
        controller: _page,
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => InteractiveViewer(
          maxScale: 5,
          child: Center(child: Hero(tag: widget.urls[i], child: NetImage(widget.urls[i], fit: BoxFit.contain))),
        ),
      ),
    );
  }
}

/// Muddat belgisi: rang + ikonka + matn
class DueChip extends StatelessWidget {
  const DueChip({super.key, required this.due, this.done = false});

  final DateTime due;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final left = due.difference(DateTime.now());
    final tone = done
        ? StatusTone.neutral
        : left.isNegative
            ? StatusTone.danger
            : left.inHours < 24
                ? StatusTone.warning
                : StatusTone.info;
    return StatusChip(
      label: done ? formatDueUz(due) : timeLeftUz(due),
      tone: tone,
      icon: left.isNegative && !done ? Icons.alarm_off_rounded : Icons.schedule_rounded,
    );
  }
}

(Color, Color, IconData) verdictStyle(BuildContext context, Verdict v) {
  final c = context.appColors;
  return switch (v) {
    Verdict.correct => (c.success, c.successContainer, Icons.check_circle_rounded),
    Verdict.partial => (c.warning, c.warningContainer, Icons.adjust_rounded),
    Verdict.incorrect => (c.danger, c.dangerContainer, Icons.cancel_rounded),
    Verdict.missing => (c.muted, context.colors.surfaceContainer, Icons.help_outline_rounded),
  };
}

/// AI xulosasi: har bir misol bo'yicha.
///
/// Ustoz ko'rinishida — qisqa belgi (xato qayerda). O'quvchi ko'rinishida ([askSubmissionId] berilsa)
/// xato misol tagida "Nega?" tugmasi: bosilganda AI shu misolni 2-3 sodda gap bilan tushuntiradi.
class GradedItemsList extends StatelessWidget {
  const GradedItemsList({super.key, required this.items, this.askSubmissionId});

  final List<GradedItem> items;
  final String? askSubmissionId;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          for (final (i, item) in items.indexed) ...[
            if (i > 0) const Divider(height: 1, indent: 64),
            _GradedItemRow(key: ValueKey(item.number), item: item, askSubmissionId: askSubmissionId),
          ],
        ],
      ),
    );
  }
}

class _GradedItemRow extends ConsumerStatefulWidget {
  const _GradedItemRow({super.key, required this.item, this.askSubmissionId});

  final GradedItem item;
  final String? askSubmissionId;

  @override
  ConsumerState<_GradedItemRow> createState() => _GradedItemRowState();
}

class _GradedItemRowState extends ConsumerState<_GradedItemRow> {
  late String? _explanation = widget.item.explanation;
  bool _loading = false;
  String? _error;

  Future<void> _ask() async {
    final id = widget.askSubmissionId;
    if (id == null || _loading) return;
    HapticFeedback.selectionClick();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final text = await ref.read(assignmentsRepositoryProvider).explainItem(id, widget.item.number);
      if (mounted) setState(() => _explanation = text);
    } on Object catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final (fg, bg, icon) = verdictStyle(context, item.verdict);
    final student = widget.askSubmissionId != null;
    final canAsk = student && item.isWrong;
    final title = item.number.length <= 6 ? '${item.number}-misol' : item.number;
    final muted = context.colors.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                child: Icon(icon, color: fg, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.text.titleMedium),
                    if (student && item.isWrong && item.studentAnswer.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: MathText(
                          'Javobingiz: ${item.studentAnswer}',
                          style: context.text.bodySmall?.copyWith(color: muted),
                        ),
                      )
                    else if (!student && item.comment.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(item.comment, style: context.text.bodyMedium?.copyWith(color: muted)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (canAsk && _explanation == null)
                _WhyButton(loading: _loading, onPressed: _ask)
              else
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(item.verdict.label, style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _explanation != null
                ? _ExplanationBox(text: _explanation!)
                : _error != null
                    ? Padding(
                        padding: const EdgeInsets.only(left: 48, top: 8),
                        child: Text(_error!, style: context.text.bodySmall?.copyWith(color: context.appColors.danger)),
                      )
                    : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _WhyButton extends StatelessWidget {
  const _WhyButton({required this.loading, required this.onPressed});

  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final primary = context.colors.primary;
    return Semantics(
      button: true,
      label: 'Nega xato? Tushuntirish',
      child: Material(
        color: primary.withValues(alpha: 0.1),
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: loading ? null : onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: loading
                  ? SizedBox(
                      key: const ValueKey('l'),
                      width: 46,
                      height: 18,
                      child: Center(
                        child: SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: primary),
                        ),
                      ),
                    )
                  : Row(
                      key: const ValueKey('t'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.help_outline_rounded, size: 18, color: primary),
                        const SizedBox(width: 4),
                        Text('Nega?', style: TextStyle(color: primary, fontWeight: FontWeight.w700)),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExplanationBox extends StatelessWidget {
  const _ExplanationBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final primary = context.colors.primary;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(left: 48, top: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border(left: BorderSide(color: primary.withValues(alpha: 0.5), width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 15, color: primary),
              const SizedBox(width: 6),
              Text('Nega xato?', style: context.text.labelMedium?.copyWith(color: primary, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          MathText(text, style: context.text.bodyMedium?.copyWith(height: 1.45)),
        ],
      ),
    );
  }
}

/// Katta baho doirasi (natija ekranlari uchun)
class ScoreBadge extends StatelessWidget {
  const ScoreBadge({super.key, required this.score, required this.scale, this.size = 96});

  final double score;
  final int scale;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ratio = scale == 0 ? 0.0 : score / scale;
    final c = context.appColors;
    final color = ratio >= 0.86
        ? c.success
        : ratio >= 0.71
            ? c.info
            : ratio >= 0.51
                ? c.warning
                : c.danger;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: ratio.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CircularProgressIndicator(
              value: v,
              strokeWidth: 8,
              color: color,
              backgroundColor: color.withValues(alpha: 0.15),
              strokeCap: StrokeCap.round,
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(scoreText(score), style: TextStyle(fontSize: size * 0.32, fontWeight: FontWeight.w800, color: color)),
                  Text('/ $scale', style: TextStyle(fontSize: size * 0.13, color: context.colors.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Topshiriq holati belgisi (ustoz ro'yxatlari uchun)
StatusChip submissionChip(Submission s) => switch (s.status) {
      SubmissionStatus.grading =>
        const StatusChip(label: 'AI tekshirmoqda', tone: StatusTone.info, icon: Icons.hourglass_top_rounded),
      SubmissionStatus.needsReview =>
        const StatusChip(label: 'Tekshirish kerak', tone: StatusTone.warning, icon: Icons.visibility_rounded),
      SubmissionStatus.failed =>
        const StatusChip(label: 'Qo\'lda baholang', tone: StatusTone.danger, icon: Icons.error_outline_rounded),
      SubmissionStatus.graded => StatusChip(
          label: '${scoreText(s.finalScore ?? 0)} / ${s.gradingScale}',
          tone: StatusTone.success,
          icon: Icons.check_rounded,
        ),
    };

/// Bo'lim sarlavhasi
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 4),
        child: Row(
          children: [
            Expanded(child: Text(text, style: context.text.titleLarge)),
            ?trailing,
          ],
        ),
      );
}
