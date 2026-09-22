import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import 'auth_models.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository(ref.watch(dioProvider)));

class AuthRepository {
  AuthRepository(this._dio);

  final Dio _dio;

  static const deviceName = 'Android';

  Future<OtpSent> requestOtp(String phone) => guard(() async {
        final r = await _dio.post<Map<String, dynamic>>('/auth/otp/request', data: {'phone': phone});
        return OtpSent.fromJson(r.data!);
      });

  Future<OtpSent> requestEmailOtp(String email) => guard(() async {
        final r = await _dio.post<Map<String, dynamic>>('/auth/email/request', data: {'email': email});
        return OtpSent.fromJson(r.data!);
      });

  /// Kodni tekshiradi: [channel] ga qarab SMS yoki email endpoint'i
  Future<OtpResult> verifyOtp(String target, String code, {OtpChannel channel = OtpChannel.sms}) => guard(() async {
        final isEmail = channel == OtpChannel.email;
        final r = await _dio.post<Map<String, dynamic>>(
          isEmail ? '/auth/email/verify' : '/auth/otp/verify',
          data: {isEmail ? 'email' : 'phone': target, 'code': code, 'device_name': deviceName},
        );
        final d = r.data!;
        if (d['status'] == 'logged_in') {
          return OtpLoggedIn(
            Tokens.fromJson(d['tokens'] as Map<String, dynamic>),
            Me.fromJson(d['me'] as Map<String, dynamic>),
          );
        }
        return OtpNeedsRegistration(d['registration_token'] as String);
      });

  Future<(Tokens, Me)> registerStudent({
    required String registrationToken,
    required String firstName,
    required String lastName,
    String? middleName,
    required DateTime birthDate,
    String? gender,
  }) =>
      _register('/auth/register/student', {
        'registration_token': registrationToken,
        'first_name': firstName,
        'last_name': lastName,
        if (middleName != null && middleName.isNotEmpty) 'middle_name': middleName,
        'birth_date': DateFormat('yyyy-MM-dd').format(birthDate),
        'gender': ?gender,
      });

  Future<(Tokens, Me)> registerTeacher({
    required String registrationToken,
    required String firstName,
    required String lastName,
    String? middleName,
  }) =>
      _register('/auth/register/teacher', {
        'registration_token': registrationToken,
        'first_name': firstName,
        'last_name': lastName,
        if (middleName != null && middleName.isNotEmpty) 'middle_name': middleName,
      });

  Future<(Tokens, Me)> _register(String path, Map<String, dynamic> body) => guard(() async {
        final r = await _dio.post<Map<String, dynamic>>(path, data: {...body, 'device_name': deviceName});
        final d = r.data!;
        return (
          Tokens.fromJson(d['tokens'] as Map<String, dynamic>),
          Me.fromJson(d['me'] as Map<String, dynamic>),
        );
      });

  Future<Me> me() => guard(() async {
        final r = await _dio.get<Map<String, dynamic>>('/me');
        return Me.fromJson(r.data!);
      });

  Future<Me> updateStudentProfile(Map<String, dynamic> changes) => guard(() async {
        final r = await _dio.patch<Map<String, dynamic>>('/students/me/profile', data: changes);
        return Me.fromJson(r.data!);
      });

  Future<Me> uploadAvatar(String path) => guard(() async {
        final form = FormData.fromMap({'file': await MultipartFile.fromFile(path, filename: 'avatar.jpg')});
        final r = await _dio.post<Map<String, dynamic>>('/me/avatar', data: form);
        return Me.fromJson(r.data!);
      });

  Future<Me> deleteAvatar() => guard(() async {
        final r = await _dio.delete<Map<String, dynamic>>('/me/avatar');
        return Me.fromJson(r.data!);
      });

  /// Faqat o'qituvchi uchun (o'quvchi ma'lumotlari ustoz ruxsatisiz qulflangan)
  Future<Me> updateName({required String firstName, required String lastName}) => guard(() async {
        final r = await _dio.patch<Map<String, dynamic>>('/me', data: {'first_name': firstName, 'last_name': lastName});
        return Me.fromJson(r.data!);
      });

  Future<void> logout() => guard(() => _dio.post<void>('/auth/logout'));
}
