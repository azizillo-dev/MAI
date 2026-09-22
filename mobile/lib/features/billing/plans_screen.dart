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
                  text: "${p.plan.name}, ${p.months} oy — ${formatSum(p.amountUzs)} so'm. "
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
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
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
          if (r.adminNote case final n? when n.isNotEmpty) n,
        ].join('\n'),
      ),
      isThreeLine: r.adminNote?.isNotEmpty ?? false,
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
  int _months = 1;
  bool _loading = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _loading = true);
    try {
      await ref.read(billingRepositoryProvider).request(
            planCode: widget.plan.code,
            months: _months,
            note: _note.text.trim(),
          );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.plan.priceUzs * _months;
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
              onSelectionChanged: (s) => setState(() => _months = s.first),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Text('Jami', style: context.text.titleMedium),
                const Spacer(),
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
              text: "Onlayn to'lov tez orada qo'shiladi. Hozircha so'rov yuborasiz, admin siz bilan bog'lanib "
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
