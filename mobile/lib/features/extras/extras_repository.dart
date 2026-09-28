import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';

// ---------------------------------------------------------------- Yordam va taklif

class SupportMessage {
  const SupportMessage({
    required this.id,
    required this.kind,
    required this.text,
    required this.status,
    this.adminReply,
    required this.createdAt,
  });

  final String id;
  final String kind; // help | suggestion | bug
  final String text;
  final String status; // open | answered | closed
  final String? adminReply;
  final DateTime createdAt;

  factory SupportMessage.fromJson(Map<String, dynamic> j) => SupportMessage(
        id: j['id'] as String,
        kind: j['kind'] as String,
        text: j['text'] as String,
        status: j['status'] as String,
        adminReply: j['admin_reply'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      );
}

// ---------------------------------------------------------------- Jetonlar

class GiftJeton {
  const GiftJeton({
    required this.code,
    required this.name,
    required this.description,
    required this.icon,
    required this.tier,
    required this.priceUzs,
  });

  final String code;
  final String name;
  final String description;
  final String icon;
  final String tier;
  final int priceUzs;

  factory GiftJeton.fromJson(Map<String, dynamic> j) => GiftJeton(
        code: j['code'] as String,
        name: j['name'] as String,
        description: j['description'] as String,
        icon: j['icon'] as String,
        tier: j['tier'] as String,
        priceUzs: j['price_uzs'] as int,
      );
}

class JetonOrder {
  const JetonOrder({
    required this.id,
    required this.code,
    required this.quantity,
    required this.amountUzs,
    required this.status,
    this.adminNote,
    required this.createdAt,
  });

  final String id;
  final String code;
  final int quantity;
  final int amountUzs;
  final String status;
  final String? adminNote;
  final DateTime createdAt;

  factory JetonOrder.fromJson(Map<String, dynamic> j) => JetonOrder(
        id: j['id'] as String,
        code: j['jeton_code'] as String,
        quantity: j['quantity'] as int,
        amountUzs: j['amount_uzs'] as int,
        status: j['status'] as String,
        adminNote: j['admin_note'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      );
}

class JetonWallet {
  const JetonWallet({required this.catalog, required this.balances, required this.orders, required this.given});

  final List<GiftJeton> catalog;
  final Map<String, int> balances;
  final List<JetonOrder> orders;
  final int given;

  int get total => balances.values.fold(0, (a, b) => a + b);
  int balanceOf(String code) => balances[code] ?? 0;

  factory JetonWallet.fromJson(Map<String, dynamic> j) => JetonWallet(
        catalog: [for (final x in j['catalog'] as List) GiftJeton.fromJson(x as Map<String, dynamic>)],
        balances: {for (final e in (j['balances'] as Map).entries) e.key as String: e.value as int},
        orders: [for (final x in j['orders'] as List) JetonOrder.fromJson(x as Map<String, dynamic>)],
        given: j['given'] as int? ?? 0,
      );
}

final extrasRepositoryProvider = Provider<ExtrasRepository>((ref) => ExtrasRepository(ref.watch(dioProvider)));

final supportMessagesProvider = FutureProvider.autoDispose<List<SupportMessage>>(
  (ref) => ref.watch(extrasRepositoryProvider).mySupport(),
);

final jetonWalletProvider = FutureProvider.autoDispose<JetonWallet>(
  (ref) => ref.watch(extrasRepositoryProvider).wallet(),
);

class ExtrasRepository {
  ExtrasRepository(this._dio);

  final Dio _dio;

  Future<List<SupportMessage>> mySupport() => guard(() async {
        final r = await _dio.get<List<dynamic>>('/support');
        return [for (final x in r.data!) SupportMessage.fromJson(x as Map<String, dynamic>)];
      });

  Future<SupportMessage> sendSupport(String kind, String text) => guard(() async {
        final r = await _dio.post<Map<String, dynamic>>('/support', data: {'kind': kind, 'text': text});
        return SupportMessage.fromJson(r.data!);
      });

  Future<JetonWallet> wallet() => guard(() async {
        final r = await _dio.get<Map<String, dynamic>>('/teachers/jetons');
        return JetonWallet.fromJson(r.data!);
      });

  Future<void> orderJetons(String code, int quantity, String? note) => guard(() async {
        await _dio.post<Map<String, dynamic>>('/teachers/me/jeton-orders',
            data: {'jeton_code': code, 'quantity': quantity, if (note != null && note.isNotEmpty) 'note': note});
      });

  Future<void> giftJeton(String studentId, String code, String? note) => guard(() async {
        await _dio.post<Map<String, dynamic>>('/teachers/me/jetons/gift',
            data: {'student_id': studentId, 'jeton_code': code, if (note != null && note.isNotEmpty) 'note': note});
      });

  /// Guruh hisobotini yuklab oladi (fayl baytlari).
  Future<List<int>> groupReport(String groupId, String format, String period) => guard(() async {
        final r = await _dio.get<List<int>>(
          '/groups/$groupId/report.$format',
          queryParameters: {'period': period},
          options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 60)),
        );
        return r.data!;
      });
}
