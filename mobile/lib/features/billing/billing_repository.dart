import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';

class PlanOffer {
  const PlanOffer({
    required this.code,
    required this.name,
    required this.priceUzs,
    required this.maxGroups,
    required this.maxStudents,
  });

  final String code;
  final String name;
  final int priceUzs;
  final int maxGroups;
  final int maxStudents;

  factory PlanOffer.fromJson(Map<String, dynamic> j) => PlanOffer(
    code: j['code'] as String,
    name: j['name'] as String,
    priceUzs: j['price_uzs'] as int,
    maxGroups: j['max_groups'] as int,
    maxStudents: j['max_students'] as int,
  );
}

class PlanRequestItem {
  const PlanRequestItem({
    required this.id,
    required this.plan,
    required this.months,
    required this.amountUzs,
    this.discountUzs = 0,
    this.promoCode,
    required this.status,
    this.adminNote,
    required this.createdAt,
  });

  final String id;
  final PlanOffer plan;
  final int months;

  /// Chegirmadan keyingi to'lanadigan summa
  final int amountUzs;
  final int discountUzs;
  final String? promoCode;

  /// pending | approved | rejected
  final String status;
  final String? adminNote;
  final DateTime createdAt;

  bool get isPending => status == 'pending';

  factory PlanRequestItem.fromJson(Map<String, dynamic> j) => PlanRequestItem(
    id: j['id'] as String,
    plan: PlanOffer.fromJson(j['plan'] as Map<String, dynamic>),
    months: j['months'] as int,
    amountUzs: j['amount_uzs'] as int,
    discountUzs: (j['discount_uzs'] as int?) ?? 0,
    promoCode: j['promo_code'] as String?,
    status: j['status'] as String,
    adminNote: j['admin_note'] as String?,
    createdAt: DateTime.parse(j['created_at'] as String),
  );
}

/// Promo kod bilan hisoblangan narx
class PromoQuote {
  const PromoQuote({required this.code, required this.fullUzs, required this.discountUzs, required this.amountUzs});

  final String code;
  final int fullUzs;
  final int discountUzs;
  final int amountUzs;

  factory PromoQuote.fromJson(Map<String, dynamic> j) => PromoQuote(
    code: j['code'] as String,
    fullUzs: j['full_uzs'] as int,
    discountUzs: j['discount_uzs'] as int,
    amountUzs: j['amount_uzs'] as int,
  );
}

class PlansCatalog {
  const PlansCatalog({required this.plans, required this.requests});

  final List<PlanOffer> plans;
  final List<PlanRequestItem> requests;

  PlanRequestItem? get pending => requests.where((r) => r.isPending).firstOrNull;
}

final billingRepositoryProvider = Provider<BillingRepository>((ref) => BillingRepository(ref.watch(dioProvider)));

final plansCatalogProvider = FutureProvider.autoDispose<PlansCatalog>(
  (ref) => ref.watch(billingRepositoryProvider).catalog(),
);

class BillingRepository {
  BillingRepository(this._dio);

  final Dio _dio;

  Future<PlansCatalog> catalog() => guard(() async {
    final r = await _dio.get<Map<String, dynamic>>('/teachers/plans');
    final d = r.data!;
    return PlansCatalog(
      plans: [for (final p in d['plans'] as List) PlanOffer.fromJson(p as Map<String, dynamic>)],
      requests: [for (final p in d['requests'] as List) PlanRequestItem.fromJson(p as Map<String, dynamic>)],
    );
  });

  Future<PromoQuote> checkPromo({required String planCode, required int months, required String code}) =>
      guard(() async {
        final r = await _dio.post<Map<String, dynamic>>(
          '/teachers/me/promo-check',
          data: {'plan_code': planCode, 'months': months, 'code': code},
        );
        return PromoQuote.fromJson(r.data!);
      });

  Future<PlanRequestItem> request({required String planCode, required int months, String? note, String? promoCode}) =>
      guard(() async {
        final r = await _dio.post<Map<String, dynamic>>(
          '/teachers/me/plan-requests',
          data: {
            'plan_code': planCode,
            'months': months,
            if (note != null && note.isNotEmpty) 'note': note,
            if (promoCode != null && promoCode.isNotEmpty) 'promo_code': promoCode,
          },
        );
        return PlanRequestItem.fromJson(r.data!);
      });
}

/// 140000 -> "140 000"
String formatSum(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}
