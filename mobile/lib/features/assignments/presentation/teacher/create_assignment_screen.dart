import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../../groups/data/groups_repository.dart';
import '../../data/assignment_models.dart';
import '../../data/assignments_repository.dart';

/// Vazifa berish: 3 usul — PDF kitobdan sahifa/misollar, misollar rasmi, matnli topshiriq.
class CreateAssignmentScreen extends ConsumerStatefulWidget {
  const CreateAssignmentScreen({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<CreateAssignmentScreen> createState() => _CreateAssignmentScreenState();
}

class _CreateAssignmentScreenState extends ConsumerState<CreateAssignmentScreen> {
  final _title = TextEditingController();
  final _instructions = TextEditingController();
  final _pageFrom = TextEditingController();
  final _pageTo = TextEditingController();
  final _problems = TextEditingController();

  SourceType _type = SourceType.book;
  String? _bookId;
  final List<XFile> _images = [];
  late DateTime _due = _defaultDue();
  bool _allowLate = true;
  int _penalty = 0;

  bool _saving = false;
  double _progress = 0;
  Map<String, String> _errors = {};

  static DateTime _defaultDue() {
    // Odatda uy vazifasi ertasi kuni darsgacha: ertaga 18:00
    final n = DateTime.now().add(const Duration(days: 1));
    return DateTime(n.year, n.month, n.day, 18);
  }

  @override
  void dispose() {
    for (final c in [_title, _instructions, _pageFrom, _pageTo, _problems]) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------- tanlovlar

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _due.isBefore(now) ? now : _due,
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
      helpText: 'Topshirish kuni',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_due),
      helpText: 'Soat nechagacha',
      builder: (context, child) =>
          MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (time == null) return;
    setState(() => _due = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _addImages(ImageSource source) async {
    final picker = ImagePicker();
    // Rasm telefonda siqiladi: yuklash tez, AI uchun sifat yetarli
    if (source == ImageSource.camera) {
      final x = await picker.pickImage(source: source, imageQuality: 82, maxWidth: 2200, maxHeight: 2200);
      if (x != null) setState(() => _images.add(x));
    } else {
      final xs = await picker.pickMultiImage(imageQuality: 82, maxWidth: 2200, maxHeight: 2200, limit: 10);
      setState(() => _images.addAll(xs.take(10 - _images.length)));
    }
  }

  Future<void> _uploadBook() async {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    final file = picked.firstOrNull;
    if (file == null || file.path == null) return;
    final size = await file.xFile.length();
    if (!mounted) return;
    if (size > 60 * 1024 * 1024) {
      showSnack(context, 'PDF 60 MB dan katta. Kichikroq faylni tanlang', error: true);
      return;
    }
    final book = await showModalBottomSheet<Book>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _BookUploadSheet(path: file.path!, fileName: file.name),
    );
    if (book != null) {
      ref.invalidate(booksProvider);
      setState(() => _bookId = book.id);
    }
  }

  // ---------------------------------------------------------------- saqlash

  Map<String, String> _validate() {
    final e = <String, String>{};
    if (_title.text.trim().length < 2) e['title'] = 'Vazifa nomini yozing';
    switch (_type) {
      case SourceType.book:
        if (_bookId == null) e['book'] = 'Kitobni tanlang yoki yuklang';
        final from = int.tryParse(_pageFrom.text);
        final to = int.tryParse(_pageTo.text.isEmpty ? _pageFrom.text : _pageTo.text);
        if (from == null) e['page_from'] = 'Betni kiriting';
        if (from != null && to != null && to < from) e['page_to'] = "Birinchi betdan kichik bo'lmasin";
      case SourceType.images:
        if (_images.isEmpty) e['images'] = 'Kamida bitta rasm qo\'shing';
      case SourceType.text:
        if (_instructions.text.trim().length < 10) e['instructions'] = 'Topshiriqni batafsilroq yozing';
    }
    if (_due.isBefore(DateTime.now().add(const Duration(minutes: 10)))) {
      e['due'] = "Muddat kamida 10 daqiqadan keyin bo'lsin";
    }
    return e;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final errors = _validate();
    setState(() => _errors = errors);
    if (errors.isNotEmpty) {
      HapticFeedback.heavyImpact();
      return;
    }
    setState(() {
      _saving = true;
      _progress = 0;
    });
    try {
      final from = int.tryParse(_pageFrom.text);
      final a = await ref.read(assignmentsRepositoryProvider).create(
            groupId: widget.groupId,
            title: _title.text.trim(),
            sourceType: _type,
            dueAt: _due,
            instructions: _instructions.text.trim(),
            allowLate: _allowLate,
            latePenaltyPercent: _allowLate ? _penalty : 0,
            bookId: _type == SourceType.book ? _bookId : null,
            pageFrom: _type == SourceType.book ? from : null,
            pageTo: _type == SourceType.book ? (int.tryParse(_pageTo.text) ?? from) : null,
            problems: _type == SourceType.book ? _problems.text.trim() : null,
            imagePaths: _type == SourceType.images ? [for (final i in _images) i.path] : const [],
            onProgress: (p) => mounted ? setState(() => _progress = p) : null,
          );
      ref.invalidate(groupAssignmentsProvider(widget.groupId));
      if (mounted) context.pushReplacement('/teacher/assignments/${a.id}');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errors = e.fieldErrors);
      showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final group = ref.watch(teacherGroupProvider(widget.groupId)).value;
    return Scaffold(
      appBar: AppBar(title: Text(group == null ? 'Vazifa berish' : 'Vazifa · ${group.name}')),
      body: SafeArea(
        child: ListView(
          padding: Insets.screen.copyWith(top: 8, bottom: 32),
          children: [
            TextField(
              controller: _title,
              maxLength: 120,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Vazifa nomi',
                hintText: 'Masalan: Kasrlarni qo\'shish',
                errorText: _errors['title'],
                counterText: '',
              ),
            ),
            const SizedBox(height: 20),
            Text('Vazifani qanday berasiz?', style: context.text.titleMedium),
            const SizedBox(height: 10),
            SegmentedButton<SourceType>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: SourceType.book, label: Text('Kitob'), icon: Icon(Icons.menu_book_rounded)),
                ButtonSegment(value: SourceType.images, label: Text('Rasm'), icon: Icon(Icons.photo_camera_rounded)),
                ButtonSegment(value: SourceType.text, label: Text('Matn'), icon: Icon(Icons.edit_note_rounded)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() {
                _type = s.first;
                _errors = {};
              }),
            ),
            const SizedBox(height: 16),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: switch (_type) {
                SourceType.book => _bookSection(),
                SourceType.images => _imagesSection(),
                SourceType.text => _textSection(),
              },
            ),
            if (_type != SourceType.text) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _instructions,
                minLines: 2,
                maxLines: 5,
                maxLength: 4000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Qo\'shimcha ko\'rsatma (ixtiyoriy)',
                  hintText: 'Masalan: yechim yo\'lini to\'liq yozing',
                  counterText: '',
                ),
              ),
            ],
            const SizedBox(height: 20),
            _dueSection(),
            const SizedBox(height: 24),
            if (_saving && _progress > 0 && _progress < 1) ...[
              LinearProgressIndicator(value: _progress, minHeight: 6, borderRadius: BorderRadius.circular(8)),
              const SizedBox(height: 10),
            ],
            PrimaryButton(
              label: _type == SourceType.text ? 'Davom etish' : 'AI misollarni ajratsin',
              icon: Icons.auto_awesome_rounded,
              loading: _saving,
              onPressed: _submit,
            ),
            const SizedBox(height: 8),
            Text(
              "Vazifa darhol o'quvchilarga chiqmaydi: avval AI tayyorlaganini ko'rib, tasdiqlaysiz.",
              textAlign: TextAlign.center,
              style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bookSection() {
    final books = ref.watch(booksProvider);
    final list = books.value ?? const <Book>[];
    final selected = list.where((b) => b.id == _bookId).firstOrNull;
    return Column(
      key: const ValueKey('book'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (books.isLoading && list.isEmpty)
          const LinearProgressIndicator()
        else if (list.isEmpty)
          InfoBanner(
            icon: Icons.upload_file_rounded,
            text: "Hali kitob yuklamagansiz. Darslik PDF'ini bir marta yuklang — keyin hamma vazifalarda ishlatasiz.",
            tone: _errors.containsKey('book') ? StatusTone.danger : StatusTone.info,
          )
        else
          DropdownButtonFormField<String>(
            initialValue: _bookId,
            isExpanded: true,
            decoration: InputDecoration(labelText: 'Kitob', errorText: _errors['book']),
            items: [
              for (final b in list)
                DropdownMenuItem(value: b.id, child: Text(b.title, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _bookId = v),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _uploadBook,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Yangi kitob (PDF) yuklash'),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _pageFrom,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: 'Betdan', hintText: '34', errorText: _errors['page_from']),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _pageTo,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: 'Betgacha', hintText: '37', errorText: _errors['page_to']),
              ),
            ),
          ],
        ),
        if (selected != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              'Kitobda 1–${selected.lastPrintedPage}-betlar bor. Bir vazifaga ko\'pi bilan 15 bet.',
              style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          ),
        const SizedBox(height: 14),
        TextField(
          controller: _problems,
          maxLength: 120,
          decoration: InputDecoration(
            labelText: 'Misollar (ixtiyoriy)',
            hintText: '56-78 yoki 3, 5, 7-10',
            helperText: "Bo'sh qoldirsangiz, sahifalardagi hamma misollar olinadi",
            errorText: _errors['problems'],
            counterText: '',
          ),
        ),
      ],
    );
  }

  Widget _imagesSection() {
    return Column(
      key: const ValueKey('images'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_images.isNotEmpty)
          SizedBox(
            height: 110,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _images.length,
              onReorderItem: (from, to) => setState(() => _images.insert(to, _images.removeAt(from))),
              itemBuilder: (context, i) => Padding(
                key: ValueKey(_images[i].path),
                padding: const EdgeInsets.only(right: 8),
                child: _Thumb(file: File(_images[i].path), onRemove: () => setState(() => _images.removeAt(i))),
              ),
            ),
          ),
        if (_errors['images'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_errors['images']!, style: TextStyle(color: context.colors.error, fontSize: 12.5)),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _images.length >= 10 ? null : () => _addImages(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_rounded),
                label: const Text('Kamera'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _images.length >= 10 ? null : () => _addImages(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_rounded),
                label: const Text('Galereya'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          "Misollar aniq ko'rinsin: yorug' joyda, sahifaga to'g'ri qarab rasmga oling.",
          style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _textSection() {
    return Column(
      key: const ValueKey('text'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _instructions,
          minLines: 4,
          maxLines: 10,
          maxLength: 4000,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Topshiriq',
            hintText: "Masalan: \"Hayvonlar\" mavzusida 15 ta so'zdan iborat inglizcha krossvord tuzib keling",
            errorText: _errors['instructions'],
            alignLabelWithHint: true,
          ),
        ),
        const InfoBanner(
          icon: Icons.auto_awesome_rounded,
          text: "AI baholash mezonlarini taklif qiladi (masalan: mavzuga mosligi, to'g'riligi). Siz tasdiqlaysiz yoki o'zgartirasiz.",
        ),
      ],
    );
  }

  Widget _dueSection() {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.event_rounded, color: context.colors.primary),
            title: const Text('Topshirish muddati'),
            subtitle: Text(
              _errors['due'] ?? formatDueUz(_due),
              style: TextStyle(
                color: _errors['due'] != null ? context.colors.error : context.colors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _pickDue,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            value: _allowLate,
            onChanged: (v) => setState(() => _allowLate = v),
            title: const Text('Kechikib topshirishga ruxsat'),
            subtitle: Text(_allowLate ? 'Muddatdan keyin ham qabul qilinadi' : 'Muddat tugagach topshirib bo\'lmaydi'),
          ),
          if (_allowLate)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Text('Kechikkanlik jarimasi', style: context.text.bodyMedium),
                  Expanded(
                    child: Slider(
                      value: _penalty.toDouble(),
                      max: 50,
                      divisions: 10,
                      label: '$_penalty%',
                      onChanged: (v) => setState(() => _penalty = v.round()),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text('-$_penalty%', textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.file, required this.onRemove});

  final File file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.md),
          child: Image.file(file, width: 86, height: 110, fit: BoxFit.cover, cacheWidth: 260),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: Material(
            color: Colors.black54,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close_rounded, size: 16, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// PDF yuklash + sahifa kalibrovkasi
class _BookUploadSheet extends ConsumerStatefulWidget {
  const _BookUploadSheet({required this.path, required this.fileName});

  final String path;
  final String fileName;

  @override
  ConsumerState<_BookUploadSheet> createState() => _BookUploadSheetState();
}

class _BookUploadSheetState extends ConsumerState<_BookUploadSheet> {
  late final _title = TextEditingController(text: widget.fileName.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), ''));
  final _offset = TextEditingController(text: '1');
  bool _loading = false;
  double _progress = 0;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _offset.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final offset = int.tryParse(_offset.text) ?? 0;
    if (_title.text.trim().length < 2 || offset < 1) {
      setState(() => _error = 'Nom va sahifa raqamini to\'g\'ri kiriting');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final book = await ref.read(assignmentsRepositoryProvider).uploadBook(
            title: _title.text.trim(),
            pageOffset: offset,
            filePath: widget.path,
            fileName: widget.fileName,
            onProgress: (p) => mounted ? setState(() => _progress = p) : null,
          );
      if (mounted) Navigator.pop(context, book);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
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
            Text('Kitob yuklash', style: context.text.titleLarge),
            const SizedBox(height: 16),
            TextField(controller: _title, decoration: const InputDecoration(labelText: 'Kitob nomi')),
            const SizedBox(height: 16),
            Text("Kitobdagi 1-bet PDF'da nechanchi sahifa?", style: context.text.titleMedium),
            const SizedBox(height: 4),
            Text(
              "Muqova va mundarija sababli farq qiladi. PDF'ni ochib, \"1\" raqamli bet nechanchi sahifada "
              "ekanini ko'ring. Shunda \"34-bet\" desangiz, AI aynan kitobdagi 34-betni oladi.",
              style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _offset,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'PDF sahifa raqami', hintText: '5'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: context.appColors.danger)),
            ],
            const SizedBox(height: 16),
            if (_loading) ...[
              LinearProgressIndicator(value: _progress == 0 ? null : _progress, minHeight: 6),
              const SizedBox(height: 10),
            ],
            PrimaryButton(label: 'Yuklash', icon: Icons.upload_rounded, loading: _loading, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
