import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lingua_path/api.dart';
import 'package:lingua_path/app_controller.dart';
import 'package:lingua_path/main.dart';
import 'package:lingua_path/journal_screen.dart';
import 'package:lingua_path/ui_text_data.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('no interface text promises XP or credits', () {
    for (final resource in uiTranslations.values) {
      for (final text in resource.values) {
        expect(text, isNot(matches(RegExp(r'XP|credit|kredit',
            caseSensitive: false))));
      }
    }
  });

  testWidgets('sample answer enables sending and advances the recorded task',
      (tester) async {
    final c = AppController(demo: true)..appLanguage = 'en';
    await c.startChat();
    await tester.pumpWidget(LinguaApp(controller: c, initialize: false));
    await tester.tap(find.text(c.tr('demoSampleAnswer')));
    await tester.pump();
    final send = find.widgetWithIcon(IconButton, Icons.arrow_upward_rounded);
    await tester.tap(send);
    await tester.pump(const Duration(milliseconds: 350));
    expect(c.practiceCompleted, 1);
    expect(c.messages.where((message) => message.user).length, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('three main destinations and a secondary journal, without a feed',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = AppController(demo: true)
      ..dashboard = demoDashboard()
      ..appLanguage = 'en';
    await tester.pumpWidget(LinguaApp(controller: c, initialize: false));
    expect(find.byType(NavigationDestination), findsNWidgets(3));
    expect(find.text('Feed'), findsNothing);
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(c.tr('journal')));
    await tester.tap(find.text(c.tr('journal')));
    await tester.pumpAndSettle();
    expect(find.byType(JournalScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('demo initialization and chat never contact external services',
      () async {
    final c = AppController(
        demo: true,
        api: TutorApi(client: MockClient((_) async {
          fail('The scripted preview must not issue HTTP requests.');
        })));
    await c.initialize();
    await c.startChat();
    await c.send('Hello, my name is Alex.');
    expect(c.chatError, isNull);
    expect(c.dashboard!.levels.first.lessons.length, 3);
    expect(c.messages.where((message) => !message.user).length, 2);
    c.dispose();
  });
}
