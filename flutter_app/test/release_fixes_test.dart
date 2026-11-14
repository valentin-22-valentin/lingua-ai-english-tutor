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
import 'package:lingua_path/screens.dart';

http.Response jsonResponse(Map<String, dynamic> value) =>
    http.Response(jsonEncode(value), 200);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('closing a drawer twice cannot pop the application route',
      (tester) async {
    tester.view.physicalSize = const Size(500, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = AppController(demo: true)..dashboard = demoDashboard();
    await tester.pumpWidget(LinguaApp(controller: c, initialize: false));
    final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold).first);
    scaffold.openDrawer();
    await tester.pump(const Duration(milliseconds: 350));
    final sidebar = tester.widget<Sidebar>(find.byType(Sidebar));
    final context = tester.element(find.byType(Sidebar));
    sidebar.choose(context, 1);
    sidebar.choose(context, 3);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(c.tab, 3);
    expect(find.byType(AppShell), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('successful beginner onboarding clears failed placement state',
      () async {
    final chatPayloads = <Map<String, dynamic>>[];
    final c = AppController(
        profileId: 'profile',
        api: TutorApi(client: MockClient((r) async {
          if (r.url.path == '/api/onboarding') {
            return jsonResponse({'current_level': 'A1'});
          }
          if (r.url.path.startsWith('/api/dashboard/')) {
            return jsonResponse({
              'profile': {'current_level': 'A1', 'target_language': 'en'},
              'next_lesson': {'id': 1},
              'levels': []
            });
          }
          chatPayloads.add(Map<String, dynamic>.from(jsonDecode(r.body)));
          return jsonResponse({
            'session_id': 'lesson-session',
            'lesson_id': 1,
            'text': 'Hello!'
          });
        })));
    c.sessionId = 'placement-session';
    c.activeLessonId = 99;
    c.messages.add(ChatMessage('Old placement answer', user: true));
    c.pending = {'request_id': 'failed-placement'};
    c.chatError = 'Old failure';
    await c.onboard('beginner');
    expect(c.messages, isEmpty);
    expect(c.pending, isNull);
    expect(c.chatError, isNull);
    await c.startChat();
    expect(chatPayloads.single.containsKey('session_id'), isFalse);
    expect(chatPayloads.single['message'], isNull);
    expect(c.sessionId, 'lesson-session');
    expect(c.messages.single.text, 'Hello!');
    c.dispose();
  });

  test(
      'resume restores all saved messages, not just the final teacher response',
      () async {
    final c = AppController(
        profileId: 'profile',
        api: TutorApi(
            client: MockClient((r) async => jsonResponse({
                  'session_id': 'session',
                  'lesson_id': 1,
                  'resumed': true,
                  'text': 'Second teacher message',
                  'messages': [
                    {'role': 'assistant', 'content': 'First teacher message'},
                    {'role': 'user', 'content': 'Saved learner answer'},
                    {'role': 'assistant', 'content': 'Second teacher message'}
                  ]
                }))));
    await c.startChat();
    expect(c.messages.length, 3);
    expect(c.messages[1].user, isTrue);
    expect(c.messages.last.text, 'Second teacher message');
    expect(c.pending, isNull);
    c.dispose();
  });

  test('failed send can reload committed history without getting stuck',
      () async {
    var calls = 0;
    final c = AppController(
        profileId: 'profile',
        api: TutorApi(client: MockClient((r) async {
          calls++;
          if (calls == 1) {
            return http.Response('{"detail":"Temporary error"}', 502);
          }
          expect(jsonDecode(r.body)['message'], isNull);
          return jsonResponse({
            'session_id': 'session',
            'resumed': true,
            'messages': [
              {'role': 'user', 'content': 'Saved learner answer'},
              {'role': 'assistant', 'content': 'Saved reply'}
            ]
          });
        })));
    await c.send('Saved learner answer');
    expect(c.pending, isNotNull);
    await c.reloadSavedChat();
    expect(c.pending, isNull);
    expect(c.chatError, isNull);
    expect(c.messages.where((m) => m.user).length, 1);
    c.dispose();
  });

  testWidgets(
      'history paginates old sessions and transcripts without AI requests',
      (tester) async {
    final paths = <String>[];
    final c = AppController(
        profileId: 'profile',
        api: TutorApi(client: MockClient((r) async {
          paths.add(r.url.path);
          if (r.url.path == '/api/sessions/profile') {
            return jsonResponse({
              'sessions': [
                {
                  'id': 'old',
                  'title': 'An old lesson',
                  'status': 'completed',
                  'started_at': '2026-01-01T12:00:00Z'
                }
              ],
              'has_more': false
            });
          }
          final offset = r.url.queryParameters['offset'];
          return jsonResponse({
            'messages': [
              {
                'role': offset == '0' ? 'user' : 'assistant',
                'content': offset == '0'
                    ? 'My saved answer.'
                    : 'The saved teacher reply.'
              }
            ],
            'has_more': offset == '0'
          });
        })))
      ..appLanguage = 'en';
    c.tab = 5;
    await tester.pumpWidget(LinguaApp(controller: c, initialize: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('An old lesson'));
    await tester.pumpAndSettle();
    expect(find.text('My saved answer.'), findsOneWidget);
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(find.text('The saved teacher reply.'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(paths.every((p) => p.startsWith('/api/sessions/')), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('history response after logout never exposes the old user text',
      (tester) async {
    final response = Completer<http.Response>();
    final c = AppController(
        profileId: 'profile',
        api: TutorApi(client: MockClient((r) => response.future)))
      ..tab = 5;
    await tester.pumpWidget(LinguaApp(controller: c, initialize: false));
    await tester.pump();
    c.logout();
    await tester.pump();
    response.complete(jsonResponse({
      'sessions': [
        {'title': 'Private old lesson'}
      ],
      'has_more': false
    }));
    await tester.pumpAndSettle();
    expect(find.text('Private old lesson'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
