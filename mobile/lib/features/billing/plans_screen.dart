import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_widgets.dart';
import '../groups/data/groups_repository.dart';
import '../teacher/home/teacher_home_screen.dart' show PlanCard;
import 'billing_repository.dart';

/// Tariflar: joriy holat, Standart/Pro kartalari va to'lov so'rovlari.
/// Hozircha to'lov tizimi yo'q — o'qituvchi so'rov yuboradi, admin to'lovni tasdiqlaydi.
class PlansScreen extends ConsumerWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(planUsageProvider);
    final catalog = ref.watch(plansCatalogProvider);

    Future<void> refresh() async {
      ref.invalidate(planUsageProvider);
      ref.invalidate(plansCatalogProvider);
      await ref.read(plansCatalogProvider.future);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Tariflar')),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: catalog.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorRetry(error: e, onRetry: refresh),
          data: (c) => ListView(
            padding: Insets.screen.copyWith(top: 8, bottom: 32),
            children: [
              if (usage.value case final u?) PlanCard(plan: u, showManage: false),
              if (c.pending case final p?) ...[
                const SizedBox(height: 14),
                InfoBanner(
                  tone: StatusTone.warning,
                  icon: Icons.hourglass_top_rounded,
                  title: "So'rov ko'rib chiqilmoqda",
                  text:
                      "${p.plan.name}, ${p.months} oy — ${formatSum(p.amountUzs)} so'm. "
                      "Admin siz bilan bog'lanadi, to'lov tasdiqlangach tarif darhol yoqiladi.",
                ),
              ],
              const SizedBox(height: 24),
              Text('Tarifni tanlang', style: context.text.titleLarge),
              const SizedBox(height: 4),
              Text(
                "Barcha tariflarda AI tekshiruv, AI yordamchi va reyting to'liq ishlaydi",
                style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              for (final plan in c.plans) ...[
                _OfferCard(
                  plan: plan,
                  current: usage.value?.planCode == plan.code && usage.value?.isExpired == false,
                  highlighted: plan.code == 'pro',
                  enabled: c.pending == null,
                  onChoose: () => _choose(context, ref, plan),
                ),
                const SizedBox(height: 12),
              ],
              if (c.requests.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text("So'rovlarim", style: context.text.titleMedium),
                const SizedBox(height: 10),
                SectionCard(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      for (final (i, r) in c.requests.indexed) ...[
                        if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                        _RequestTile(r: r),
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

  Future<void> _choose(BuildContext context, WidgetRef ref, PlanOffer plan) async {
    final sent = await showModalBottomSheet<bool>(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _RequestSheet(plan: plan),
    );
    if (sent == true && context.mounted) {
      ref.invalidate(plansCatalogProvider);
      showSnack(context, "So'rov yuborildi. Admin tez orada bog'lanadi");
    }
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.plan,
    required this.current,
    required this.highlighted,
    required this.enabled,
    required this.onChoose,
  });

  final PlanOffer plan;
  final bool current;
  final bool highlighted;
  final bool enabled;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final accent = highlighted ? Palette.gold : context.colors.primary;
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: highlighted ? accent : context.appColors.border, width: highlighted ? 1.6 : 1),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(highlighted ? Icons.workspace_premium_rounded : Icons.star_rounded, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(plan.name, style: context.text.titleMedium)),
              if (current)
                const StatusChip(label: 'Joriy', tone: StatusTone.success, icon: Icons.check_rounded)
              else if (highlighted)
                const StatusChip(label: "Ko'p guruhli", tone: StatusTone.warning),
            ],
          ),
          const SizedBox(height: 14),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: formatSum(plan.priceUzs),
                  style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                TextSpan(
                  text: " so'm / oy",
                  style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Feature(icon: Icons.groups_rounded, text: '${plan.maxGroups} ta guruh'),
          _Feature(icon: Icons.person_rounded, text: "${plan.maxStudents} tagacha o'quvchi"),
          const _Feature(icon: Icons.auto_awesome_rounded, text: 'AI tekshiruv va AI yordamchi'),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: highlighted
                ? FilledButton(onPressed: enabled ? onChoose : null, child: Text(current ? 'Uzaytirish' : 'Tanlash'))
                : OutlinedButton(onPressed: enabled ? onChoose : null, child: Text(current ? 'Uzaytirish' : 'Tanlash')),
          ),
        ],
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      children: [
        Icon(icon, size: 18, color: context.appColors.success),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: context.text.bodyMedium)),
      ],
    ),
  );
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.r});

  final PlanRequestItem r;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (r.status) {
      'approved' => ('Tasdiqlandi', StatusTone.success),
      'rejected' => ('Rad etildi', StatusTone.danger),
      _ => ('Kutilmoqda', StatusTone.warning),
    };
    return ListTile(
      title: Text('${r.plan.name} · ${r.months} oy'),
      subtitle: Text(
        [
          "${formatSum(r.amountUzs)} so'm · ${formatDateUz(r.createdAt.toLocal())}",
          if (r.promoCode case final c?) "Promo kod $c: −${formatSum(r.discountUzs)} so'm",
          if (r.adminNote case final n? when n.isNotEmpty) n,
        ].join('\n'),
      ),
      isThreeLine: (r.adminNote?.isNotEmpty ?? false) || r.promoCode != null,
      trailing: StatusChip(label: label, tone: tone),
    );
  }
}

class _RequestSheet extends ConsumerStatefulWidget {
  const _RequestSheet({required this.plan});

  final PlanOffer plan;

  @override
  ConsumerState<_RequestSheet> createState() => _RequestSheetState();
}

class _RequestSheetState extends ConsumerState<_RequestSheet> {
  static const _options = [1, 3, 6, 12];
  final _note = TextEditingController();
  final _promo = TextEditingController();
  int _months = 1;
  bool _loading = false;
  bool _promoOpen = false;
  bool _checking = false;
  PromoQuote? _quote;
  String? _promoError;

  @override
  void dispose() {
    _note.dispose();
    _promo.dispose();
    super.dispose();
  }

  Future<void> _applyPromo() async {
    final code = _promo.text.trim();
    if (code.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _checking = true;
      _promoError = null;
    });
    try {
      final q = await ref
          .read(billingRepositoryProvider)
          .checkPromo(planCode: widget.plan.code, months: _months, code: code);
      if (mounted) setState(() => _quote = q);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _quote = null;
          _promoError = e.message;
        });
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _removePromo() => setState(() {
    _quote = null;
    _promoError = null;
    _promo.clear();
  });

  void _setMonths(int m) {
    setState(() => _months = m);
    // Muddat o'zgarsa chegirma ham qayta hisoblanadi (foizli kod summaga bog'liq)
    if (_quote != null) _applyPromo();
  }

  Future<void> _send() async {
    setState(() => _loading = true);
    try {
      await ref
          .read(billingRepositoryProvider)
          .request(planCode: widget.plan.code, months: _months, note: _note.text.trim(), promoCode: _quote?.code);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code.startsWith('PROMO_')) {
        setState(() {
          _quote = null;
          _promoError = e.message;
        });
      } else {
        showSnack(context, e.message, error: true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _promoSection(BuildContext context) {
    final q = _quote;
    if (q != null) {
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        decoration: BoxDecoration(color: context.appColors.successContainer, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            Icon(Icons.local_offer_rounded, color: context.appColors.success, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: q.code,
                      style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: .5),
                    ),
                    TextSpan(text: " qo'llandi · −${formatSum(q.discountUzs)} so'm"),
                  ],
                ),
                style: context.text.bodyMedium?.copyWith(color: context.appColors.success),
              ),
            ),
            IconButton(
              tooltip: 'Olib tashlash',
              onPressed: _removePromo,
              icon: Icon(Icons.close_rounded, color: context.appColors.success, size: 20),
            ),
          ],
        ),
      );
    }
    if (!_promoOpen) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _promoOpen = true),
          icon: const Icon(Icons.local_offer_outlined, size: 18),
          label: const Text('Promo kodingiz bormi?'),
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: _promo,
            autofocus: true,
            maxLength: 32,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _applyPromo(),
            onChanged: (_) {
              if (_promoError != null) setState(() => _promoError = null);
            },
            decoration: InputDecoration(
              labelText: 'Promo kod',
              hintText: 'Masalan: USTOZ20',
              counterText: '',
              errorText: _promoError,
              errorMaxLines: 2,
              prefixIcon: const Icon(Icons.local_offer_outlined),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Mavzudagi tugmalar butun kenglikni egallaydi — Row ichida o'lchamni aniq beramiz
        FilledButton.tonal(
          style: FilledButton.styleFrom(minimumSize: const Size(96, 56)),
          onPressed: _checking ? null : _applyPromo,
          child: _checking
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text("Qo'llash"),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final full = widget.plan.priceUzs * _months;
    final total = _quote?.amountUzs ?? full;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${widget.plan.name} tarif', style: context.text.titleLarge),
            const SizedBox(height: 18),
            Text('Muddat', style: context.text.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [for (final m in _options) ButtonSegment(value: m, label: Text('$m oy'))],
              selected: {_months},
              onSelectionChanged: (s) => _setMonths(s.first),
            ),
            const SizedBox(height: 14),
            _promoSection(context),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Jami', style: context.text.titleMedium),
                const Spacer(),
                if (total != full) ...[
                  Text(
                    formatSum(full),
                    style: context.text.bodyLarge?.copyWith(
                      color: context.colors.onSurfaceVariant,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  "${formatSum(total)} so'm",
                  style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: context.colors.primary),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              maxLength: 300,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Izoh (ixtiyoriy)',
                hintText: "Masalan: Telegram @username yoki qulay aloqa vaqti",
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            const InfoBanner(
              icon: Icons.support_agent_rounded,
              text:
                  "Onlayn to'lov tez orada qo'shiladi. Hozircha so'rov yuborasiz, admin siz bilan bog'lanib "
                  "to'lovni qabul qiladi va tarif shu zahoti yoqiladi.",
            ),
            const SizedBox(height: 20),
            PrimaryButton(label: "So'rov yuborish", icon: Icons.send_rounded, loading: _loading, onPressed: _send),
          ],
        ),
      ),
    );
  }
}
