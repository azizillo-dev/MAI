import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import '../application/auth_controller.dart';
import '../application/sign_in_flow.dart';
import '../data/auth_models.dart';
import '../data/auth_repository.dart';
import 'welcome_screen.dart';

/// "Kirish" orqali kelgan yangi foydalanuvchi uchun rol tanlash
class RolePickScreen extends ConsumerWidget {
  const RolePickScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void pick(UserRole role) {
      ref.read(signInFlowProvider.notifier).chooseRole(role);
      context.pushReplacement(role == UserRole.teacher ? '/auth/register/teacher' : '/auth/register/student');
    }

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListView(
          padding: Insets.screen,
          children: [
            Text('Siz kimsiz?', style: context.text.headlineSmall),
            const SizedBox(height: 6),
            Text(
              "Bu raqam bilan hali akkaunt yo'q. Keling, yangisini ochamiz.",
              style: context.text.bodyLarge?.copyWith(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            RoleCard(
              icon: Icons.school_rounded,
              title: "Men o'qituvchiman",
              subtitle: 'Guruh yarating, vazifa bering — AI tekshiradi',
              onTap: () => pick(UserRole.teacher),
            ),
            const SizedBox(height: 12),
            RoleCard(
              icon: Icons.backpack_rounded,
              title: "Men o'quvchiman",
              subtitle: "Vazifalarni topshiring, baho va XP to'plang",
              color: Palette.success,
              onTap: () => pick(UserRole.student),
            ),
          ],
        ),
      ),
    );
  }
}

/// Telefon tasdiqlangan: faqat o'qish uchun ko'rsatiladi
class _VerifiedPhone extends StatelessWidget {
  const _VerifiedPhone({required this.phone});

  final String phone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.appColors.successContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_rounded, color: context.appColors.success, size: 20),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              phone.contains('@') ? phone : formatPhone(phone),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
          ),
          const Spacer(),
          Text('Tasdiqlangan', style: TextStyle(color: context.appColors.success, fontSize: 13)),
        ],
      ),
    );
  }
}

String? _validateName(String? v, {bool required = true}) {
  final value = (v ?? '').trim();
  if (value.isEmpty) return required ? "To'ldirilishi shart" : null;
  if (value.length < 2) return 'Kamida 2 ta harf';
  if (!RegExp(r"^[A-Za-zА-Яа-яЁёЎўҚқҒғҲҳ'ʻʼ‘’`\- ]+$").hasMatch(value)) return 'Faqat harflar';
  return null;
}

class _NameField extends StatelessWidget {
  const _NameField({
    required this.controller,
    required this.label,
    this.hint,
    this.required = true,
    this.serverError,
    this.last = false,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool required;
  final String? serverError;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      textCapitalization: TextCapitalization.words,
      textInputAction: last ? TextInputAction.done : TextInputAction.next,
      autofillHints: const [AutofillHints.name],
      maxLength: 40,
      inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[0-9_@#$%^&*()+=!?.,;:/\\|<>"{}\[\]]'))],
      decoration: InputDecoration(
        labelText: required ? label : '$label (ixtiyoriy)',
        hintText: hint,
        counterText: '',
        errorText: serverError,
      ),
      validator: (v) => _validateName(v, required: required),
    );
  }
}

// ---------------------------------------------------------------- O'quvchi

class StudentRegisterScreen extends ConsumerStatefulWidget {
  const StudentRegisterScreen({super.key});

  @override
  ConsumerState<StudentRegisterScreen> createState() => _StudentRegisterScreenState();
}

class _StudentRegisterScreenState extends ConsumerState<StudentRegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _middle = TextEditingController();
  DateTime? _birthDate;
  String? _gender;
  bool _loading = false;
  bool _triedSubmit = false;
  Map<String, String> _serverErrors = const {};

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _middle.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 12, 1, 1),
      firstDate: DateTime(now.year - 90),
      lastDate: DateTime(now.year - 4, now.month, now.day),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      initialDatePickerMode: DatePickerMode.year,
      helpText: "Tug'ilgan sanangiz",
      cancelText: 'Bekor qilish',
      confirmText: 'Tanlash',
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  Future<void> _submit() async {
    setState(() => _triedSubmit = true);
    final formOk = _form.currentState!.validate();
    if (!formOk || _birthDate == null || _gender == null) return;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ConfirmSheet(
        rows: [
          ('Ism', _first.text.trim()),
          ('Familiya', _last.text.trim()),
          if (_middle.text.trim().isNotEmpty) ('Otasining ismi', _middle.text.trim()),
          ("Tug'ilgan sana", formatDateUz(_birthDate!)),
          ('Jins', _gender == 'male' ? "O'g'il bola" : 'Qiz bola'),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _loading = true;
      _serverErrors = const {};
    });
    try {
      final flow = ref.read(signInFlowProvider);
      final (tokens, me) = await ref.read(authRepositoryProvider).registerStudent(
            registrationToken: flow.registrationToken!,
            firstName: _first.text.trim(),
            lastName: _last.text.trim(),
            middleName: _middle.text.trim(),
            birthDate: _birthDate!,
            gender: _gender,
          );
      ref.read(signInFlowProvider.notifier).reset();
      await ref.read(authControllerProvider.notifier).signIn(tokens, me);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'REGISTRATION_EXPIRED') {
        showSnack(context, e.message, error: true);
        context.go('/welcome');
        return;
      }
      setState(() => _serverErrors = e.fieldErrors);
      showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = ref.watch(signInFlowProvider).phone ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text("Ro'yxatdan o'tish")),
      body: SafeArea(
        child: Form(
          key: _form,
          autovalidateMode: _triedSubmit ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
          child: ListView(
            padding: Insets.screen.copyWith(top: 8, bottom: 24),
            children: [
              Text("Ma'lumotlaringiz", style: context.text.headlineSmall),
              const SizedBox(height: 14),
              const InfoBanner(
                tone: StatusTone.warning,
                title: 'Diqqat bilan kiriting',
                text: "Saqlangandan keyin bu ma'lumotlarni faqat ustozingiz ruxsati bilan o'zgartirish mumkin. "
                    'Ism va familiyangizni hujjatdagidek yozing.',
                icon: Icons.lock_outline_rounded,
              ),
              const SizedBox(height: 20),
              _VerifiedPhone(phone: phone),
              const SizedBox(height: 16),
              _NameField(controller: _first, label: 'Ism', hint: 'Azizillo', serverError: _serverErrors['first_name']),
              const SizedBox(height: 14),
              _NameField(controller: _last, label: 'Familiya', hint: 'Nabiyev', serverError: _serverErrors['last_name']),
              const SizedBox(height: 14),
              _NameField(
                controller: _middle,
                label: 'Otasining ismi',
                required: false,
                last: true,
                serverError: _serverErrors['middle_name'],
              ),
              const SizedBox(height: 14),
              _DateTile(
                value: _birthDate,
                onTap: _pickDate,
                error: _triedSubmit && _birthDate == null ? 'Tanlanishi shart' : _serverErrors['birth_date'],
              ),
              const SizedBox(height: 20),
              Text('Jins', style: context.text.titleMedium),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'male', label: Text("O'g'il bola"), icon: Icon(Icons.boy_rounded)),
                  ButtonSegment(value: 'female', label: Text('Qiz bola'), icon: Icon(Icons.girl_rounded)),
                ],
                emptySelectionAllowed: true,
                showSelectedIcon: false,
                selected: {?_gender},
                onSelectionChanged: (s) => setState(() => _gender = s.isEmpty ? null : s.first),
              ),
              if (_triedSubmit && _gender == null)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 12),
                  child: Text('Tanlanishi shart', style: TextStyle(color: context.colors.error, fontSize: 12)),
                ),
              const SizedBox(height: 32),
              PrimaryButton(label: 'Davom etish', loading: _loading, onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({required this.value, required this.onTap, this.error});

  final DateTime? value;
  final VoidCallback onTap;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: onTap,
      child: InputDecorator(
        isEmpty: value == null,
        decoration: InputDecoration(
          labelText: "Tug'ilgan sana",
          errorText: error,
          suffixIcon: const Icon(Icons.calendar_month_rounded),
        ),
        child: Text(value == null ? '' : formatDateUz(value!), style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}

class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("Ma'lumotlar to'g'rimi?", style: context.text.titleLarge),
            const SizedBox(height: 6),
            Text(
              "Tasdiqlaganingizdan keyin ularni o'zingiz o'zgartira olmaysiz.",
              style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  for (final (i, row) in rows.indexed) ...[
                    if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                      child: Row(
                        children: [
                          Text(row.$1, style: TextStyle(color: context.colors.onSurfaceVariant)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              row.$2,
                              textAlign: TextAlign.end,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            PrimaryButton(label: 'Ha, tasdiqlayman', onPressed: () => Navigator.pop(context, true)),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Tahrirlash')),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- O'qituvchi

class TeacherRegisterScreen extends ConsumerStatefulWidget {
  const TeacherRegisterScreen({super.key});

  @override
  ConsumerState<TeacherRegisterScreen> createState() => _TeacherRegisterScreenState();
}

class _TeacherRegisterScreenState extends ConsumerState<TeacherRegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _middle = TextEditingController();
  bool _loading = false;
  Map<String, String> _serverErrors = const {};

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _middle.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _serverErrors = const {};
    });
    try {
      final flow = ref.read(signInFlowProvider);
      final (tokens, me) = await ref.read(authRepositoryProvider).registerTeacher(
            registrationToken: flow.registrationToken!,
            firstName: _first.text.trim(),
            lastName: _last.text.trim(),
            middleName: _middle.text.trim(),
          );
      ref.read(signInFlowProvider.notifier).reset();
      // next_step = teacher_onboarding: router AI savollariga olib o'tadi
      await ref.read(authControllerProvider.notifier).signIn(tokens, me);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'REGISTRATION_EXPIRED') {
        showSnack(context, e.message, error: true);
        context.go('/welcome');
        return;
      }
      setState(() => _serverErrors = e.fieldErrors);
      showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = ref.watch(signInFlowProvider).phone ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text("Ro'yxatdan o'tish")),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: Insets.screen.copyWith(top: 8, bottom: 24),
            children: [
              Text('Tanishib olaylik', style: context.text.headlineSmall),
              const SizedBox(height: 6),
              Text(
                "O'quvchilaringiz sizni shu ism bilan ko'radi.",
                style: context.text.bodyLarge?.copyWith(color: context.colors.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              _VerifiedPhone(phone: phone),
              const SizedBox(height: 16),
              _NameField(controller: _first, label: 'Ism', serverError: _serverErrors['first_name']),
              const SizedBox(height: 14),
              _NameField(controller: _last, label: 'Familiya', serverError: _serverErrors['last_name']),
              const SizedBox(height: 14),
              _NameField(
                controller: _middle,
                label: 'Otasining ismi',
                required: false,
                last: true,
                serverError: _serverErrors['middle_name'],
              ),
              const SizedBox(height: 32),
              PrimaryButton(label: 'Davom etish', loading: _loading, onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}
