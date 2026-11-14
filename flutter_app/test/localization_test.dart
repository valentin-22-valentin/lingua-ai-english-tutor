import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lingua_path/api.dart';
import 'package:lingua_path/app_controller.dart';
import 'package:lingua_path/main.dart';
import 'package:lingua_path/journal_state.dart';
import 'package:lingua_path/ui_text.dart';
import 'package:lingua_path/ui_text_data.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('history labels preserve accented characters in every translated locale', () {
    expect(UiText.get('hu', 'historyTitle'), 'Korábbi beszélgetések');
    expect(UiText.get('ro', 'historyTitle'), 'Conversații anterioare');
    expect(UiText.get('de', 'historyTitle'), 'Bisherige Gespräche');
    expect(UiText.get('es', 'historyMore'), 'Cargar más');
    expect(UiText.get('fr', 'historyClosed'), 'Terminée');
  });
  test('all six JSON resources match compiled messages and placeholders', () {
    final baseline = uiTranslations['en']!;
    final placeholders = RegExp(r'\{(\w+)\}');
    for (final code in UiText.codes) {
      final resource = Map<String, dynamic>.from(
          jsonDecode(File('lib/l10n/app_$code.json').readAsStringSync()));
      expect(resource, uiTranslations[code],
          reason: '$code generator is stale');
      expect(resource.keys.toSet(), baseline.keys.toSet());
      for (final entry in resource.entries) {
        final expected = placeholders
            .allMatches(baseline[entry.key]!)
            .map((m) => m.group(1)!)
            .toSet();
        expect(
            placeholders
                .allMatches(entry.value as String)
                .map((m) => m.group(1)!)
                .toSet(),
            expected,
            reason: '$code.${entry.key} placeholder parity');
        final text = UiText.get(code, entry.key,
            params: {for (final name in expected) name: 3});
        expect(text.trim(), isNotEmpty);
        expect(text, isNot(entry.key));
        expect(placeholders.hasMatch(text), isFalse);
      }
    }
    expect(UiText.get('en', 'practiceProgress', params: {'done': 3, 'total': 8}),
        contains('3'));
    expect(UiText.get('unsupported', 'password'), 'Password');
    expect(() => UiText.get('en', 'unknownKey'), throwsArgumentError);
    expect(() => UiText.get('en', 'practiceProgress'), throwsArgumentError);
  });
  test('API and state failures use the current interface language', () {
    final api = TutorApi()..interfaceLanguage = () => 'fr';
    expect(
        api.tr('responseUnreadable'), 'La réponse du service est illisible.');
    expect(
        UiText.serverError(
            'en',
            'Nem sikerült bejelentkezni. Ellenőrizd az adatokat és az e-mail megerősítését.',
            401),
        'Could not sign in. Check your details and confirm your email address.');
    expect(UiText.serverError('de', 'Unexpected internal detail', 502),
        UiText.get('de', 'aiResponseFailed'));
    expect(JournalState.readable(Exception(), 'es'),
        'No se pudo conectar. Vuelve a intentarlo.');
    api.close();
  });
  testWidgets('English authentication translates validation, toggle and footer',
      (tester) async {
    final c = AppController()..appLanguage = 'en';
    await tester.pumpWidget(LinguaApp(controller: c, initialize: false));
    await tester.pumpAndSettle();
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.byTooltip('Show password'), findsOneWidget);
    expect(find.text('Bejelentkezés'), findsNothing);
    expect(find.text('Jelszó'), findsNothing);
    await tester.ensureVisible(find.text('Sign in'));
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
    await tester.ensureVisible(find.text('New here? Create an account'));
    await tester.tap(find.text('New here? Create an account'));
    await tester.pump();
    expect(find.text('Your name'), findsOneWidget);
    expect(find.text('Already have an account? Sign in'), findsOneWidget);
    expect(find.textContaining('Your sign-in is not stored'), findsOneWidget);
    // Already-visible validation errors must follow a subsequent language change.
    final language = tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>));
    language.onChanged!('de');
    await tester.pumpAndSettle();
    expect(find.text('Gib eine gültige E-Mail-Adresse ein.'), findsOneWidget);
    expect(find.text('Verwende mindestens 8 Zeichen.'), findsOneWidget);
    expect(find.text('Enter a valid email address.'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  for (final locale in UiText.codes) {
    testWidgets('$locale fixed screen copy fits a narrow screen',
        (tester) async {
      tester.view.physicalSize = const Size(375, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = AppController(demo: true)
        ..appLanguage = locale
        ..dashboard = demoDashboard(ui: locale);
      c.journal.data = demoJournal(language: locale);
      await tester.pumpWidget(LinguaApp(controller: c, initialize: false));
      for (final tab in [0, 1, 4, 3]) {
        c.navigate(tab);
        await tester.pump(const Duration(milliseconds: 350));
        expect(tester.takeException(), isNull, reason: '$locale tab $tab');
        for (final label in find
            .descendant(
                of: find.byType(NavigationBar), matching: find.byType(Text))
            .evaluate()) {
          if ((label.widget as Text).data != UiText.get(locale, 'navChat')) {
            continue;
          }
          expect(
              tester.getSize(find.byWidget(label.widget)).height, lessThan(24),
              reason: '$locale chat navigation must stay one line');
        }
      }
      expect(find.text(UiText.get(locale, 'settingsTitle')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
