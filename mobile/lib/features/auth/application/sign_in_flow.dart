import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_models.dart';

/// Kirish/ro'yxatdan o'tish bosqichlari orasida saqlanadigan ma'lumot.
/// URL'ga qo'yilmaydi: telefon va registration_token maxfiy.
class SignInFlow {
  const SignInFlow({this.role, this.phone, this.otp, this.registrationToken, this.firstNameHint, this.lastNameHint});

  /// Welcome ekranida tanlangan rol. "Kirish" orqali kelganda null.
  final UserRole? role;
  /// Kod yuborilgan manzil (telefon yoki email)
  final String? phone;
  final OtpSent? otp;

  OtpChannel get channel => otp?.channel ?? OtpChannel.sms;
  final String? registrationToken;

  /// Google'dan kelgan ism-familiya (ro'yxatdan o'tish formasi oldindan to'ladi)
  final String? firstNameHint;
  final String? lastNameHint;

  SignInFlow copyWith({
    UserRole? role,
    String? phone,
    OtpSent? otp,
    String? registrationToken,
    String? firstNameHint,
    String? lastNameHint,
  }) =>
      SignInFlow(
        role: role ?? this.role,
        phone: phone ?? this.phone,
        otp: otp ?? this.otp,
        registrationToken: registrationToken ?? this.registrationToken,
        firstNameHint: firstNameHint ?? this.firstNameHint,
        lastNameHint: lastNameHint ?? this.lastNameHint,
      );
}

final signInFlowProvider = NotifierProvider<SignInFlowController, SignInFlow>(SignInFlowController.new);

class SignInFlowController extends Notifier<SignInFlow> {
  @override
  SignInFlow build() => const SignInFlow();

  void start(UserRole? role) => state = SignInFlow(role: role);

  void chooseRole(UserRole role) => state = state.copyWith(role: role);

  void otpSent(String phone, OtpSent otp) => state = state.copyWith(phone: phone, otp: otp);

  void needsRegistration(String token, {String? firstName, String? lastName}) =>
      state = state.copyWith(registrationToken: token, firstNameHint: firstName, lastNameHint: lastName);

  void reset() => state = const SignInFlow();
}
