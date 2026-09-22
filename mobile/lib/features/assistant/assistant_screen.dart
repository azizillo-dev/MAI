import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../auth/application/auth_controller.dart';
import '../groups/data/groups_repository.dart';
import 'assistant_controller.dart';

const _violet = Color(0xFF8B5CF6);

/// O'qituvchining AI yordamchisi: o'quvchi va guruhlar haqida savol-javob
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send([String? text]) {
    final q = (text ?? _input.text).trim();
    if (q.isEmpty || ref.read(assistantChatProvider).sending) return;
    _input.clear();
    ref.read(assistantChatProvider.notifier).send(q);
    _toBottom();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(assistantChatProvider);
    ref.listen(assistantChatProvider, (prev, next) {
      if (prev?.messages.length != next.messages.length) _toBottom();
    });
    // Ro'yxat teskari: eng yangi xabar pastda, klaviatura ochilganda ham ko'rinib turadi
    final items = chat.messages.reversed.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_rounded, color: _violet),
            SizedBox(width: 8),
            Text('AI yordamchi'),
          ],
        ),
        actions: [
          if (chat.messages.isNotEmpty)
            IconButton(
              tooltip: 'Yangi suhbat',
              onPressed: chat.sending ? null : () => ref.read(assistantChatProvider.notifier).clear(),
              icon: const Icon(Icons.add_comment_outlined),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: chat.messages.isEmpty
                ? _Intro(onAsk: _send)
                : ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    itemCount: items.length + (chat.sending ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (chat.sending) {
                        if (i == 0) return const _Typing();
                        i -= 1;
                      }
                      return _Bubble(message: items[i]);
                    },
                  ),
          ),
          _Composer(controller: _input, sending: chat.sending, onSend: _send),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Bo'sh holat

class _Intro extends ConsumerWidget {
  const _Intro({required this.onAsk});

  final ValueChanged<String> onAsk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(currentUserProvider)?.firstName ?? '';
    final groups = ref.watch(teacherGroupsProvider).value ?? const [];
    final first = groups.firstOrNull;
    final members = first == null ? null : ref.watch(groupMembersProvider(first.id)).value;
    final student = members?.where((m) => !m.isPending).firstOrNull;

    final suggestions = [
      if (student != null) '${student.fullName} qanday o\'qiyapti?',
      if (first != null) '«${first.name}» guruhida kim orqada qolyapti?',
      "Qaysi mavzularda ko'p xato qilinyapti?",
      if (groups.length > 1) 'Guruhlarimni solishtirib ber',
      'Bu hafta kim vazifa topshirmadi?',
    ];

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: Insets.screen.copyWith(top: 28, bottom: 20),
      children: [
        Center(
          child: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [_violet, context.colors.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [BoxShadow(color: _violet.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 8))],
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 36),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          name.isEmpty ? 'Salom!' : 'Salom, $name!',
          textAlign: TextAlign.center,
          style: context.text.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          "O'quvchilaringiz va guruhlaringiz haqida so'rang — baholar, o'sish yoki pasayish, "
          "topshirilmagan vazifalar. Javoblar faqat haqiqiy ma'lumotlarga asoslanadi.",
          textAlign: TextAlign.center,
          style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
        ),
        const SizedBox(height: 26),
        Text('Masalan:', style: context.text.titleSmall?.copyWith(color: context.appColors.muted)),
        const SizedBox(height: 10),
        for (final s in suggestions) ...[
          _SuggestionTile(text: s, onTap: () => onAsk(s)),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: context.colors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: context.appColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                const Icon(Icons.chat_bubble_outline_rounded, size: 18, color: _violet),
                const SizedBox(width: 10),
                Expanded(child: Text(text, style: context.text.bodyMedium)),
                Icon(Icons.north_east_rounded, size: 16, color: context.appColors.muted),
              ],
            ),
          ),
        ),
      );
}

// ---------------------------------------------------------------- Xabarlar

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final user = message.fromUser;
    final bg = user
        ? context.colors.primary
        : message.failed
        ? context.appColors.dangerContainer
        : context.colors.surfaceContainerLowest;
    final fg = user
        ? context.colors.onPrimary
        : message.failed
        ? context.appColors.danger
        : context.colors.onSurface;
    final maxW = MediaQuery.sizeOf(context).width * (user ? 0.78 : 0.88);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: user ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: bg,
                border: user ? null : Border.all(color: context.appColors.border),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(user ? 18 : 4),
                  bottomRight: Radius.circular(user ? 4 : 18),
                ),
              ),
              child: user
                  ? Text(message.text, style: TextStyle(color: fg, fontSize: 15, height: 1.35))
                  : SelectableText.rich(
                      richAssistantText(message.text, TextStyle(color: fg, fontSize: 15, height: 1.45)),
                    ),
            ),
          ),
          for (final a in message.attachments)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxW),
                child: switch (a) {
                  StudentAttachment() => _StudentCard(a: a),
                  GroupAttachment() => _GroupCard(a: a),
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// `**qalin**` va "* " / "- " ro'yxatlarini sodda ko'rinishga keltiradi
TextSpan richAssistantText(String text, TextStyle base) {
  final lines = text.split('\n').map((l) {
    final m = RegExp(r'^(\s*)[*-]\s+').firstMatch(l);
    return m == null ? l : '${m.group(1)}•  ${l.substring(m.end)}';
  }).join('\n');
  final parts = lines.split('**');
  return TextSpan(
    style: base,
    children: [
      for (final (i, p) in parts.indexed)
        TextSpan(text: p, style: i.isOdd ? const TextStyle(fontWeight: FontWeight.w700) : null),
    ],
  );
}

class _Typing extends StatefulWidget {
  const _Typing();

  @override
  State<_Typing> createState() => _TypingState();
}

class _TypingState extends State<_Typing> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: context.colors.surfaceContainerLowest,
          border: Border.all(color: context.appColors.border),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _c,
              builder: (context, _) => Row(
                children: [
                  for (var i = 0; i < 3; i++)
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _violet.withValues(
                          alpha: 0.3 + 0.7 * (0.5 + 0.5 * math.sin((_c.value * 2 * math.pi) - i * 0.9)).clamp(0, 1),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              "Ma'lumotlarni tahlil qilyapman…",
              style: context.text.bodySmall?.copyWith(color: context.appColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Kartalar

Color _percentColor(BuildContext context, double? p) => p == null
    ? context.appColors.muted
    : p >= 80
    ? context.appColors.success
    : p >= 60
    ? context.appColors.warning
    : context.appColors.danger;

class _StudentCard extends StatelessWidget {
  const _StudentCard({required this.a});

  final StudentAttachment a;

  @override
  Widget build(BuildContext context) {
    final (icon, tone) = switch (a.trend) {
      "o'smoqda" => (Icons.trending_up_rounded, StatusTone.success),
      'pasaymoqda' => (Icons.trending_down_rounded, StatusTone.danger),
      'barqaror' => (Icons.trending_flat_rounded, StatusTone.info),
      _ => (Icons.help_outline_rounded, StatusTone.neutral),
    };
    final initials = a.name.split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0]).join();
    return SectionCard(
      onTap: () => context.push('/students/${a.id}'),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Avatar(initials: initials, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Text(a.name, style: context.text.titleSmall, overflow: TextOverflow.ellipsis),
              ),
              StatusChip(label: a.trend, tone: tone, icon: icon),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Metric(
                label: "O'rtacha",
                value: a.avgPercent == null ? '—' : '${a.avgPercent!.round()}%',
                color: _percentColor(context, a.avgPercent),
              ),
              _Metric(
                label: "O'rni",
                value: a.rank == null ? '—' : '${a.rank}/${a.groupSize}',
                color: context.colors.onSurface,
              ),
              _Metric(
                label: 'Topshirmagan',
                value: '${a.missing}',
                color: a.missing > 0 ? context.appColors.danger : context.colors.onSurface,
              ),
            ],
          ),
          if (a.points.length >= 2) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              width: double.infinity,
              child: CustomPaint(painter: _Sparkline(a.points, _percentColor(context, a.avgPercent))),
            ),
            const SizedBox(height: 4),
            Text(
              'Oxirgi ${a.points.length} ta ish natijasi',
              style: context.text.labelSmall?.copyWith(color: context.appColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.a});

  final GroupAttachment a;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: context.colors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.groups_rounded, color: context.colors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(a.name, style: context.text.titleSmall, overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Metric(
                label: "O'rtacha",
                value: a.avgPercent == null ? '—' : '${a.avgPercent!.round()}%',
                color: _percentColor(context, a.avgPercent),
              ),
              _Metric(label: "O'quvchi", value: '${a.students}', color: context.colors.onSurface),
              _Metric(
                label: 'Topshirish',
                value: a.submissionRate == null ? '—' : '${a.submissionRate!.round()}%',
                color: _percentColor(context, a.submissionRate),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: context.text.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label, style: context.text.labelSmall?.copyWith(color: context.appColors.muted)),
          ],
        ),
      );
}

class _Sparkline extends CustomPainter {
  _Sparkline(this.points, this.color);

  final List<double> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // 0..100 foiz shkalasi: turli o'quvchilar kartalari bir xil ko'lamda
    Offset at(int i) => Offset(
          size.width * i / (points.length - 1),
          size.height - 4 - (size.height - 8) * (points[i].clamp(0, 100) / 100),
        );
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(at(points.length - 1), 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Sparkline old) => old.points != points || old.color != color;
}

// ---------------------------------------------------------------- Kiritish

class _Composer extends StatefulWidget {
  const _Composer({required this.controller, required this.sending, required this.onSend});

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final canSend = !widget.sending && widget.controller.text.trim().isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: context.appColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: widget.controller,
              minLines: 1,
              maxLines: 5,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => widget.onSend(),
              decoration: const InputDecoration(
                hintText: "Savolingizni yozing…",
                counterText: '',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 6),
          AnimatedScale(
            scale: canSend ? 1 : 0.9,
            duration: const Duration(milliseconds: 150),
            child: IconButton.filled(
              onPressed: canSend ? widget.onSend : null,
              style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
              icon: widget.sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.arrow_upward_rounded),
            ),
          ),
        ],
      ),
    );
  }
}
