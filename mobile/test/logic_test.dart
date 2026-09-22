import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mentor_ai/core/utils/formatters.dart';
import 'package:mentor_ai/features/auth/data/auth_models.dart';
import 'package:mentor_ai/features/groups/data/group_models.dart';

String _fmt(TextInputFormatter f, String input) =>
    f.formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: input)).text;

void main() {
  group('UzPhoneInputFormatter', () {
    final f = UzPhoneInputFormatter();

    test('raqamlarni guruhlaydi', () {
      expect(_fmt(f, '901234567'), '90 123 45 67');
      expect(_fmt(f, '9012'), '90 12');
    });

    test("joylashtirilgan to'liq raqamdan +998 ni olib tashlaydi", () {
      expect(_fmt(f, '+998 90 123 45 67'), '90 123 45 67');
      expect(_fmt(f, '998901234567'), '90 123 45 67');
    });

    test("9 raqamdan ortig'ini kesadi", () {
      expect(_fmt(f, '9012345678999'), '90 123 45 67');
    });
  });

  group('GroupCodeInputFormatter', () {
    final f = GroupCodeInputFormatter();

    test('katta harf va chiziqcha', () {
      expect(_fmt(f, 'k7m4xq9p'), 'K7M4-XQ9P');
      expect(_fmt(f, 'k7m'), 'K7M');
      expect(_fmt(f, 'k7m4x'), 'K7M4-X');
      expect(_fmt(f, 'K7M4 XQ9P extra'), 'K7M4-XQ9P');
    });
  });

  group('InviteLink', () {
    test('https havola', () {
      final l = InviteLink.tryParse('https://mentorai.uz/join/K7M4XQ9P?t=abc123');
      expect(l?.code, 'K7M4XQ9P');
      expect(l?.token, 'abc123');
    });

    test('kichik harfli kod', () {
      expect(InviteLink.tryParse('https://mentorai.uz/join/k7m4xq9p')?.code, 'K7M4XQ9P');
    });

    test('boshqa QR rad etiladi', () {
      expect(InviteLink.tryParse('https://google.com'), isNull);
      expect(InviteLink.tryParse('salom'), isNull);
      expect(InviteLink.tryParse('https://mentorai.uz/join/ABC'), isNull);
      // Eski 6 belgili format endi qabul qilinmaydi
      expect(InviteLink.tryParse('https://mentorai.uz/join/K7M4XQ'), isNull);
    });
  });

  group('telefon ko\'rinishi', () {
    test('format va maska', () {
      expect(formatPhone('+998901234567'), '+998 90 123 45 67');
      expect(maskPhone('+998901234567'), '+998 90 *** ** 67');
    });
  });

  test('Me.fromJson: o\'quvchi', () {
    final me = Me.fromJson({
      'id': 'u1',
      'phone': '+998901234567',
      'role': 'student',
      'first_name': 'Azizillo',
      'last_name': 'Nabiyev',
      'middle_name': null,
      'full_name': 'Azizillo Nabiyev',
      'locale': 'uz',
      'student': {'birth_date': '2012-05-14', 'gender': 'male', 'is_locked': true, 'can_edit': false},
      'teacher': null,
      'next_step': 'home',
    });
    expect(me.isStudent, isTrue);
    expect(me.initials, 'AN');
    expect(me.student!.isLocked, isTrue);
    expect(me.needsOnboarding, isFalse);
  });

  test('TeacherGroup parol ko\'rinishi', () {
    final g = TeacherGroup.fromJson({
      'id': 'g1',
      'name': '7-B',
      'subject': 'math',
      'grading_scale': '5',
      'status': 'active',
      'join_enabled': true,
      'join_code': 'K7M4-XQ9P',
      'join_password': '48291375',
      'invite_url': 'https://mentorai.uz/join/K7M4XQ?t=x',
      'members_active': 3,
      'members_pending': 1,
    });
    expect(g.passwordPretty, '4829 1375');
    expect(g.joinEnabled, isTrue);
  });

  test('formatDateUz', () {
    expect(formatDateUz(DateTime(2012, 5, 14)), '14-may, 2012');
  });
}
