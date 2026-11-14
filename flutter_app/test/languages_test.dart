import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lingua_path/api.dart';
import 'package:lingua_path/app_controller.dart';
import 'package:lingua_path/language_settings.dart';
import 'package:lingua_path/main.dart';
import 'package:lingua_path/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('unchanged and unsupported preferences make no request', () async {
    var calls = 0;
    final c = AppController(
        profileId: 'p',
        api: TutorApi(client: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        })));
    expect(await c.updateLanguages('hu', 'hu'), isTrue);
    expect(await c.updateLanguages('xx', 'en'), isFalse);
    expect(await c.updateLanguages('en', 'xx'), isFalse);
    expect(calls, 0);
    c.dispose();
  });

  test('English explanations are allowed; no target selector payload',
      () async {
    Map<String, dynamic>? payload;
    final c = AppController(
        profileId: 'p',
        api: TutorApi(client: MockClient((r) async {
          payload = jsonDecode(r.body) as Map<String, dynamic>;
          expect(r.url.path, '/api/profile/languages');
          return http.Response('{}', 200);
        })));
    expect(await c.updateLanguages('en', 'fr'), isTrue);
    expect(payload,
        {'profile_id': 'p', 'native_language': 'en', 'app_language': 'fr'});
    expect(c.nativeLanguage, 'en');
    expect(c.targetLanguage, 'en');
    expect(c.appLanguage, 'fr');
    c.dispose();
  });

  test('failed preference save preserves the current conversation', () async {
    final c = AppController(
        profileId: 'p',
        api: TutorApi(
            client: MockClient(
                (_) async => http.Response('{"detail":"Busy"}', 409))))
      ..sessionId = 'old';
    expect(await c.updateLanguages('de', 'fr'), isFalse);
    expect(c.nativeLanguage, 'hu');
    expect(c.appLanguage, 'hu');
    expect(c.sessionId, 'old');
    expect(c.languageError, 'Busy');
    c.dispose();
  });

  test('explanation and interface changes preserve English tasks and history',
      () async {
    var calls = 0;
    final c = AppController(
        profileId: 'p',
        api: TutorApi(client: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        })))
      ..dashboard = demoDashboard()
      ..selectedLevel = 'A1'
      ..sessionId = 'keep-me'
      ..practiceCompleted = 4;
    c.messages.add(ChatMessage('Hello, my name is Alex.', user: true));
    final originalLevels = c.dashboard!.levels;
    expect(await c.updateLanguages('de', 'fr'), isTrue);
    expect(c.nativeLanguage, 'de');
    expect(c.appLanguage, 'fr');
    expect(c.targetLanguage, 'en');
    expect(c.sessionId, 'keep-me');
    expect(c.practiceCompleted, 4);
    expect(c.selectedLevel, 'A1');
    expect(c.messages.single.text, 'Hello, my name is Alex.');
    expect(c.dashboard!.levels, same(originalLevels));
    expect(c.contentGeneration, 0);
    expect(calls, 1);
    c.dispose();
  });

  test('audio or AI work blocks a preference save', () async {
    var calls = 0;
    final c = AppController(
        profileId: 'p',
        api: TutorApi(client: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        })))
      ..audioActive = true;
    expect(await c.updateLanguages('de', 'fr'), isFalse);
    c.audioActive = false;
    c.chatting = true;
    expect(await c.updateLanguages('de', 'fr'), isFalse);
    expect(calls, 0);
    c.dispose();
  });

  test(
      'late save cannot repopulate a logged-out account or clear a newer operation',
      () async {
    final response = Completer<http.Response>();
    final c = AppController(
        profileId: 'p',
        api: TutorApi(client: MockClient((_) => response.future)));
    final saving = c.updateLanguages('de', 'fr');
    await Future<void>.delayed(Duration.zero);
    c.logout();
    c.languagesSaving = true;
    response.complete(http.Response('{}', 200));
    expect(await saving, isFalse);
    expect(c.profileId, isEmpty);
    expect(c.dashboard, isNull);
    expect(c.nativeLanguage, 'hu');
    expect(c.languagesSaving, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_language'), isNull);
    c.dispose();
  });

  testWidgets(
      'two language preferences; English is fixed and explanations can be English',
      (tester) async {
    final c = AppController(demo: true)
      ..dashboard = demoDashboard()
      ..appLanguage = 'en';
    await tester.pumpWidget(MaterialApp(
        theme: linguaTheme(Brightness.light),
        home: Scaffold(
            body: SingleChildScrollView(
                child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: LanguageSettings(controller: c))))));
    final fields = tester
        .widgetList<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>))
        .toList();
    expect(fields.length, 2);
    expect(fields[0].decoration.labelText, c.tr('explanationLanguage'));
    expect(fields[1].decoration.labelText, c.tr('interface'));
    expect(find.text(c.tr('learningEnglish')), findsOneWidget);
    final dropdowns = tester
        .widgetList<DropdownButton<String>>(find.byType(DropdownButton<String>))
        .toList();
    expect(dropdowns[0].items!.length, 6);
    expect(dropdowns[0].items!.singleWhere((e) => e.value == 'en').enabled,
        isTrue);
    fields[0].onChanged!('en');
    await tester.pump();
    await tester.ensureVisible(find.text(c.tr('save')));
    await tester.tap(find.text(c.tr('save')));
    await tester.pumpAndSettle();
    expect(c.nativeLanguage, 'en');
    expect(c.dashboard!.currentLevel, 'A1');
    expect(c.targetLanguage, 'en');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
