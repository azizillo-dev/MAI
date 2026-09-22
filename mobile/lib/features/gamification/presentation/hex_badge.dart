import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Nishon tiklari: metall (oltin/kumush/bronza) va rangli (ko'k/yashil/binafsha).
/// [light, mid, dark] — gradient bosqichlari.
const badgeTiers = <String, List<Color>>{
  'gold': [Color(0xFFFEF08A), Color(0xFFF59E0B), Color(0xFF92400E)],
  'silver': [Color(0xFFF8FAFC), Color(0xFF94A3B8), Color(0xFF334155)],
  'bronze': [Color(0xFFFED7AA), Color(0xFFEA580C), Color(0xFF7C2D12)],
  'blue': [Color(0xFFBFDBFE), Color(0xFF3B82F6), Color(0xFF1E3A8A)],
  'green': [Color(0xFFBBF7D0), Color(0xFF22C55E), Color(0xFF14532D)],
  'purple': [Color(0xFFE9D5FF), Color(0xFFA855F7), Color(0xFF4C1D95)],
};

const badgeIcons = <String, IconData>{
  'rocket': Icons.rocket_launch_rounded,
  'clock': Icons.alarm_on_rounded,
  'fire': Icons.local_fire_department_rounded,
  'diamond': Icons.diamond_rounded,
  'brain': Icons.psychology_rounded,
  'target': Icons.track_changes_rounded,
  'bolt': Icons.bolt_rounded,
  'shield': Icons.shield_rounded,
  'calculate': Icons.calculate_rounded,
  'functions': Icons.functions_rounded,
  'translate': Icons.translate_rounded,
  'language': Icons.menu_book_rounded,
  'trending': Icons.trending_up_rounded,
  'stairs': Icons.stairs_rounded,
  'trophy': Icons.emoji_events_rounded,
};

/// Olti burchakli nishon. [earned] = false bo'lsa kulrang (olinmagan).
class HexBadge extends StatelessWidget {
  const HexBadge({
    super.key,
    required this.tier,
    required this.icon,
    this.size = 84,
    this.earned = true,
    this.label,
  });

  final String tier;
  final IconData icon;
  final double size;
  final bool earned;

  /// Ikonka ostidagi kichik yozuv (masalan oy medalida o'rin raqami)
  final String? label;

  @override
  Widget build(BuildContext context) {
    final colors = badgeTiers[tier] ?? badgeTiers['blue']!;
    final badge = SizedBox(
      width: size,
      height: size * 1.08,
      child: CustomPaint(
        painter: _HexPainter(colors),
        child: Center(
          child: Padding(
            padding: EdgeInsets.only(top: size * 0.02),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: size * (label == null ? 0.42 : 0.34),
                  color: Colors.white,
                  shadows: [Shadow(color: colors[2].withValues(alpha: 0.7), blurRadius: size * 0.08, offset: Offset(0, size * 0.03))],
                ),
                if (label != null)
                  Text(
                    label!,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: size * 0.16,
                      height: 1.1,
                      shadows: [Shadow(color: colors[2], blurRadius: 3)],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (earned) return RepaintBoundary(child: badge);
    // Olinmagan: kulrang va xiraroq (Ibrat'dagidek "hali yopiq" ko'rinish)
    return RepaintBoundary(
      child: Opacity(
        opacity: 0.55,
        child: ColorFiltered(colorFilter: const ColorFilter.matrix(_grayscale), child: badge),
      ),
    );
  }
}

const _grayscale = <double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0, 0, 0, 1, 0,
];

class _HexPainter extends CustomPainter {
  _HexPainter(this.c);

  final List<Color> c;

  /// Burchaklari yumaloqlangan olti burchak
  Path _roundedHex(Offset center, double r, double radius) {
    final pts = [
      for (var i = 0; i < 6; i++)
        Offset(center.dx + r * math.cos(math.pi / 180 * (60 * i - 90)), center.dy + r * math.sin(math.pi / 180 * (60 * i - 90))),
    ];
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final prev = pts[(i + 5) % 6], cur = pts[i], next = pts[(i + 1) % 6];
      final a = Offset.lerp(cur, prev, radius / (cur - prev).distance)!;
      final b = Offset.lerp(cur, next, radius / (cur - next).distance)!;
      i == 0 ? path.moveTo(a.dx, a.dy) : path.lineTo(a.dx, a.dy);
      path.quadraticBezierTo(cur.dx, cur.dy, b.dx, b.dy);
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: r);

    // Soya
    canvas.drawPath(
      _roundedHex(center.translate(0, r * 0.06), r * 0.98, r * 0.16),
      Paint()
        ..color = c[2].withValues(alpha: 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.08),
    );
    // Tashqi hoshiya (metall chekka)
    canvas.drawPath(
      _roundedHex(center, r * 0.98, r * 0.16),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c[0], c[1], c[2]],
          stops: const [0, 0.45, 1],
        ).createShader(rect),
    );
    // Ichki yuza
    final inner = _roundedHex(center, r * 0.80, r * 0.12);
    canvas.drawPath(
      inner,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.5),
          radius: 1.1,
          colors: [Color.lerp(c[0], c[1], 0.35)!, c[1], Color.lerp(c[1], c[2], 0.55)!],
          stops: const [0, 0.55, 1],
        ).createShader(rect),
    );
    // Ichki chegara chizig'i
    canvas.drawPath(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.035
        ..color = Colors.white.withValues(alpha: 0.45),
    );
    // Yaltiroq nur (yuqori yarmi)
    canvas.save();
    canvas.clipPath(inner);
    canvas.drawOval(
      Rect.fromCenter(center: center.translate(-r * 0.15, -r * 0.55), width: r * 1.6, height: r * 0.9),
      Paint()..color = Colors.white.withValues(alpha: 0.22),
    );
    canvas.restore();
    // Uchqunlar
    final sparkle = Paint()..color = Colors.white.withValues(alpha: 0.9);
    _star(canvas, center.translate(r * 0.52, -r * 0.48), r * 0.09, sparkle);
    _star(canvas, center.translate(-r * 0.55, r * 0.35), r * 0.06, sparkle);
    _star(canvas, center.translate(r * 0.62, r * 0.12), r * 0.045, sparkle);
  }

  void _star(Canvas canvas, Offset c0, double s, Paint p) {
    final path = Path()
      ..moveTo(c0.dx, c0.dy - s)
      ..quadraticBezierTo(c0.dx, c0.dy, c0.dx + s, c0.dy)
      ..quadraticBezierTo(c0.dx, c0.dy, c0.dx, c0.dy + s)
      ..quadraticBezierTo(c0.dx, c0.dy, c0.dx - s, c0.dy)
      ..quadraticBezierTo(c0.dx, c0.dy, c0.dx, c0.dy - s)
      ..close();
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_HexPainter old) => old.c != c;
}
