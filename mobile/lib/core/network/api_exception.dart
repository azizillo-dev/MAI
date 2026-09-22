import 'package:dio/dio.dart';

/// Backend xatosi: `{"error": {"code", "message", "details"}}`.
class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.status,
    this.details = const {},
  });

  final String code;
  final String message;
  final int? status;
  final Map<String, dynamic> details;

  bool get isNetwork => code == 'NETWORK';

  /// Forma maydonlari bo'yicha xatolar (422 VALIDATION_ERROR / ONBOARDING_INVALID).
  Map<String, String> get fieldErrors {
    final fields = details['fields'];
    if (fields is Map) {
      return fields.map((k, v) => MapEntry(k.toString(), v.toString()));
    }
    return const {};
  }

  int? get retryAfter => (details['retry_after'] as num?)?.toInt();

  factory ApiException.fromDio(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] is Map) {
      final err = data['error'] as Map;
      return ApiException(
        code: err['code']?.toString() ?? 'UNKNOWN',
        message: err['message']?.toString() ?? _fallback,
        status: e.response?.statusCode,
        details: Map<String, dynamic>.from((err['details'] as Map?) ?? const {}),
      );
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return const ApiException(
          code: 'NETWORK',
          message: "Internet aloqasi yo'q yoki juda sekin. Qayta urinib ko'ring",
        );
      default:
        return ApiException(code: 'UNKNOWN', message: _fallback, status: e.response?.statusCode);
    }
  }

  static const _fallback = "Kutilmagan xatolik. Birozdan keyin qayta urinib ko'ring";

  @override
  String toString() => 'ApiException($code, $message)';
}

/// UI uchun: har qanday xatoni o'qiladigan matnga aylantiradi.
String errorText(Object error) =>
    error is ApiException ? error.message : "Kutilmagan xatolik. Qayta urinib ko'ring";
