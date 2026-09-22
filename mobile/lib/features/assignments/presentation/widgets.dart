import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import '../data/assignment_models.dart';

/// Tarmoqdagi rasm: yuklanayotganda skelet, xato bo'lsa ikonka (ekran "sakramaydi").
class NetImage extends StatelessWidget {
  const NetImage(this.url, {super.key, this.fit = BoxFit.cover});

  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: fit,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, sync) => AnimatedOpacity(
        opacity: frame == null ? 0 : 1,
        duration: const Duration(milliseconds: 200),
        child: child,
      ),
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : ColoredBox(
              color: context.colors.surfaceContainer,
              child: const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
      errorBuilder: (context, _, _) => ColoredBox(
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

/// AI xulosasi: har bir misol bo'yicha
class GradedItemsList extends StatelessWidget {
  const GradedItemsList({super.key, required this.items});

  final List<GradedItem> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          for (final (i, item) in items.indexed) ...[
            if (i > 0) const Divider(height: 1, indent: 56),
            Builder(builder: (context) {
              final (fg, bg, icon) = verdictStyle(context, item.verdict);
              return ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                  child: Icon(icon, color: fg, size: 22),
                ),
                title: Text(
                  item.number.length <= 6 ? '${item.number}-misol' : item.number,
                  style: context.text.titleMedium,
                ),
                subtitle: item.comment.isEmpty ? null : Text(item.comment),
                trailing: Text(item.verdict.label, style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
              );
            }),
          ],
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
