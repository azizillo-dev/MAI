import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mentor_ai/core/theme/app_colors.dart';
import 'package:mentor_ai/core/theme/app_theme.dart';
import 'package:mentor_ai/core/widgets/otp_field.dart';
import 'package:mentor_ai/features/auth/presentation/welcome_screen.dart';

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
}
