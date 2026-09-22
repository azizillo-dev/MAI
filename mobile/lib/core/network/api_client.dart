import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';
import '../storage/token_storage.dart';
import 'api_exception.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

/// Sessiya tugaganda (refresh ham rad etilsa) signal beradi. AuthController tinglaydi.
final sessionExpiredProvider = Provider<StreamController<void>>((ref) {
  final controller = StreamController<void>.broadcast();
  ref.onDispose(controller.close);
  return controller;
});

BaseOptions _options() => BaseOptions(
      baseUrl: Env.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 20),
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
    );

final dioProvider = Provider<Dio>((ref) {
  final storage = ref.watch(tokenStorageProvider);
  final dio = Dio(_options());
  dio.interceptors.add(
    _AuthInterceptor(
      storage: storage,
      refreshDio: Dio(_options()),
      retryDio: dio,
      onExpired: () => ref.read(sessionExpiredProvider).add(null),
    ),
  );
  return dio;
});

/// Access token 15 daqiqa yashaydi. 401 kelsa, refresh token bilan yangisini olib,
/// so'rovni jimgina qayta yuboradi. Bir vaqtda kelgan bir nechta 401 navbatda turadi
/// (QueuedInterceptor), shuning uchun refresh faqat bir marta chaqiriladi.
class _AuthInterceptor extends QueuedInterceptor {
  _AuthInterceptor({
    required this.storage,
    required this.refreshDio,
    required this.retryDio,
    required this.onExpired,
  });

  final TokenStorage storage;
  final Dio refreshDio;
  final Dio retryDio;
  final void Function() onExpired;

  static const _retriedKey = 'auth_retried';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = storage.accessToken;
    if (token != null) options.headers['Authorization'] = 'Bearer $token';
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final request = err.requestOptions;
    final unauthorized = err.response?.statusCode == 401;
    if (!unauthorized || request.extra[_retriedKey] == true || storage.refreshToken == null) {
      return handler.next(err);
    }

    // Navbatda kutgan paytda boshqa so'rov tokenni allaqachon yangilagan bo'lishi mumkin
    final sentWith = request.headers['Authorization'];
    final current = storage.accessToken;
    if (current != null && sentWith != 'Bearer $current') {
      return _retry(request, handler, err);
    }

    try {
      final resp = await refreshDio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': storage.refreshToken},
      );
      final data = resp.data!;
      await storage.save(
        access: data['access_token'] as String,
        refresh: data['refresh_token'] as String,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        await storage.clear();
        onExpired();
      }
      // Tarmoq xatosi: sessiyani yopmaymiz, keyingi urinishda qayta refresh qilinadi
      return handler.next(err);
    }
    return _retry(request, handler, err);
  }

  Future<void> _retry(RequestOptions request, ErrorInterceptorHandler handler, DioException original) async {
    request.extra[_retriedKey] = true;
    request.headers['Authorization'] = 'Bearer ${storage.accessToken}';
    // Yuborilgan FormData qayta ishlatilmaydi: fayl yuklash o'rtasida token yangilansa, nusxa yuboramiz
    final data = request.data;
    if (data is FormData) request.data = data.clone();
    try {
      handler.resolve(await retryDio.fetch<dynamic>(request));
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}

/// Repository'lar uchun: Dio xatolarini [ApiException]ga aylantiradi.
Future<T> guard<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on DioException catch (e) {
    throw ApiException.fromDio(e);
  }
}
