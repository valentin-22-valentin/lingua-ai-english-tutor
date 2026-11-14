import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lingua_path/api.dart';
import 'package:lingua_path/app_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  http.Response dashboard(String locale) => http.Response(
      jsonEncode({
        'profile': {
          'native_language': 'hu',
          'target_language': 'en',
          'app_language': locale,
          'current_level': 'A2'
        },
        'levels': []
      }),
      200);
  http.Response auth() => http.Response(
      jsonEncode({
        'profile_id': 'profile',
        'access_token': 'test',
        'expires_in': 3600
      }),
      200);

  test('changing sign-in language clears old authentication notices', () async {
    final c = AppController()
      ..authError = 'Previous error'
      ..authNotice = 'Previous notice';
    await c.setInterfaceLanguage('en');
    expect(c.authError, isNull);
    expect(c.authNotice, isNull);
    c.dispose();
  });

  test('sign-in preference is persisted before profile loading', () async {
    var stored = 'hu';
    final paths = <String>[];
    final c = AppController(api: TutorApi(client: MockClient((r) async {
      paths.add(r.url.path);
      if (r.url.path == '/api/auth/login') return auth();
      if (r.url.path == '/api/profile/interface-language') {
        expect(jsonDecode(r.body),
            {'profile_id': 'profile', 'app_language': 'en'});
        stored = 'en';
        return http.Response('{}', 200);
      }
      if (r.url.path.startsWith('/api/dashboard/')) return dashboard(stored);
      return http.Response('{}', 200);
    })));
    await c.setInterfaceLanguage('en');
    await c.authenticate('test@example.com', 'password');
    expect(c.appLanguage, 'en');
    expect(c.nativeLanguage, 'hu');
    expect(c.targetLanguage, 'en');
    expect(c.dashboard!.currentLevel, 'A2');
    expect(paths.indexOf('/api/profile/interface-language'),
        lessThan(paths.indexOf('/api/dashboard/profile')));
    expect(paths.where((p) => p == '/api/profile/languages'), isEmpty);
    c.dispose();
  });

  test('without a local choice the saved profile language wins', () async {
    final paths = <String>[];
    final c = AppController(api: TutorApi(client: MockClient((r) async {
      paths.add(r.url.path);
      if (r.url.path == '/api/auth/login') return auth();
      if (r.url.path.startsWith('/api/dashboard/')) return dashboard('fr');
      return http.Response('{}', 200);
    })));
    await c.authenticate('test@example.com', 'password');
    expect(c.appLanguage, 'fr');
    expect(paths, isNot(contains('/api/profile/interface-language')));
    c.dispose();
  });

  test('remembered device preference survives the next sign-in', () async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    var stored = 'hu';
    final c = AppController(api: TutorApi(client: MockClient((r) async {
      if (r.url.path == '/api/auth/login') return auth();
      if (r.url.path == '/api/profile/interface-language') {
        stored = jsonDecode(r.body)['app_language'] as String;
        return http.Response('{}', 200);
      }
      if (r.url.path.startsWith('/api/dashboard/')) return dashboard(stored);
      return http.Response('{}', 200);
    })));
    await c.initialize();
    await c.authenticate('test@example.com', 'password');
    expect(stored, 'en');
    expect(c.appLanguage, 'en');
    c.dispose();
  });

  test('failed preference save preserves selection and retries on refresh',
      () async {
    var saves = 0;
    var stored = 'hu';
    final c = AppController(api: TutorApi(client: MockClient((r) async {
      if (r.url.path == '/api/auth/login') return auth();
      if (r.url.path == '/api/profile/interface-language') {
        saves++;
        if (saves == 1) return http.Response('{}', 503);
        stored = 'en';
        return http.Response('{}', 200);
      }
      if (r.url.path.startsWith('/api/dashboard/')) return dashboard(stored);
      return http.Response('{}', 200);
    })));
    await c.setInterfaceLanguage('en');
    await c.authenticate('test@example.com', 'password');
    expect(saves, 1);
    expect(c.appLanguage, 'en');
    expect(c.languageError, isNotNull);
    await c.refresh();
    expect(saves, 2);
    expect(c.appLanguage, 'en');
    expect(c.languageError, isNull);
    c.dispose();
  });

  test('logout during preference save cannot restore the old account',
      () async {
    final response = Completer<http.Response>();
    final paths = <String>[];
    final c = AppController(api: TutorApi(client: MockClient((r) async {
      paths.add(r.url.path);
      if (r.url.path == '/api/auth/login') return auth();
      return response.future;
    })));
    await c.setInterfaceLanguage('en');
    final signingIn = c.authenticate('test@example.com', 'password');
    await Future<void>.delayed(Duration.zero);
    c.logout();
    response.complete(http.Response('{}', 200));
    await signingIn;
    expect(c.profileId, isEmpty);
    expect(c.dashboard, isNull);
    expect(paths.any((p) => p.startsWith('/api/dashboard/')), isFalse);
    c.dispose();
  });
}
