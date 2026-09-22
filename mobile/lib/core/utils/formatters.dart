import 'package:flutter/services.dart';

/// "901234567" -> "90 123 45 67" (terish paytida)
class UzPhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    // Foydalanuvchi to'liq raqamni joylashtirsa (+998...), prefiksni olib tashlaymiz
    if (digits.length > 9 && digits.startsWith('998')) digits = digits.substring(3);
    if (digits.length > 9) digits = digits.substring(0, 9);

    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 2 || i == 5 || i == 7) buf.write(' ');
      buf.write(digits[i]);
    }
    final text = buf.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

/// Guruh kodi: 8 belgi, katta harf, "K7M4-XQ9P" ko'rinishida
class GroupCodeInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var raw = newValue.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (raw.length > 8) raw = raw.substring(0, 8);
    final text = raw.length > 4 ? '${raw.substring(0, 4)}-${raw.substring(4)}' : raw;
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

String digitsOnly(String s) => s.replaceAll(RegExp(r'\D'), '');

const uzMonths = [
  'yanvar',
  'fevral',
  'mart',
  'aprel',
  'may',
  'iyun',
  'iyul',
  'avgust',
  'sentabr',
  'oktabr',
  'noyabr',
  'dekabr',
];

String formatDateUz(DateTime d) => '${d.day}-${uzMonths[d.month - 1]}, ${d.year}';

String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// "Bugun, 18:00" / "Ertaga, 18:00" / "Kecha, 18:00" / "24-sentabr, 18:00"
String formatDueUz(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = day.difference(today).inDays;
  final prefix = switch (diff) {
    0 => 'Bugun',
    1 => 'Ertaga',
    -1 => 'Kecha',
    _ => '${d.day}-${uzMonths[d.month - 1]}${d.year != n.year ? ', ${d.year}' : ''}',
  };
  return '$prefix, ${_hm(d)}';
}

/// "3 soat qoldi" / "2 kun qoldi" / "Muddati o'tdi"
String timeLeftUz(DateTime due, {DateTime? now}) {
  final left = due.difference(now ?? DateTime.now());
  if (left.isNegative) return "Muddati o'tdi";
  if (left.inMinutes < 60) return '${left.inMinutes.clamp(1, 59)} daqiqa qoldi';
  if (left.inHours < 24) return '${left.inHours} soat qoldi';
  return '${left.inDays} kun qoldi';
}

const subjectLabels = {'math': 'Matematika', 'english': 'Ingliz tili'};

String subjectLabel(String s) => subjectLabels[s] ?? s;

String gradingLabel(String s) => '$s ballik';
