import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_widgets.dart';
import '../auth/application/auth_controller.dart';
import '../auth/data/auth_repository.dart';

/// Ustoz bergan BIR MARTALIK ruxsat bilan ochiladi. Saqlangach yana qulflanadi.
class StudentProfileEditScreen extends ConsumerStatefulWidget {
  const StudentProfileEditScreen({super.key});

  @override
  ConsumerState<StudentProfileEditScreen> createState() => _StudentProfileEditScreenState();
}

class _StudentProfileEditScreenState extends ConsumerState<StudentProfileEditScreen> {
  final _form = GlobalKey<FormState>();
  late final _me = ref.read(currentUserProvider)!;
  late final _first = TextEditingController(text: _me.firstName);
  late final _last = TextEditingController(text: _me.lastName);
  late final _middle = TextEditingController(text: _me.middleName ?? '');
  late DateTime _birth = _me.student!.birthDate;
  bool _saving = false;
  Map<String, String> _errors = const {};

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _middle.dispose();
    super.dispose();
  }

  Map<String, dynamic> _changes() => {
        if (_first.text.trim() != _me.firstName) 'first_name': _first.text.trim(),
        if (_last.text.trim() != _me.lastName) 'last_name': _last.text.trim(),
        if (_middle.text.trim().isNotEmpty && _middle.text.trim() != (_me.middleName ?? ''))
          'middle_name': _middle.text.trim(),
        if (_birth != _me.student!.birthDate) 'birth_date': DateFormat('yyyy-MM-dd').format(_birth),
      };

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final changes = _changes();
    if (changes.isEmpty) {
      showSnack(context, "Hech narsa o'zgartirilmadi");
      return;
    }
    final ok = await confirmDialog(
      context,
      title: 'Saqlaysizmi?',
      message: "Ruxsat bir martalik. Saqlaganingizdan keyin ma'lumotlar yana qulflanadi.",
      confirmLabel: 'Saqlash',
    );
    if (!ok) return;

    setState(() {
      _saving = true;
      _errors = const {};
    });
    try {
      final me = await ref.read(authRepositoryProvider).updateStudentProfile(changes);
      await ref.read(authControllerProvider.notifier).updateMe(me);
      if (mounted) {
        showSnack(context, "Ma'lumotlar saqlandi");
        context.pop();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errors = e.fieldErrors);
      showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _validate(String? v, {bool required = true}) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return required ? "To'ldirilishi shart" : null;
    if (value.length < 2) return 'Kamida 2 ta harf';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tahrirlash')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: Insets.screen.copyWith(top: 8, bottom: 24),
            children: [
              const InfoBanner(
                tone: StatusTone.warning,
                text: "Ustozingiz bir martalik ruxsat berdi. Saqlaganingizdan keyin ma'lumotlar yana qulflanadi.",
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _first,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: 'Ism', errorText: _errors['first_name']),
                validator: _validate,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _last,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: 'Familiya', errorText: _errors['last_name']),
                validator: _validate,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _middle,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: 'Otasining ismi (ixtiyoriy)', errorText: _errors['middle_name']),
                validator: (v) => _validate(v, required: false),
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _birth,
                    firstDate: DateTime(now.year - 90),
                    lastDate: DateTime(now.year - 4, now.month, now.day),
                    initialEntryMode: DatePickerEntryMode.calendarOnly,
                  );
                  if (picked != null) setState(() => _birth = picked);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: "Tug'ilgan sana",
                    errorText: _errors['birth_date'],
                    suffixIcon: const Icon(Icons.calendar_month_rounded),
                  ),
                  child: Text(formatDateUz(_birth), style: const TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 32),
              PrimaryButton(label: 'Saqlash', loading: _saving, onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}
