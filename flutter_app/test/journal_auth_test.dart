import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lingua_path/api.dart';
import 'package:lingua_path/app_controller.dart';
import 'package:lingua_path/main.dart';
import 'package:lingua_path/models.dart';
import 'package:lingua_path/journal_state.dart';
import 'package:lingua_path/screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('beginner onboarding remains usable without placement curriculum',
      (tester) async {
    final c = AppController(profileId: 'profile')
      ..dashboard =
          Dashboard(username: 'Alex', currentLevel: 'ONBOARDING', levels: []);
    await tester.pumpWidget(LinguaApp(controller: c, initialize: false));
    expect(find.text('Az alapoktól kezdem'), findsOneWidget);
    final placement = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Megnézem, hol tartok'));
    expect(placement.onPressed, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('settings sign-out returns to the sign-in screen',
      (tester) async {
    final c = AppController(profileId: 'profile')
      ..dashboard = Dashboard(username: 'Alex', currentLevel: 'A1', levels: [])
      ..tab = 3;
    await tester.pumpWidget(LinguaApp(controller: c, initialize: false));
    await tester.scrollUntilVisible(find.text('Kijelentkezés'), 200);
    await tester.tap(find.text('Kijelentkezés'));
    await tester.pumpAndSettle();
    expect(c.profileId, isEmpty);
    expect(c.dashboard, isNull);
    expect(find.byType(Form), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  test('stored discussion reload replaces local history without duplicates',
      () async {
    final api = TutorApi(
        client: MockClient((request) async => http.Response(
            jsonEncode({
              ...demoJournal(),
              'journal': [
                {
                  'id': 'entry',
                  'content': 'Private',
                  'discussion': [
                    {'message': 'Why?', 'text': 'Because'},
                    {'message': 'Example?', 'text': 'I walked.'}
                  ]
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'})));
    final p = JournalState(api: api, profile: () => 'profile', demo: false);
    p.discussions['entry'] = [
      {'role': 'user', 'text': 'Old'}
    ];
    await p.load();
    await p.load();
    expect(p.error, isNull);
    expect(p.discussions['entry']!.length, 4);
    expect(p.discussions['entry']!.last['text'], 'I walked.');
    p.dispose();
    api.close();
  });
  test('late response after auth retry cannot expire or expose new session',
      () async {
    for (final status in [200, 401]) {
      final waiting = Completer<http.Response>();
      var calls = 0;
      var expired = false;
      final api = TutorApi(
          token: 'old',
          client: MockClient((request) async {
            calls++;
            if (calls == 1) {
              return http.Response('{"detail":"Expired"}', 401);
            }
            return waiting.future;
          }));
      api.refreshAuthorization = () async {
        api.token = 'refreshed';
      };
      api.sessionExpired = () {
        expired = true;
      };
      final response = api.journalSummary('old-profile');
      await Future<void>.delayed(Duration.zero);
      expect(calls, 2);
      api.sessionGeneration++;
      api.token = 'new-account';
      waiting.complete(http.Response('{"detail":"Old","journal":[]}', status));
      await expectLater(response,
          throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 409)));
      expect(expired, isFalse);
      expect(api.token, 'new-account');
      api.close();
    }
  });
  test('journal retry keeps original UUID and content; discussion retry too',
      () async {
    final journal = <Map<String, dynamic>>[],
        discussion = <Map<String, dynamic>>[];
    final entry = {
      'id': 'entry',
      'content': 'Today I walk.',
      'feedback': {'text': 'Try past tense.', 'corrections': []}
    };
    final api = TutorApi(client: MockClient((request) async {
      if (request.method == 'GET') {
        return http.Response(
            jsonEncode({
              ...demoJournal(),
              'journal': [entry]
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      if (request.url.path.endsWith('/discuss')) {
        discussion.add(payload);
        return discussion.length == 1
            ? http.Response('{"detail":"Retry"}', 502)
            : http.Response('{"text":"Use walked."}', 200);
      }
      journal.add(payload);
      return journal.length == 1
          ? http.Response('{"detail":"Retry"}', 502)
          : http.Response(jsonEncode(entry), 200);
    }));
    final p = JournalState(api: api, profile: () => 'profile', demo: false);
    expect(await p.write('Today I walk.'), isFalse);
    expect(await p.write('New text'), isFalse);
    expect(journal.length, 1);
    expect(await p.write('', retry: true), isTrue);
    expect(journal.first, journal.last);
    expect(p.entries.length, 1);
    expect(await p.discuss('entry', 'Why?'), isFalse);
    expect(await p.discuss('entry', '', retry: true), isTrue);
    expect(discussion.first, discussion.last);
    expect(p.discussions['entry']!.length, 2);
    p.dispose();
    api.close();
  });
  test('logout clears private state and rejects late journal result', () async {
    final waiting = Completer<http.Response>();
    final c = AppController(
        profileId: 'profile',
        api: TutorApi(
            token: 'token', client: MockClient((request) => waiting.future)));
    c.journal.data = {
      ...demoJournal(),
      'journal': [
        {'id': 'secret', 'content': 'Private'}
      ]
    };
    c.messages.add(ChatMessage('Private conversation'));
    final operation = c.journal.write('New private text');
    await Future<void>.delayed(Duration.zero);
    c.logout();
    waiting.complete(http.Response('{"id":"late","content":"Private"}', 200));
    expect(await operation, isFalse);
    expect(c.journal.data, isNull);
    expect(c.messages, isEmpty);
    expect(c.api.token, isEmpty);
    expect(c.profileId, isEmpty);
    c.dispose();
  });
  test('email confirmation does not invent an authenticated session', () async {
    final c = AppController(
        api: TutorApi(
            client: MockClient((request) async =>
                http.Response('{"confirmation_required":true}', 200))));
    await c.authenticate('a@example.test', 'longpassword', username: 'Alex');
    expect(c.configured, isFalse);
    expect(c.authNotice, contains('erősítsd meg'));
    expect(c.api.token, isEmpty);
    c.dispose();
  });
  test('401 refresh updates bearer once and does not persist tokens', () async {
    var protected = 0, refreshes = 0;
    final c = AppController(
        profileId: 'profile',
        api: TutorApi(
            token: 'old',
            client: MockClient((request) async {
              if (request.url.path.endsWith('/refresh')) {
                refreshes++;
                return http.Response(
                    '{"profile_id":"profile","access_token":"new","refresh_token":"r2","expires_in":3600}',
                    200);
              }
              protected++;
              if (protected == 1) {
                return http.Response('{"detail":"Expired"}', 401);
              }
              expect(request.headers['Authorization'], 'Bearer new');
              return http.Response(jsonEncode(demoJournal()), 200,
                  headers: {'content-type': 'application/json; charset=utf-8'});
            })))
      ..refreshToken = 'refresh';
    await c.journal.load();
    expect(refreshes, 1);
    expect(c.api.token, 'new');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
    c.dispose();
  });
  testWidgets('blank profile has working registration form', (tester) async {
    final c = AppController();
    await tester.pumpWidget(LinguaApp(controller: c, initialize: false));
    expect(find.text('Bejelentkezés'), findsOneWidget);
    await tester.ensureVisible(find.text('Új vagy itt? Hozz létre fiókot'));
    await tester.tap(find.text('Új vagy itt? Hozz létre fiókot'));
    await tester.pump();
    expect(find.text('Fiók létrehozása'), findsOneWidget);
    expect(find.text('Neved'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  for (final theme in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('journal ${theme.name} at narrow phone is polished empty state',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = AppController(demo: true)
        ..dashboard = demoDashboard()
        ..tab = 4
        ..theme = theme;
      c.journal.data = demoJournal();
      await tester.pumpWidget(LinguaApp(controller: c, initialize: false));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Mi történt ma?'), findsOneWidget);
      expect(find.text('A saját szavaiddal'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('settings fit enlarged phone text without gamification controls',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = AppController(demo: true)
      ..dashboard = demoDashboard()
      ..tab = 3;
    c.journal.data = demoJournal();
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('hu'),
        supportedLocales: const [Locale('hu')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: linguaTheme(Brightness.light),
        home: MediaQuery(
            data: const MediaQueryData(
                size: Size(360, 800), textScaler: TextScaler.linear(1.3)),
            child: AppShell(controller: c))));
    expect(find.text('Részt veszek a heti ranglistán'), findsNothing);
    expect(find.text('Beállítások mentése'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
