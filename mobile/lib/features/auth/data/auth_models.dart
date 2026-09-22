enum UserRole {
  student,
  teacher,
  admin;

  static UserRole parse(String value) => UserRole.values.asNameMap()[value] ?? UserRole.student;
}

class StudentInfo {
  const StudentInfo({required this.birthDate, this.gender, required this.isLocked, required this.canEdit});

  final DateTime birthDate;
  final String? gender;
  final bool isLocked;

  /// Ustoz bir martalik tahrirlash ruxsatini berganmi
  final bool canEdit;

  factory StudentInfo.fromJson(Map<String, dynamic> j) => StudentInfo(
        birthDate: DateTime.parse(j['birth_date'] as String),
        gender: j['gender'] as String?,
        isLocked: j['is_locked'] as bool,
        canEdit: j['can_edit'] as bool,
      );
}

class TeacherInfo {
  const TeacherInfo({required this.onboardingCompleted, required this.defaultGradingScale});

  final bool onboardingCompleted;
  final String defaultGradingScale;

  factory TeacherInfo.fromJson(Map<String, dynamic> j) => TeacherInfo(
        onboardingCompleted: j['onboarding_completed'] as bool,
        defaultGradingScale: j['default_grading_scale'] as String,
      );
}

class Me {
  const Me({
    required this.id,
    this.phone,
    this.email,
    required this.role,
    required this.firstName,
    required this.lastName,
    this.middleName,
    required this.fullName,
    required this.locale,
    this.avatarUrl,
    this.student,
    this.teacher,
    required this.nextStep,
    required this.raw,
  });

  final String id;
  final String? phone;
  final String? email;
  final UserRole role;
  final String firstName;
  final String lastName;
  final String? middleName;
  final String fullName;
  final String locale;
  final String? avatarUrl;
  final StudentInfo? student;
  final TeacherInfo? teacher;

  /// teacher_onboarding | home
  final String nextStep;

  /// Keshlash uchun asl JSON
  final Map<String, dynamic> raw;

  /// Kirish manzili (email yoki telefon) — profil va sozlamalarda ko'rsatiladi
  String get contact => email ?? (phone == null ? '' : formatPhone(phone!));

  bool get isTeacher => role == UserRole.teacher;
  bool get isStudent => role == UserRole.student;
  bool get needsOnboarding => nextStep == 'teacher_onboarding';

  /// Qisqa ID (profil kartasida): "ID: 3F8B12"
  String get shortId => id.replaceAll('-', '').substring(0, 6).toUpperCase();

  String get initials =>
      '${firstName.isNotEmpty ? firstName[0] : ''}${lastName.isNotEmpty ? lastName[0] : ''}'.toUpperCase();

  factory Me.fromJson(Map<String, dynamic> j) => Me(
        id: j['id'] as String,
        phone: j['phone'] as String?,
        email: j['email'] as String?,
        role: UserRole.parse(j['role'] as String),
        firstName: j['first_name'] as String,
        lastName: j['last_name'] as String,
        middleName: j['middle_name'] as String?,
        fullName: j['full_name'] as String,
        locale: j['locale'] as String? ?? 'uz',
        avatarUrl: j['avatar_url'] as String?,
        student: j['student'] == null ? null : StudentInfo.fromJson(j['student'] as Map<String, dynamic>),
        teacher: j['teacher'] == null ? null : TeacherInfo.fromJson(j['teacher'] as Map<String, dynamic>),
        nextStep: j['next_step'] as String? ?? 'home',
        raw: j,
      );
}

class Tokens {
  const Tokens({required this.access, required this.refresh});

  final String access;
  final String refresh;

  factory Tokens.fromJson(Map<String, dynamic> j) =>
      Tokens(access: j['access_token'] as String, refresh: j['refresh_token'] as String);
}

enum OtpChannel { sms, email }

class OtpSent {
  const OtpSent({required this.target, required this.channel, required this.expiresIn, required this.resendIn, this.devCode});

  /// Kod yuborilgan manzil: "+998901234567" yoki "ism@gmail.com"
  final String target;
  final OtpChannel channel;
  final int expiresIn;
  final int resendIn;

  /// Faqat development serverda keladi
  final String? devCode;

  factory OtpSent.fromJson(Map<String, dynamic> j) => OtpSent(
        target: (j['target'] ?? j['phone']) as String,
        channel: j['channel'] == 'email' ? OtpChannel.email : OtpChannel.sms,
        expiresIn: j['expires_in'] as int,
        resendIn: j['resend_in'] as int,
        devCode: j['dev_code'] as String?,
      );
}

sealed class OtpResult {
  const OtpResult();
}

class OtpLoggedIn extends OtpResult {
  const OtpLoggedIn(this.tokens, this.me);
  final Tokens tokens;
  final Me me;
}

class OtpNeedsRegistration extends OtpResult {
  const OtpNeedsRegistration(this.registrationToken);
  final String registrationToken;
}

String formatPhone(String phone) {
  // +998901234567 -> +998 90 123 45 67
  final d = phone.replaceAll(RegExp(r'\D'), '');
  if (d.length != 12) return phone;
  return '+${d.substring(0, 3)} ${d.substring(3, 5)} ${d.substring(5, 8)} ${d.substring(8, 10)} ${d.substring(10)}';
}

/// ali.valiyev@gmail.com -> al*********@gmail.com; telefon bo'lsa +998 90 *** ** 67
String maskTarget(String target) {
  if (target.contains('@')) {
    final at = target.indexOf('@');
    final name = target.substring(0, at);
    return '${name.substring(0, name.length < 2 ? name.length : 2)}${'*' * (name.length > 2 ? name.length - 2 : 3)}${target.substring(at)}';
  }
  return maskPhone(target);
}

String maskPhone(String phone) {
  final d = phone.replaceAll(RegExp(r'\D'), '');
  if (d.length != 12) return phone;
  return '+${d.substring(0, 3)} ${d.substring(3, 5)} *** ** ${d.substring(10)}';
}
