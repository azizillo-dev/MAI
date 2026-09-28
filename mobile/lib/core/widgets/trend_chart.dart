import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Foizlar (0-100) chizig'i: bo'sh (null) nuqtalar tashlab ketiladi, oxirgi nuqta ajratib ko'rsatiladi.
/// O'qituvchi dashboardida 8 haftalik trend, o'quvchida oxirgi baholar uchun.
///
/// Shkala ma'lumotga moslashadi (masalan 55–80%): 0–100 da o'zgarish sezilmay qoladi.
/// Chegaradagi qiymatlar yozib qo'yiladi — kesilgan o'q aldamasligi uchun.
class TrendChart extends StatelessWidget {
  const TrendChart({super.key, required this.values, this.color});

  final List<double?> values;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (values.whereType<double>().length < 2) return const SizedBox.shrink();
    return CustomPaint(
      painter: _TrendPainter(
        values,
        color ?? scheme.primary,
        scheme.outlineVariant,
        Theme.of(context).textTheme.labelSmall!.copyWith(color: scheme.onSurfaceVariant, fontSize: 10),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.values, this.color, this.grid, this.labelStyle);

  final List<double?> values;
  final Color color;
  final Color grid;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    final known = values.whereType<double>();
    // Ma'lumot oralig'i + zaxira, kamida 20 foizlik oyna, 10 ga yaxlitlangan
    var lo = (known.reduce(math.min) - 8).clamp(0, 100).toDouble();
    var hi = (known.reduce(math.max) + 8).clamp(0, 100).toDouble();
    lo = (lo / 10).floorToDouble() * 10;
    hi = (hi / 10).ceilToDouble() * 10;
    if (hi - lo < 20) {
      hi = math.min(100, lo + 20);
      lo = hi - 20;
    }
    const labelW = 30.0;
    final w = size.width - labelW;
    Offset at(int i, double v) =>
        Offset(w * i / (n - 1), size.height - 6 - (size.height - 12) * ((v.clamp(lo, hi) - lo) / (hi - lo)));

    // Yuqori va pastki chegara chiziqlari yozuvlari bilan (sust)
    final gridPaint = Paint()
      ..color = grid.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (final v in [lo, hi]) {
      final y = at(0, v).dy;
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
      final tp = TextPainter(text: TextSpan(text: '${v.round()}%', style: labelStyle), textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(w + 6, y - tp.height / 2));
    }

    final pts = [for (var i = 0; i < n; i++) if (values[i] != null) at(i, values[i]!)];
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      // Silliq egri chiziq (kubik) — nuqtalar orasida o'rta nazorat nuqtalari
      final p0 = pts[i - 1], p1 = pts[i];
      final mx = (p0.dx + p1.dx) / 2;
      path.cubicTo(mx, p0.dy, mx, p1.dy, p1.dx, p1.dy);
    }
    final fill = Path.from(path)
      ..lineTo(pts.last.dx, size.height)
      ..lineTo(pts.first.dx, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.24), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    for (final p in pts) {
      canvas.drawCircle(p, 2.5, Paint()..color = color);
    }
    canvas.drawCircle(pts.last, 5.5, Paint()..color = color);
    canvas.drawCircle(pts.last, 2.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_TrendPainter old) => old.values != values || old.color != color;
}
