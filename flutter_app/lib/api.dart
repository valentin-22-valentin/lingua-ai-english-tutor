import 'dart:convert';
import 'ui_text.dart';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class ApiFailure implements Exception {
  final String message;
  final int? status;
  ApiFailure(this.message, [this.status]);
  @override
  String toString() => message;
}

class TutorApi {
  String Function()? interfaceLanguage;
  String tr(String key) => UiText.get(interfaceLanguage?.call() ?? 'hu', key);
  final String baseUrl;
  String token;
  int sessionGeneration = 0;
  final http.Client client;
  Future<void> Function()? prepareAuthorization;
  Future<void> Function()? refreshAuthorization;
  void Function()? sessionExpired;
  TutorApi({String? baseUrl, String? token, http.Client? client})
      : baseUrl = (baseUrl ??
                const String.fromEnvironment('API_BASE_URL',
                    defaultValue: 'http://127.0.0.1:8000'))
            .replaceAll(RegExp(r'/$'), ''),
        token = token ?? const String.fromEnvironment('ACCESS_TOKEN'),
        client = client ?? http.Client();
  Map<String, String> get headers => {
        'Content-Type': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token'
      };
  Uri uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);
  Map<String, dynamic> decode(http.Response response) {
    Object? body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      body = null;
    }
    if (response.statusCode >= 400) {
      final detail = body is Map ? body['detail'] : null;
      throw ApiFailure(
          UiText.serverError(interfaceLanguage?.call() ?? 'hu',
              detail is String ? detail : null, response.statusCode),
          response.statusCode);
    }
    if (body is! Map) {
      throw ApiFailure(tr('responseUnreadable'));
    }
    return Map<String, dynamic>.from(body);
  }

  Future<http.Response> authorized(
      Future<http.Response> Function() action) async {
    final generation = sessionGeneration;
    await prepareAuthorization?.call();
    if (generation != sessionGeneration) {
      throw ApiFailure(tr('sessionChanged'), 409);
    }
    var response = await action();
    if (generation != sessionGeneration) {
      throw ApiFailure(tr('sessionChanged'), 409);
    }
    if (response.statusCode == 401 && refreshAuthorization != null) {
      try {
        await refreshAuthorization!();
        if (generation != sessionGeneration) {
          throw ApiFailure(tr('sessionChanged'), 409);
        }
        response = await action();
      } catch (_) {
        if (generation == sessionGeneration) {
          sessionExpired?.call();
        }
        rethrow;
      }
    }
    if (generation != sessionGeneration) {
      throw ApiFailure(tr('sessionChanged'), 409);
    }
    if (response.statusCode == 401) {
      sessionExpired?.call();
    }
    return response;
  }

  Future<Map<String, dynamic>> get(String path,
          [Map<String, String>? query]) async =>
      decode(await authorized(() => client
          .get(uri(path, query), headers: headers)
          .timeout(const Duration(seconds: 25))));
  Future<Map<String, dynamic>> post(
          String path, Map<String, dynamic> body) async =>
      decode(await authorized(() => client
          .post(uri(path), headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 65))));
  Future<Map<String, dynamic>> auth(
          String action, Map<String, dynamic> body) async =>
      decode(await client
          .post(uri('/api/auth/$action'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 30)));
  Future<Map<String, dynamic>> saveLanguages(Map<String, dynamic> payload) =>
      post('/api/profile/languages', payload);
  Future<Map<String, dynamic>> dashboard(String profile) =>
      get('/api/dashboard/$profile');
  Future<Map<String, dynamic>> sessions(String profile, int offset) =>
      get('/api/sessions/$profile', {'offset': '$offset'});
  Future<Map<String, dynamic>> transcript(
          String profile, String session, int offset) =>
      get('/api/sessions/$profile/$session', {'offset': '$offset'});
  Future<Map<String, dynamic>> chat(Map<String, dynamic> payload) =>
      post('/api/chat', payload);
  Future<void> onboard(String profile, String mode) async {
    await post('/api/onboarding', {'profile_id': profile, 'mode': mode});
  }

  Future<Map<String, dynamic>> journalSummary(String profile) =>
      get('/api/journal/$profile');
  Future<Map<String, dynamic>> journal(Map<String, dynamic> body) =>
      post('/api/journal', body);
  Future<Map<String, dynamic>> discuss(Map<String, dynamic> body) =>
      post('/api/journal/discuss', body);
  Future<void> deleteJournal(String profile, String entry) async {
    decode(await authorized(() => client
        .delete(uri('/api/journal/$entry', {'profile_id': profile}),
            headers: headers)
        .timeout(const Duration(seconds: 25))));
  }

  Future<String> transcribe(String profile, Uint8List bytes) async {
    final response = await authorized(() async {
      final request = http.MultipartRequest('POST', uri('/api/transcribe'))
        ..fields['profile_id'] = profile
        ..files.add(http.MultipartFile.fromBytes('file', bytes,
            filename: 'speech.wav', contentType: MediaType('audio', 'wav')));
      if (token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      return http.Response.fromStream(await client.send(request))
          .timeout(const Duration(seconds: 65));
    });
    return decode(response)['text'] as String? ?? '';
  }

  Future<Uint8List> speech(String profile, String session, String text) async {
    final payload = {
      'profile_id': profile,
      'session_id': session,
      'text': text
    };
    final response = await authorized(() => client
        .post(uri('/api/speech'), headers: headers, body: jsonEncode(payload))
        .timeout(const Duration(seconds: 65)));
    if (response.statusCode >= 400) {
      decode(response);
    }
    return response.bodyBytes;
  }

  void close() => client.close();
}
