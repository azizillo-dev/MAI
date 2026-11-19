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

  /// Google orqali kirish: Google Cloud'dagi "Web" OAuth client ID (backend GOOGLE_CLIENT_IDS bilan bir xil).
  /// Bo'sh bo'lsa, tugma "tez orada" deydi:  --dart-define=GOOGLE_SERVER_CLIENT_ID=...apps.googleusercontent.com
  static const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
}
