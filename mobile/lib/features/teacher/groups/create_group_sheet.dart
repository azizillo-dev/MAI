import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../auth/application/auth_controller.dart';
import '../../groups/data/group_models.dart';
import '../../groups/data/groups_repository.dart';

Future<void> showCreateGroupSheet(BuildContext context, WidgetRef ref) async {
  // Limit tugagan bo'lsa, forma ochilmasdan oldin aytamiz
  PlanUsage? plan;
  try {
    plan = await ref.read(planUsageProvider.future);
  } on Object {
    plan = null; // tekshira olmasak ham formani ochamiz: server baribir limitni tekshiradi
  }
  if (!context.mounted) return;
  final p = plan;
  if (p != null && !p.canCreateGroup) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.workspace_premium_rounded, color: Palette.gold, size: 36),
        title: Text(p.isExpired ? 'Tarif muddati tugagan' : 'Guruhlar limiti tugadi'),
        content: Text(
          p.isExpired
              ? "Yangi guruh ochish uchun tarifni faollashtiring. Mavjud ma'lumotlaringiz saqlanib qoladi."
              : "${p.planName} tarifida ${p.maxGroups} ta guruh ochish mumkin. "
                    "Pro tarifda 3 ta guruh va 90 tagacha o'quvchi.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Keyinroq')),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              context.push('/teacher/plans');
            },
            child: const Text('Tariflar'),
          ),
        ],
      ),
    );
    return;
  }

  final groupId = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _CreateGroupSheet(),
  );
  if (groupId != null && context.mounted) {
    ref.invalidate(teacherGroupsProvider);
    ref.invalidate(planUsageProvider);
    context.push('/teacher/groups/$groupId?created=1');
  }
}

class _CreateGroupSheet extends ConsumerStatefulWidget {
  const _CreateGroupSheet();

  @override
  ConsumerState<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends ConsumerState<_CreateGroupSheet> {
  final _name = TextEditingController();
  late String _subject;
  late String _scale;
  bool _loading = false;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    final teacher = ref.read(currentUserProvider)?.teacher;
    _scale = teacher?.defaultGradingScale ?? '5';
    _subject = 'math';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.length < 2) {
      setState(() => _nameError = 'Guruh nomini kiriting (kamida 2 belgi)');
      return;
    }
    setState(() {
      _loading = true;
      _nameError = null;
    });
    try {
      final g = await ref.read(groupsRepositoryProvider).create(
            name: name,
            subject: _subject,
            gradingScale: _scale,
          );
      if (mounted) Navigator.pop(context, g.id);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _nameError = e.fieldErrors['name']);
      if (_nameError == null) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Yangi guruh', style: context.text.titleLarge),
            const SizedBox(height: 18),
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 40,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Guruh nomi',
                hintText: 'Masalan: 7-B matematika',
                errorText: _nameError,
                counterText: '',
              ),
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
            ),
            const SizedBox(height: 18),
            Text('Fan', style: context.text.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'math', label: Text('Matematika'), icon: Icon(Icons.calculate_rounded)),
                ButtonSegment(value: 'english', label: Text('Ingliz tili'), icon: Icon(Icons.translate_rounded)),
              ],
              selected: {_subject},
              onSelectionChanged: (s) => setState(() => _subject = s.first),
            ),
            const SizedBox(height: 18),
            Text('Baholash tizimi', style: context.text.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: '5', label: Text('5 ball')),
                ButtonSegment(value: '10', label: Text('10 ball')),
                ButtonSegment(value: '100', label: Text('100 ball')),
              ],
              selected: {_scale},
              onSelectionChanged: (s) => setState(() => _scale = s.first),
            ),
            const SizedBox(height: 18),
            const InfoBanner(
              icon: Icons.verified_user_rounded,
              text: "Har bir o'quvchini siz tasdiqlaysiz: kod begona odamga tarqalsa ham, u guruhga o'zi kira olmaydi.",
            ),
            const SizedBox(height: 20),
            PrimaryButton(label: 'Guruh yaratish', loading: _loading, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}
