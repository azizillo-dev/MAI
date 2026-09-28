import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

final _math = RegExp(r'\$([^$]+)\$');

/// Matndagi `$...$` bo'laklarini matematik formula (LaTeX) qilib chizadi, qolgani oddiy matn.
/// Masalan: "Hisoblang: $\frac{3}{4} + \frac{1}{8}$".
List<InlineSpan> mathSpans(String text, TextStyle style) {
  final spans = <InlineSpan>[];
  var last = 0;
  for (final m in _math.allMatches(text)) {
    if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
    final tex = m.group(1)!;
    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Math.tex(
          tex,
          mathStyle: MathStyle.text,
          textStyle: style,
          // Formula buzuq bo'lsa ham ilova qulamaydi: asl matn ko'rinadi
          onErrorFallback: (_) => Text('\$$tex\$', style: style),
        ),
      ),
    );
    last = m.end;
  }
  if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
  return spans;
}

bool hasMath(String text) => _math.hasMatch(text);

class MathText extends StatelessWidget {
  const MathText(this.text, {super.key, this.style, this.textAlign});

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final effective = DefaultTextStyle.of(context).style.merge(style);
    if (!hasMath(text)) return Text(text, style: effective, textAlign: textAlign);
    return Text.rich(TextSpan(style: effective, children: mathSpans(text, effective)), textAlign: textAlign);
  }
}
