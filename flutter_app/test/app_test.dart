import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lingua_path/api.dart';
import 'package:lingua_path/app_controller.dart';
import 'package:lingua_path/chat_screen.dart';
import 'package:lingua_path/main.dart';
import 'package:lingua_path/models.dart';
import 'package:lingua_path/screens.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('empty profile name has safe avatar fallback', () {
    expect(avatarInitial('  '), 'L');
    expect(avatarInitial(null), 'L');
  });
  testWidgets('tracked lesson progress renders at narrow width',
      (tester) async {
    final c = AppController(profileId: 'profile', demo: true)
      ..dashboard = demoDashboard()
      ..sessionId = 'session'
      ..practiceCompleted = 5;
    c.messages.add(ChatMessage('Practise introducing yourself.'));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(width: 320, child: ChatScreen(controller: c)))));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    final indicator = tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(indicator.value, 5 / 8);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  test('completed chat restarts without old session and follows promoted level',
      () async {
    final payloads = <Map<String, dynamic>>[];
    final c = AppController(
        profileId: 'profile',
        api: TutorApi(client: MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(
                '{"profile":{"username":"Alex","current_level":"A2"},"levels":[]}',
                200);
          }
          payloads.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
              '{"session_id":"new-session","text":"Hello","lesson_complete":false}',
              200);
        })))
      ..dashboard = demoDashboard()
      ..selectedLevel = 'A1'
      ..sessionId = 'old-session'
      ..completion = 'Done';
    c.messages.add(ChatMessage('Old chat'));
    await c.refresh();
    expect(c.selectedLevel, 'A2');
    await c.startChat();
    expect(payloads.single.containsKey('session_id'), isFalse);
    expect(c.messages.length, 1);
    expect(c.completion, isNull);
    c.dispose();
  });
  test('microphone upload explicitly declares audio/wav', () async {
    final client = MockClient((request) async {
      expect(request.body.toLowerCase(), contains('content-type: audio/wav'));
      return http.Response('{"text":"Hello"}', 200);
    });
    final api = TutorApi(client: client);
    expect(
        await api.transcribe('profile', Uint8List.fromList([1, 2])), 'Hello');
    api.close();
  });
  test('failed chat retry retains id and user bubble exactly once', () async {
    final payloads = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      payloads.add(jsonDecode(request.body) as Map<String, dynamic>);
      if (payloads.length == 1) {
        return http.Response('{"detail":"Try again"}', 502);
      }
      return http.Response(
          '{"session_id":"session","text":"Hello","lesson_complete":false}',
          200);
    });
    final c =
        AppController(api: TutorApi(client: client), profileId: 'profile');
    await c.send('Hi');
    expect(c.pending, isNotNull);
    await c.send('different message');
    expect(payloads.length, 1);
    await c.send(null, retry: true);
    expect(payloads[1], equals(payloads[0]));
    expect(c.messages.where((m) => m.user).length, 1);
    expect(c.messages.last.text, 'Hello');
    expect(c.pending, isNull);
    c.dispose();
  });
  test('WAV header matches mono PCM 16000Hz audio', () {
    final bytes = pcmToWav(Uint8List.fromList([1, 2, 3, 4]));
    expect(ascii.decode(bytes.sublist(0, 4)), 'RIFF');
    expect(ascii.decode(bytes.sublist(8, 12)), 'WAVE');
    final header = ByteData.sublistView(bytes);
    expect(header.getUint32(24, Endian.little), 16000);
    expect(header.getUint32(40, Endian.little), 4);
    expect(bytes.sublist(44), [1, 2, 3, 4]);
  });
  test('browser PCM keeps its measured 48kHz duration in WAV metadata', () {
    // Chrome may return native 48 kHz PCM although the recorder asks for 16 kHz.
    final pcm = Uint8List(48000 * 2 * 6);
    final rate = pcmSampleRate(pcm, const Duration(seconds: 6));
    final wav = pcmToWav(pcm, sampleRate: rate);
    final header = ByteData.sublistView(wav);
    expect(rate, 48000);
    expect(header.getUint32(24, Endian.little), 48000);
    expect(header.getUint32(40, Endian.little) / (48000 * 2), 6);
  });
  test('browser PCM uses a safe default for an incomplete short capture', () {
    expect(pcmSampleRate(Uint8List(2), const Duration(milliseconds: 20)),
        16000);
  });
  test('theme preference persists', () async {
    final c = AppController(demo: true);
    await c.setTheme(ThemeMode.dark);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme'), 'dark');
    c.dispose();
  });
  for (final theme in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('real path renders in ${theme.name} theme at phone width',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = AppController(demo: true)
        ..dashboard = demoDashboard()
        ..selectedLevel = 'A1'
        ..theme = theme;
      await tester.pumpWidget(LinguaApp(controller: c, initialize: false));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('DEMÓ'), findsOneWidget);
      expect(find.text('A következő lépés\nmár a tiéd.'), findsOneWidget);
      expect(find.text('Kezdjük el'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final context = tester.element(find.byType(PathScreen));
      expect(Theme.of(context).brightness,
          theme == ThemeMode.dark ? Brightness.dark : Brightness.light);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('locked level cannot become selected', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = AppController(demo: true)
      ..dashboard = demoDashboard()
      ..selectedLevel = 'A1';
    await tester.pumpWidget(LinguaApp(controller: c, initialize: false));
    c.dashboard!.levels.add(CourseLevel(
        level: 'A2',
        title: 'Locked test level',
        status: 'locked',
        lessons: []));
    c.notifyListeners();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('Locked test level'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.selectedLevel, 'A1');
    expect(
        find.text(
            'Ez a szint az előző szint sikeres teljesítése után nyílik meg.'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('small phone at enlarged text has no overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = AppController(demo: true)
      ..dashboard = demoDashboard()
      ..selectedLevel = 'A1';
    await tester.pumpWidget(MaterialApp(
        theme: linguaTheme(Brightness.light),
        home: MediaQuery(
            data: const MediaQueryData(
                size: Size(320, 720), textScaler: TextScaler.linear(1.3)),
            child: AppShell(controller: c))));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  test('backend status determines available lessons', () {
    final level = CourseLevel.fromJson({
      'level': 'B1',
      'status': 'current',
      'lessons': [
        {'id': 88, 'title': 'Travel', 'status': 'available'},
        {'id': 89, 'title': 'Exam', 'status': 'locked', 'is_level_exam': true}
      ]
    });
    expect(level.lessons.first.status, 'available');
    expect(level.lessons.last.exam, isTrue);
  });
}
