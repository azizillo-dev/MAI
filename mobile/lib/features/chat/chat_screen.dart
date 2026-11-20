import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_widgets.dart';
import 'chat_repository.dart';

/// Ustoz ↔ o'quvchi suhbati.
///
/// [conversationId] (ro'yxatdan) yoki [peerId] (profildan "Xabar yozish") bilan ochiladi.
/// Yangi xabarlar har 4 soniyada so'raladi; ekran yopilsa so'rov to'xtaydi.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, this.conversationId, this.peerId});

  final String? conversationId;
  final String? peerId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _Pending {
  _Pending(this.localId, this.text);

  final String localId;
  final String text;
  bool failed = false;
}

class _ChatScreenState extends ConsumerState<ChatScreen> with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  Conversation? _conv;
  Object? _error;
  final List<ChatMessage> _messages = [];
  final List<_Pending> _pending = [];
  Timer? _poll;
  bool _loadingOlder = false;
  bool _hasOlder = true;
  bool _active = true;

  ChatRepository get _repo => ref.read(chatRepositoryProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Ilova fonda bo'lsa so'ramaymiz (batareya va trafik)
    _active = state == AppLifecycleState.resumed;
    if (_active) _fetchNew();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final conv = widget.conversationId != null
          ? await _repo.get(widget.conversationId!)
          : await _repo.openWith(widget.peerId!);
      final msgs = await _repo.messages(conv.id);
      if (!mounted) return;
      setState(() {
        _conv = conv;
        _messages
          ..clear()
          ..addAll(msgs);
        _hasOlder = msgs.length >= 50;
      });
      _markRead();
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 4), (_) => _fetchNew());
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _fetchNew() async {
    final conv = _conv;
    if (conv == null || !_active || !mounted) return;
    try {
      final last = _messages.lastOrNull?.raw;
      final fresh = await _repo.messages(conv.id, after: last);
      final updated = await _repo.get(conv.id); // "o'qildi" belgisi va yozish huquqi
      if (!mounted) return;
      final known = _messages.map((m) => m.id).toSet();
      final add = fresh.where((m) => !known.contains(m.id)).toList();
      setState(() {
        _conv = updated;
        _messages.addAll(add);
      });
      if (add.any((m) => !m.fromMe)) _markRead();
    } on Object {
      // Vaqtincha tarmoq xatosi: keyingi so'rovda qayta urinadi
    }
  }

  void _markRead() {
    final conv = _conv;
    if (conv == null) return;
    _repo.markRead(conv.id).then((_) => ref.invalidate(chatUnreadProvider), onError: (_) {});
  }

  void _onScroll() {
    // Ro'yxat teskari: yuqoriga (eskilarga) yetganda oldingi xabarlarni yuklaymiz
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 200) _loadOlder();
  }

  Future<void> _loadOlder() async {
    final conv = _conv;
    if (conv == null || _loadingOlder || !_hasOlder || _messages.isEmpty) return;
    _loadingOlder = true;
    try {
      final older = await _repo.messages(conv.id, before: _messages.first.raw);
      if (!mounted) return;
      setState(() {
        _messages.insertAll(0, older);
        _hasOlder = older.length >= 50;
      });
    } on Object {
      // keyingi aylantirishda qayta urinadi
    } finally {
      _loadingOlder = false;
    }
  }

  Future<void> _send([_Pending? retry]) async {
    final conv = _conv;
    final text = retry?.text ?? _input.text.trim();
    if (conv == null || text.isEmpty) return;
    HapticFeedback.lightImpact();
    final p = retry ?? _Pending('${DateTime.now().microsecondsSinceEpoch}', text);
    setState(() {
      if (retry == null) {
        _pending.add(p);
        _input.clear();
      } else {
        p.failed = false;
      }
    });
    try {
      final msg = await _repo.send(conv.id, text);
      if (!mounted) return;
      setState(() {
        _pending.remove(p);
        if (!_messages.any((m) => m.id == msg.id)) _messages.add(msg);
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => p.failed = true);
      if (e is ApiException && e.status == 403) {
        _fetchNew();
      }
      showSnack(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final conv = _conv;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: conv == null
            ? const Text('Xabarlar')
            : InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: conv.peer.isTeacher ? null : () => context.push('/students/${conv.peer.id}'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Avatar(initials: conv.peer.initials, imageUrl: conv.peer.avatarUrl, size: 40),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(conv.peer.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleMedium),
                            Text(
                              conv.peer.isTeacher ? 'Ustoz' : "O'quvchi",
                              style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
      body: _error != null
          ? ErrorRetry(error: _error!, onRetry: _load)
          : conv == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(child: _buildList(context, conv)),
                    if (conv.canSend)
                      _Composer(controller: _input, onSend: _send)
                    else
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                          child: InfoBanner(
                            tone: StatusTone.neutral,
                            icon: Icons.lock_outline_rounded,
                            text: conv.peer.isTeacher
                                ? "Siz endi bu ustozning guruhida emassiz — yangi xabar yuborib bo'lmaydi"
                                : "O'quvchi endi guruhingizda emas — yangi xabar yuborib bo'lmaydi",
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }

  Widget _buildList(BuildContext context, Conversation conv) {
    if (_messages.isEmpty && _pending.isEmpty) {
      return _EmptyChat(
        peer: conv.peer,
        onPick: conv.canSend
            ? (t) {
                _input.text = t;
                _input.selection = TextSelection.collapsed(offset: t.length);
              }
            : null,
      );
    }
    // Teskari ro'yxat: eng yangi xabar pastda, klaviatura ochilganda ham ko'rinib turadi
    final items = <Widget>[];
    final lastMine = _messages.lastWhereOrNull((m) => m.fromMe);
    final read = lastMine != null && conv.peerReadAt != null && !conv.peerReadAt!.isBefore(lastMine.createdAt);
    for (final p in _pending.reversed) {
      items.add(_Bubble(text: p.text, mine: true, time: null, failed: p.failed, onRetry: () => _send(p)));
    }
    for (var i = _messages.length - 1; i >= 0; i--) {
      final m = _messages[i];
      final next = i + 1 < _messages.length ? _messages[i + 1] : null;
      final prev = i > 0 ? _messages[i - 1] : null;
      // Bir kishining ketma-ket xabarlari bir guruh: oraliq kichik, "dum" faqat oxirgisida
      final tail = next == null || next.fromMe != m.fromMe || next.createdAt.difference(m.createdAt).inMinutes > 5;
      items.add(_Bubble(
        text: m.text,
        mine: m.fromMe,
        time: m.createdAt,
        tail: tail,
        status: identical(m, lastMine) ? (read ? _Status.read : _Status.sent) : null,
      ));
      if (prev == null || !_sameDay(prev.createdAt, m.createdAt)) items.add(_DayChip(day: m.createdAt));
    }
    return ListView(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      children: items,
    );
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}

extension<T> on List<T> {
  T? lastWhereOrNull(bool Function(T) test) {
    for (var i = length - 1; i >= 0; i--) {
      if (test(this[i])) return this[i];
    }
    return null;
  }
}

enum _Status { sent, read }

String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.text,
    required this.mine,
    required this.time,
    this.tail = true,
    this.status,
    this.failed = false,
    this.onRetry,
  });

  final String text;
  final bool mine;
  final DateTime? time;
  final bool tail;
  final _Status? status;
  final bool failed;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.colors.primary;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = mine ? p : (dark ? const Color(0xFF1E293B) : Colors.white);
    final fg = mine ? Colors.white : context.colors.onSurface;
    final meta = mine ? Colors.white.withValues(alpha: 0.75) : context.colors.onSurfaceVariant;
    const r = Radius.circular(20);
    const small = Radius.circular(6);
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
      padding: const EdgeInsets.fromLTRB(14, 9, 12, 7),
      decoration: BoxDecoration(
        color: failed ? context.appColors.dangerContainer : bg,
        borderRadius: BorderRadius.only(
          topLeft: r,
          topRight: r,
          bottomLeft: mine || !tail ? r : small,
          bottomRight: mine && tail ? small : r,
        ),
        boxShadow: mine || dark
            ? null
            : [BoxShadow(color: Palette.slate900.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: 8,
        children: [
          SelectableText(text, style: TextStyle(color: failed ? context.colors.onSurface : fg, fontSize: 15.5, height: 1.35)),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (time != null)
                  Text(_hm(time!), style: TextStyle(color: failed ? context.appColors.danger : meta, fontSize: 11)),
                if (mine && time == null && !failed)
                  Icon(Icons.schedule_rounded, size: 13, color: meta),
                if (failed) Icon(Icons.error_outline_rounded, size: 15, color: context.appColors.danger),
                if (status != null) ...[
                  const SizedBox(width: 3),
                  Icon(status == _Status.read ? Icons.done_all_rounded : Icons.done_rounded, size: 15, color: meta),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: EdgeInsets.only(top: tail ? 8 : 2),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: failed
            ? GestureDetector(
                onTap: onRetry,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    bubble,
                    Padding(
                      padding: const EdgeInsets.only(top: 4, right: 4),
                      child: Text(
                        "Yuborilmadi · qayta urinish uchun bosing",
                        style: TextStyle(fontSize: 12, color: context.appColors.danger, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              )
            : bubble,
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(day.year, day.month, day.day);
    final diff = today.difference(d).inDays;
    final label = diff == 0
        ? 'Bugun'
        : diff == 1
            ? 'Kecha'
            : d.year == now.year
                ? '${d.day}-${uzMonths[d.month - 1]}'
                : '${d.day}-${uzMonths[d.month - 1]}, ${d.year}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: context.colors.surfaceContainer,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.colors.onSurfaceVariant)),
        ),
      ),
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({required this.controller, required this.onSend});

  final TextEditingController controller;
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
    final canSend = widget.controller.text.trim().isNotEmpty;
    final p = context.colors.primary;
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 10, 10),
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
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    hintText: 'Xabar yozing',
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    enabledBorder:
                        OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(color: p.withValues(alpha: 0.5)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedScale(
                scale: canSend ? 1 : 0.85,
                duration: const Duration(milliseconds: 160),
                child: Material(
                  color: canSend ? p : context.colors.surfaceContainer,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: canSend ? widget.onSend : null,
                    child: SizedBox.square(
                      dimension: 48,
                      child: Icon(
                        Icons.send_rounded,
                        size: 22,
                        color: canSend ? Colors.white : context.colors.onSurfaceVariant,
                        semanticLabel: 'Yuborish',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.peer, this.onPick});

  final ChatPeer peer;
  final ValueChanged<String>? onPick;

  @override
  Widget build(BuildContext context) {
    final first = peer.fullName.split(' ').first;
    // Tez boshlash uchun tayyor jumlalar (bosilsa — maydonga tushadi, tahrirlab yuborsa bo'ladi)
    final quick = peer.isTeacher
        ? ["Assalomu alaykum, ustoz!", "Vazifani tushunmadim, yordam bera olasizmi?", "Ishimni qayta tekshirib bering"]
        : ["Assalomu alaykum, $first!", "Uy vazifangizni ko'rdim — barakalla!", "Oxirgi ishingizni birga ko'rib chiqamiz"];
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      children: [
        Center(child: Avatar(initials: peer.initials, imageUrl: peer.avatarUrl, size: 84)),
        const SizedBox(height: 14),
        Text(peer.fullName, textAlign: TextAlign.center, style: context.text.titleLarge),
        const SizedBox(height: 6),
        Text(
          peer.isTeacher ? "Ustozingizga savolingizni yozing" : "$first bilan suhbatni boshlang",
          textAlign: TextAlign.center,
          style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
        ),
        if (onPick != null) ...[
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [for (final q in quick) ActionChip(label: Text(q), onPressed: () => onPick!(q))],
          ),
        ],
      ],
    );
  }
}
