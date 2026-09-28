import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_widgets.dart';
import '../billing/billing_repository.dart' show formatSum;
import '../gamification/presentation/hex_badge.dart';
import 'extras_repository.dart';

IconData jetonIcon(String key) => badgeIcons[key] ?? Icons.star_rounded;

/// O'qituvchining jetonlari: adminlardan sotib olinadi, yaxshi o'qigan o'quvchiga sovg'a qilinadi
class TeacherJetonsScreen extends ConsumerWidget {
  const TeacherJetonsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(jetonWalletProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Jetonlarim')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(jetonWalletProvider.future),
        child: wallet.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(jetonWalletProvider)),
          data: (w) => ListView(
            padding: Insets.screen.copyWith(top: 8, bottom: 32),
            children: [
              _WalletHeader(w: w),
              const SizedBox(height: 18),
              const InfoBanner(
                icon: Icons.card_giftcard_rounded,
                text: "Jetonni o'quvchining profilidan sovg'a qilasiz: guruh → o'quvchi → «Jeton sovg'a qilish». "
                    "O'quvchi uni o'z nishonlari orasida ismingiz bilan ko'radi.",
              ),
              const SizedBox(height: 22),
              Text('Jetonlar', style: context.text.titleLarge),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.78,
                children: [
                  for (final j in w.catalog)
                    _JetonCard(j: j, balance: w.balanceOf(j.code), onBuy: () => _buy(context, ref, j)),
                ],
              ),
              if (w.orders.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('Buyurtmalarim', style: context.text.titleMedium),
                const SizedBox(height: 10),
                SectionCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      for (final (i, o) in w.orders.indexed) ...[
                        if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                        _OrderTile(o: o, name: w.catalog.where((j) => j.code == o.code).firstOrNull?.name ?? o.code),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _buy(BuildContext context, WidgetRef ref, GiftJeton j) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _BuySheet(j: j),
    );
    if (sent == true && context.mounted) {
      ref.invalidate(jetonWalletProvider);
      showSnack(context, "Buyurtma yuborildi. To'lov tasdiqlangach jetonlar hisobingizga tushadi");
    }
  }
}

class _WalletHeader extends StatelessWidget {
  const _WalletHeader({required this.w});

  final JetonWallet w;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF59E0B), Color(0xFFEA580C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: const Color(0xFFEA580C).withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Qo'limdagi jetonlar", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text('${w.total}',
                    style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800, height: 1)),
                const SizedBox(height: 8),
                Text("${w.given} ta sovg'a qilingan",
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          const HexBadge(tier: 'gold', icon: Icons.card_giftcard_rounded, size: 76),
        ],
      ),
    );
  }
}

class _JetonCard extends StatelessWidget {
  const _JetonCard({required this.j, required this.balance, required this.onBuy});

  final GiftJeton j;
  final int balance;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      onTap: onBuy,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              HexBadge(tier: j.tier, icon: jetonIcon(j.icon), size: 66),
              if (balance > 0)
                Positioned(
                  right: -6,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: context.appColors.success, borderRadius: BorderRadius.circular(100)),
                    child: Text('$balance',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(j.name, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Expanded(
            child: Text(j.description, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
          ),
          Text("${formatSum(j.priceUzs)} so'm",
              style: context.text.labelLarge?.copyWith(color: context.colors.primary, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.o, required this.name});

  final JetonOrder o;
  final String name;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (o.status) {
      'approved' => ('Tasdiqlandi', StatusTone.success),
      'rejected' => ('Rad etildi', StatusTone.danger),
      _ => ('Kutilmoqda', StatusTone.warning),
    };
    return ListTile(
      title: Text('$name × ${o.quantity}'),
      subtitle: Text("${formatSum(o.amountUzs)} so'm · ${formatDateUz(o.createdAt)}"),
      trailing: StatusChip(label: label, tone: tone),
    );
  }
}

class _BuySheet extends ConsumerStatefulWidget {
  const _BuySheet({required this.j});

  final GiftJeton j;

  @override
  ConsumerState<_BuySheet> createState() => _BuySheetState();
}

class _BuySheetState extends ConsumerState<_BuySheet> {
  final _note = TextEditingController();
  int _qty = 5;
  bool _loading = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _loading = true);
    try {
      await ref.read(extrasRepositoryProvider).orderJetons(widget.j.code, _qty, _note.text.trim());
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final j = widget.j;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                HexBadge(tier: j.tier, icon: jetonIcon(j.icon), size: 58),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(j.name, style: context.text.titleLarge),
                      Text(j.description, style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Text('Soni', style: context.text.titleMedium),
                const Spacer(),
                IconButton.filledTonal(
                  onPressed: _qty > 1 ? () => setState(() => _qty -= 1) : null,
                  icon: const Icon(Icons.remove_rounded),
                ),
                SizedBox(
                  width: 56,
                  child: Text('$_qty', textAlign: TextAlign.center,
                      style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                ),
                IconButton.filledTonal(
                  onPressed: _qty < 500 ? () {
                    HapticFeedback.selectionClick();
                    setState(() => _qty += 1);
                  } : null,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final n in [5, 10, 20, 50])
                  ChoiceChip(label: Text('$n ta'), selected: _qty == n, onSelected: (_) => setState(() => _qty = n)),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Text('Jami', style: context.text.titleMedium),
                const Spacer(),
                Text("${formatSum(j.priceUzs * _qty)} so'm",
                    style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: context.colors.primary)),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _note,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'Izoh (ixtiyoriy)',
                hintText: 'Masalan: Telegram @username yoki qulay aloqa vaqti',
                counterText: '',
              ),
            ),
            const SizedBox(height: 8),
            const InfoBanner(
              icon: Icons.support_agent_rounded,
              text: "Onlayn to'lov tez orada. Hozircha buyurtma yuborasiz, admin bog'lanib to'lovni qabul qiladi va "
                  'jetonlar hisobingizga darhol tushadi.',
            ),
            const SizedBox(height: 18),
            PrimaryButton(label: 'Buyurtma berish', icon: Icons.shopping_bag_rounded, loading: _loading, onPressed: _send),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- O'quvchiga sovg'a qilish

Future<void> showGiftSheet(BuildContext context, WidgetRef ref, {required String studentId, required String name}) async {
  final gifted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _GiftSheet(studentId: studentId, name: name),
  );
  if (gifted == true && context.mounted) {
    showSnack(context, "Jeton sovg'a qilindi! $name uni nishonlari orasida ko'radi");
  }
}

class _GiftSheet extends ConsumerStatefulWidget {
  const _GiftSheet({required this.studentId, required this.name});

  final String studentId;
  final String name;

  @override
  ConsumerState<_GiftSheet> createState() => _GiftSheetState();
}

class _GiftSheetState extends ConsumerState<_GiftSheet> {
  final _note = TextEditingController();
  String? _code;
  bool _loading = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _gift() async {
    final code = _code;
    if (code == null) return;
    setState(() => _loading = true);
    try {
      await ref.read(extrasRepositoryProvider).giftJeton(widget.studentId, code, _note.text.trim());
      ref.invalidate(jetonWalletProvider);
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(jetonWalletProvider);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: wallet.when(
          loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(jetonWalletProvider)),
          data: (w) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("${widget.name}ga jeton", style: context.text.titleLarge),
              const SizedBox(height: 4),
              Text('Qaysi jetonni sovg\'a qilasiz?',
                  style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant)),
              const SizedBox(height: 14),
              if (w.total == 0)
                const InfoBanner(
                  tone: StatusTone.warning,
                  icon: Icons.info_outline_rounded,
                  text: "Hozircha jetoningiz yo'q. Profil → «Jetonlarim» bo'limidan sotib oling.",
                )
              else
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final j in w.catalog.where((j) => w.balanceOf(j.code) > 0))
                      _GiftOption(
                        j: j,
                        balance: w.balanceOf(j.code),
                        selected: _code == j.code,
                        onTap: () => setState(() => _code = j.code),
                      ),
                  ],
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _note,
                maxLength: 200,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: "Tabrik so'zi (ixtiyoriy)",
                  hintText: 'Masalan: Barakalla, shunday davom et!',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 14),
              PrimaryButton(
                label: "Sovg'a qilish",
                icon: Icons.card_giftcard_rounded,
                loading: _loading,
                onPressed: _code == null ? null : _gift,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GiftOption extends StatelessWidget {
  const _GiftOption({required this.j, required this.balance, required this.selected, required this.onTap});

  final GiftJeton j;
  final int balance;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = context.colors.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 100,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: selected ? primary.withValues(alpha: 0.1) : context.colors.surfaceContainerLowest,
          border: Border.all(color: selected ? primary : context.appColors.border, width: selected ? 2 : 1),
        ),
        child: Column(
          children: [
            HexBadge(tier: j.tier, icon: jetonIcon(j.icon), size: 48),
            const SizedBox(height: 6),
            Text(j.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelMedium),
            Text('$balance ta', style: context.text.labelSmall?.copyWith(color: context.appColors.muted)),
          ],
        ),
      ),
    );
  }
}
