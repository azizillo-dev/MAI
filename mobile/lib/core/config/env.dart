/// Build vaqtida beriladi:
///   flutter run --dart-define=API_BASE_URL=https://api.mentorai.uz/api/v1
/// Standart qiymat Android emulyatoridan kompyuterdagi backendga ulanadi.
abstract final class Env {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1',
  );

  /// Guruh taklif havolalari shu manzil bilan boshlanadi (QR ichida ham shu).
  static const joinUrlHost = 'mentorai.uz';

  /// SMS provayder ulanganda: flutter build ... --dart-define=SMS_ENABLED=true
  /// Debug rejimda doim ko'rinadi (lokal backend SMS kodini konsolga chiqaradi).
  static const smsEnabled = bool.fromEnvironment('SMS_ENABLED');
}
