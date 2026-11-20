import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mentor_ai/core/theme/app_colors.dart';
import 'package:mentor_ai/core/theme/app_theme.dart';
import 'package:mentor_ai/core/widgets/motion.dart';
import 'package:mentor_ai/core/widgets/otp_field.dart';
import 'package:mentor_ai/features/assignments/data/assignment_models.dart';
import 'package:mentor_ai/features/assignments/presentation/widgets.dart';
import 'package:mentor_ai/features/auth/presentation/welcome_screen.dart';
import 'package:mentor_ai/features/student/home/student_bento.dart';
import 'package:mentor_ai/features/auth/presentation/email_screen.dart';

Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) => ProviderScope(
      child: MaterialApp(theme: buildTheme(brightness, AccentColor.indigo.color), home: child),
    );

void main() {
  testWidgets('Welcome: ikkala rol va kirish tugmasi ko\'rinadi', (tester) async {
    await tester.pumpWidget(_wrap(const WelcomeScreen()));
    // Logotip cheksiz "suzadi": pumpAndSettle tugamaydi, kirish animatsiyasi vaqtini kutamiz
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text("Men o'qituvchiman"), findsOneWidget);
    expect(find.text("Men o'quvchiman"), findsOneWidget);
    expect(find.textContaining('Kirish', findRichText: true), findsOneWidget);
  });

  testWidgets('Welcome: kichik ekranda va qorong\'i temada toshib ketmaydi', (tester) async {
    tester.view.physicalSize = const Size(720, 1280); // 360x640 dp
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(const WelcomeScreen(), brightness: Brightness.dark));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(tester.takeException(), isNull);
  });

  testWidgets('OtpField: 6 raqam kiritilganda onCompleted chaqiriladi', (tester) async {
    final controller = TextEditingController();
    String? completed;
    await tester.pumpWidget(
      _wrap(Scaffold(body: Padding(
        padding: const EdgeInsets.all(20),
        child: OtpField(controller: controller, onCompleted: (v) => completed = v),
      ))),
    );
    await tester.enterText(find.byType(TextField), '12ab3456');
    await tester.pump();
    // Faqat raqamlar qabul qilinadi
    expect(controller.text, '123456');
    expect(completed, '123456');
    expect(find.text('1'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets("Natija: o'quvchida xato misol tagida \"Nega?\", ustozda qisqa belgi", (tester) async {
    const items = [
      GradedItem(number: '1', verdict: Verdict.correct, comment: ''),
      GradedItem(number: '2', verdict: Verdict.incorrect, comment: 'Maxraj xato', studentAnswer: r'$rac{3}{5}$'),
      GradedItem(number: '3', verdict: Verdict.partial, comment: '', explanation: 'Qavsni ochishda ishora almashadi.'),
    ];
    await tester.pumpWidget(_wrap(const Scaffold(body: SingleChildScrollView(
      child: GradedItemsList(items: items, askSubmissionId: 's1'),
    ))));
    expect(find.text('Nega?'), findsOneWidget); // faqat tushuntirilmagan xato misolda
    expect(find.text('Qavsni ochishda ishora almashadi.'), findsOneWidget);
    expect(find.text('Maxraj xato'), findsNothing);

    await tester.pumpWidget(_wrap(const Scaffold(body: SingleChildScrollView(child: GradedItemsList(items: items)))));
    expect(find.text('Nega?'), findsNothing);
    expect(find.text('Maxraj xato'), findsOneWidget);
  });

  testWidgets("Email: '@' ikonkasi yo'q, domen tugmasi manzilni to'ldiradi", (tester) async {
    await tester.pumpWidget(_wrap(const EmailScreen()));
    expect(find.byIcon(Icons.alternate_email_rounded), findsNothing);
    await tester.enterText(find.byType(TextField), 'ali');
    await tester.pumpAndSettle(); // tugmalar ochilish animatsiyasi
    expect(find.text('@gmail.com'), findsOneWidget);
    await tester.tap(find.text('@gmail.com'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'ali@gmail.com');

    await tester.enterText(find.byType(TextField), 'ali@gmial.com');
    await tester.pumpAndSettle();
    expect(find.textContaining('ali@gmail.com', findRichText: true), findsOneWidget); // "Balki ...?"
  });

  testWidgets("Skelet SliverFillRemaining ichida xatosiz chiziladi (bosh sahifa yuklanishi)", (tester) async {
    await tester.pumpWidget(_wrap(const Scaffold(
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(child: SizedBox(height: 150)),
        SliverFillRemaining(hasScrollBody: false, child: SkeletonList(count: 4)),
      ]),
    )));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.byType(SkeletonBox), findsWidgets);
  });

  testWidgets("O'quvchi bento: kechikkan vazifa bo'lsa 'hammasi topshirilgan' demaydi", (tester) async {
    StudentAssignment task(String id, Duration fromNow, {bool late = true}) => StudentAssignment.fromJson({
          'id': id, 'group_name': '7-B', 'subject': 'math', 'teacher_name': 'Ustoz', 'title': 'Vazifa $id',
          'source_type': 'text', 'items': <dynamic>[], 'rubric': <dynamic>[], 'image_urls': <dynamic>[],
          'due_at': DateTime.now().add(fromNow).toUtc().toIso8601String(),
          'allow_late': late, 'late_penalty_percent': 0, 'grading_scale': '5', 'submission': null,
        });
    Future<void> show(List<StudentAssignment> list) async {
      await tester.pumpWidget(_wrap(Scaffold(body: Padding(
        padding: const EdgeInsets.all(16),
        child: StudentBento(list: list),
      ))));
      await tester.pump(const Duration(seconds: 1));
    }

    await show([task('1', const Duration(days: -3)), task('2', const Duration(days: -1))]);
    expect(find.text('Kechikkan'), findsOneWidget);
    expect(find.text('2 ta'), findsOneWidget);
    expect(find.text('Hammasi topshirilgan'), findsNothing);

    // Tizim shrifti 1.3 baravar kattalashtirilganda ham toshmasin
    await tester.pumpWidget(_wrap(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
      child: Scaffold(body: Padding(
        padding: const EdgeInsets.all(16),
        child: StudentBento(list: [task('4', const Duration(days: -2))]),
      )),
    )));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);

    await show([task('3', const Duration(hours: 5))]);
    expect(find.text('Keyingi muddat'), findsOneWidget);
    expect(find.text('5 soat').evaluate().isNotEmpty || find.text('4 soat').evaluate().isNotEmpty, isTrue);
    expect(tester.takeException(), isNull);
  });
}
