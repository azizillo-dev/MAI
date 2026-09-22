import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_models.dart';

/// Kirish/ro'yxatdan o'tish bosqichlari orasida saqlanadigan ma'lumot.
/// URL'ga qo'yilmaydi: telefon va registration_token maxfiy.
class SignInFlow {
  const SignInFlow({this.role, this.phone, this.otp, this.registrationToken});

  /// Welcome ekranida tanlangan rol. "Kirish" orqali kelganda null.
  final UserRole? role;
  /// Kod yuborilgan manzil (telefon yoki email)
  final String? phone;
  final OtpSent? otp;

  OtpChannel get channel => otp?.channel ?? OtpChannel.sms;
  final String? registrationToken;

  SignInFlow copyWith({UserRole? role, String? phone, OtpSent? otp, String? registrationToken}) => SignInFlow(
        role: role ?? this.role,
        phone: phone ?? this.phone,
        otp: otp ?? this.otp,
        registrationToken: registrationToken ?? this.registrationToken,
      );
}

final signInFlowProvider = NotifierProvider<SignInFlowController, SignInFlow>(SignInFlowController.new);

class SignInFlowController extends Notifier<SignInFlow> {
  @override
  SignInFlow build() => const SignInFlow();

  void start(UserRole? role) => state = SignInFlow(role: role);

  void chooseRole(UserRole role) => state = state.copyWith(role: role);

  void otpSent(String phone, OtpSent otp) => state = state.copyWith(phone: phone, otp: otp);

  void needsRegistration(String token) => state = state.copyWith(registrationToken: token);

  void reset() => state = const SignInFlow();
}
