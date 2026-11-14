import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'api.dart';
import 'demo_tutor.dart';
import 'models.dart';
import 'journal_state.dart';
import 'ui_text.dart';

class AppController extends ChangeNotifier {
  final TutorApi api;
  String profileId;
  final bool demo;
  final DemoTutor _demoTutor = DemoTutor();
  String? get demoAnswer => _demoTutor.sample;
  late final JournalState journal;
  String? refreshToken, authError, authNotice;
  DateTime? tokenExpires;
  bool authenticating = false;
  int _authEpoch = 0;
  int _languageSaveId = 0;
  int contentGeneration = 0;
  String appLanguage = 'hu';
  bool _hasInterfacePreference = false;
  int _interfaceRevision = 0;
  String? _pendingInterfacePreference;
  String? languageError;
  bool languagesSaving = false, audioActive = false;
  bool languageDraftDirty = false;
  String _native = 'hu';
  String get nativeLanguage => dashboard?.nativeLanguage ?? _native;
  String get targetLanguage => 'en';
  String tr(String key) => UiText.get(appLanguage, key);
  bool get languageBusy =>
      languagesSaving ||
      chatting ||
      audioActive ||
      authenticating ||
      onboarding ||
      loading ||
      journal.writing ||
      journal.discussing ||
      pending != null ||
      journal.pendingJournal != null ||
      journal.pendingDiscussion != null;
  void setAudioActive(bool value) {
    if (audioActive == value) return;
    audioActive = value;
    notifyListeners();
  }

  Future<void> setInterfaceLanguage(String value) async {
    if (!UiText.codes.contains(value)) return;
    _hasInterfacePreference = true;
    _interfaceRevision++;
    appLanguage = value;
    authError = null;
    authNotice = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_language', value);
  }

  // The historic native_language field stores the preferred explanation language.
  Future<bool> updateLanguages(String explanation, String ui) async {
    if (languageBusy || !configured) return false;
    if (!UiText.codes.contains(explanation) || !UiText.codes.contains(ui)) {
      languageError = tr('invalidInput');
      notifyListeners();
      return false;
    }
    if (explanation == nativeLanguage && ui == appLanguage) return true;
    final epoch = _authEpoch;
    final operation = ++_languageSaveId;
    final profile = profileId;
    bool current() =>
        !_disposed &&
        epoch == _authEpoch &&
        operation == _languageSaveId &&
        profile == profileId;
    languagesSaving = true;
    languageError = null;
    notifyListeners();
    try {
      if (!demo) {
        await api.saveLanguages({
          'profile_id': profile,
          'native_language': explanation,
          'app_language': ui,
        });
      }
      if (!current()) return false;
      _hasInterfacePreference = true;
      _interfaceRevision++;
      _pendingInterfacePreference = null;
      _native = explanation;
      appLanguage = ui;
      languageDraftDirty = false;
      // Preferences do not change the English course, session, task or progress.
      final previous = dashboard;
      if (previous != null) {
        dashboard = Dashboard(
          username: previous.username,
          currentLevel: previous.currentLevel,
          levels: previous.levels,
          completed: previous.completed,
          nextLesson: previous.nextLesson,
          nativeLanguage: explanation,
          targetLanguage: 'en',
          appLanguage: ui,
        );
      }
      final prefs = await SharedPreferences.getInstance();
      if (!current()) return false;
      await prefs.setString('app_language', ui);
      return current();
    } catch (e) {
      if (current()) languageError = JournalState.readable(e, appLanguage);
      return false;
    } finally {
      if (current()) {
        languagesSaving = false;
        notifyListeners();
      }
    }
  }

  Future<void>? _refreshing;
  ThemeMode theme = ThemeMode.system;
  Dashboard? dashboard;
  bool loading = false, chatting = false, onboarding = false;
  String? error, chatError, sessionId, selectedLevel;
  int? practiceCompleted;
  int? activeLessonId;
  String? completion;
  int tab = 0;
  final List<ChatMessage> messages = [];
  Map<String, dynamic>? pending;
  bool _disposed = false;
  AppController({TutorApi? api, String? profileId, bool? demo})
      : api = api ?? TutorApi(),
        profileId = profileId ?? const String.fromEnvironment('PROFILE_ID'),
        demo = demo ?? const bool.fromEnvironment('DEMO_MODE') {
    journal = JournalState(
        api: this.api, profile: () => this.profileId, demo: this.demo);
    this.api.interfaceLanguage = () => appLanguage;
    journal.addListener(journalChanged);
    this.api.prepareAuthorization = prepareAuth;
    this.api.refreshAuthorization = refreshAuth;
    this.api.sessionExpired = () => logout(expired: true);
  }
  bool get configured => demo || profileId.isNotEmpty;
  void journalChanged() {
    notifyListeners();
  }

  Future<void> authenticate(String email, String password,
      {String? username}) async {
    if (authenticating) {
      return;
    }
    final epoch = ++_authEpoch;
    authenticating = true;
    authError = null;
    authNotice = null;
    notifyListeners();
    try {
      final result = await api.auth(username == null ? 'login' : 'register', {
        'email': email.trim(),
        'password': password,
        if (username != null) 'username': username.trim()
      });
      if (epoch != _authEpoch) {
        return;
      }
      if (result['confirmation_required'] == true) {
        authNotice = tr('authConfirmation');
        return;
      }
      _acceptAuth(result);
      // A choice made on the sign-in screen is intentional. Persist only that
      // preference; do not overwrite native language, target course or progress.
      _pendingInterfacePreference =
          _hasInterfacePreference ? appLanguage : null;
      await refresh();
      if (epoch != _authEpoch) return;
      await journal.load();
    } catch (e) {
      if (epoch == _authEpoch) {
        authError = JournalState.readable(e, appLanguage);
      }
    } finally {
      if (epoch == _authEpoch) {
        authenticating = false;
        notifyListeners();
      }
    }
  }

  void _acceptAuth(Map<String, dynamic> result, {bool refreshing = false}) {
    if (!refreshing) {
      api.sessionGeneration++;
    }
    profileId = result['profile_id'] as String;
    api.token = result['access_token'] as String;
    refreshToken = result['refresh_token'] as String?;
    tokenExpires = DateTime.now()
        .add(Duration(seconds: (result['expires_in'] as num? ?? 3600).toInt()));
  }

  Future<void> _syncInterfacePreference(int epoch) async {
    final preferred = _pendingInterfacePreference;
    if (preferred == null || demo) return;
    try {
      await api.post('/api/profile/interface-language', {
        'profile_id': profileId,
        'app_language': preferred,
      });
      if (epoch != _authEpoch || _disposed) return;
      if (_pendingInterfacePreference == preferred) {
        _pendingInterfacePreference = null;
      }
      languageError = null;
    } catch (_) {
      if (epoch != _authEpoch || _disposed) return;
      // Keep the explicitly selected local language even when persistence fails.
      // A later refresh retries this preference instead of reverting to Hungarian.
      languageError = tr('interfaceSaveError');
    }
  }

  Future<void> prepareAuth() async {
    if (refreshToken != null &&
        tokenExpires != null &&
        DateTime.now()
            .isAfter(tokenExpires!.subtract(const Duration(seconds: 30)))) {
      await refreshAuth();
    }
  }

  Future<void> refreshAuth() async {
    if (_refreshing != null) {
      return _refreshing!;
    }
    if (refreshToken == null) {
      throw ApiFailure(tr('sessionExpired'), 401);
    }
    final epoch = _authEpoch;
    final token = refreshToken!;
    final future = () async {
      try {
        final result = await api.auth('refresh', {'refresh_token': token});
        if (epoch != _authEpoch) {
          throw ApiFailure(tr('sessionChanged'), 401);
        }
        _acceptAuth(result, refreshing: true);
      } catch (_) {
        if (epoch == _authEpoch) {
          logout(expired: true);
        }
        rethrow;
      }
    }();
    _refreshing = future;
    try {
      await future;
    } finally {
      if (_refreshing == future) {
        _refreshing = null;
      }
    }
  }

  void logout({bool expired = false}) {
    _pendingInterfacePreference = null;
    _authEpoch++;
    _languageSaveId++;
    contentGeneration++;
    languagesSaving = false;
    languageDraftDirty = false;
    _native = 'hu';
    api.sessionGeneration++;
    profileId = '';
    api.token = '';
    refreshToken = null;
    tokenExpires = null;
    dashboard = null;
    selectedLevel = null;
    messages.clear();
    pending = null;
    sessionId = null;
    activeLessonId = null;
    practiceCompleted = null;
    completion = null;
    error = null;
    chatError = null;
    loading = false;
    chatting = false;
    onboarding = false;
    authenticating = false;
    tab = 0;
    journal.clear();
    authError = expired ? tr('sessionExpired') : null;
    authNotice = null;
    notifyListeners();
  }

  CourseLevel? get level {
    final levels = dashboard?.levels ?? [];
    for (final level in levels) {
      if (level.level == selectedLevel) {
        return level;
      }
    }
    return levels.isEmpty ? null : levels.first;
  }

  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  Future<void> initialize() async {
    final revision = _interfaceRevision;
    final prefs = await SharedPreferences.getInstance();
    if (revision == _interfaceRevision) {
      final stored = prefs.getString('app_language');
      _hasInterfacePreference = UiText.codes.contains(stored);
      appLanguage = _hasInterfacePreference
          ? stored!
          : demo
              ? 'en'
              : 'hu';
    }
    theme = ThemeMode.values.firstWhere(
        (e) => e.name == prefs.getString('theme'),
        orElse: () => ThemeMode.system);
    notifyListeners();
    if (configured) {
      _pendingInterfacePreference =
          !demo && _hasInterfacePreference ? appLanguage : null;
      await refresh();
      await journal.load();
    }
  }

  Future<void> setTheme(ThemeMode value) async {
    theme = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme', value.name);
  }

  void navigate(int value) {
    if (![0, 1, 3, 4, 5].contains(value)) return;
    tab = value;
    notifyListeners();
  }

  void selectLevel(String value) {
    selectedLevel = value;
    tab = 0;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (loading) {
      return;
    }
    loading = true;
    final epoch = _authEpoch;
    final interfaceRevision = _interfaceRevision;
    error = null;
    notifyListeners();
    try {
      if (_pendingInterfacePreference != null) {
        await _syncInterfacePreference(epoch);
        if (epoch != _authEpoch) return;
      }
      final previousLevel = dashboard?.currentLevel;
      final result = demo
          ? demoDashboard(
              native: _native, ui: appLanguage, completed: _demoTutor.completed)
          : Dashboard.fromJson(await api.dashboard(profileId));
      if (epoch != _authEpoch) {
        return;
      }
      if (result.targetLanguage != 'en') {
        throw ApiFailure(tr('englishOnly'), 409);
      }
      dashboard = result;
      if (_pendingInterfacePreference == null &&
          interfaceRevision == _interfaceRevision) {
        appLanguage = result.appLanguage;
      }
      _native = result.nativeLanguage;
      if (selectedLevel == null || previousLevel != dashboard!.currentLevel) {
        selectedLevel = dashboard!.currentLevel;
      }
    } catch (e) {
      if (epoch != _authEpoch) {
        return;
      }
      error = e is ApiFailure ? e.message : tr('networkError');
    } finally {
      if (epoch == _authEpoch) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> onboard(String mode) async {
    if (onboarding ||
        chatting ||
        languagesSaving ||
        audioActive ||
        languageDraftDirty) {
      return;
    }
    onboarding = true;
    final epoch = _authEpoch;
    error = null;
    notifyListeners();
    try {
      if (!demo) {
        await api.onboard(profileId, mode);
      }
      if (epoch != _authEpoch || _disposed) return;
      _resetChat();
      contentGeneration++;
      selectedLevel = null;
      await refresh();
      if (mode == 'placement') {
        await startChat();
      }
    } catch (e) {
      if (epoch != _authEpoch || _disposed) return;
      error = e is ApiFailure ? e.message : tr('startFailed');
    } finally {
      if (epoch == _authEpoch) {
        onboarding = false;
        notifyListeners();
      }
    }
  }

  Future<void> startChat() async {
    if (chatting) return;
    final nextId = dashboard?.nextLesson?['id'];
    if (activeLessonId != null && nextId != null && activeLessonId != nextId) {
      _resetChat();
    }
    if (completion != null && !chatting && pending == null) {
      messages.clear();
      sessionId = null;
      practiceCompleted = null;
      completion = null;
    }
    tab = 1;
    notifyListeners();
    if (messages.isEmpty && !chatting) {
      await send(null);
    }
  }

  Future<void> send(String? text, {bool retry = false}) async {
    if (chatting || languagesSaving || !configured) {
      return;
    }
    if (pending != null && !retry) {
      return;
    }
    if (!retry) {
      pending = {
        'profile_id': profileId,
        'request_id': const Uuid().v4(),
        'message': text,
        if (sessionId != null) 'session_id': sessionId
      };
      if (text != null) {
        messages.add(ChatMessage(text, user: true));
      }
    }
    if (pending == null) {
      return;
    }
    chatting = true;
    final epoch = _authEpoch;
    chatError = null;
    notifyListeners();
    try {
      final result = demo
          ? _demoTutor.reply(pending!['message'] as String?)
          : await api.chat(Map<String, dynamic>.from(pending!));
      if (epoch != _authEpoch) {
        return;
      }
      sessionId = result['session_id'] as String?;
      activeLessonId = (result['lesson_id'] as num?)?.toInt();
      practiceCompleted = (result['practice_completed'] as num?)?.toInt();
      if (result['resumed'] == true && result['messages'] is List) {
        messages
          ..clear()
          ..addAll((result['messages'] as List).map((m) =>
              ChatMessage(m['content'] as String, user: m['role'] == 'user')));
      } else {
        messages.add(ChatMessage(result['text'] as String? ?? ''));
      }
      pending = null;
      if (demo) await refresh();
      if (result['lesson_complete'] == true) {
        completion = result['passed'] == true && practiceCompleted == 8
            ? tr('practiceMastered')
            : result['passed'] == true
                ? UiText.format(appLanguage, 'lessonPassed',
                    {'score': result['score'] ?? '–'})
                : UiText.format(appLanguage, 'lessonRetry',
                    {'score': result['score'] ?? '–'});
        await refresh();
      }
    } catch (e) {
      if (epoch != _authEpoch) {
        return;
      }
      chatError = e is ApiFailure ? e.message : tr('chatFailed');
    } finally {
      if (epoch == _authEpoch) {
        chatting = false;
        notifyListeners();
      }
    }
  }

  Future<void> nextChat() async {
    if (chatting || pending != null) {
      return;
    }
    messages.clear();
    sessionId = null;
    completion = null;
    practiceCompleted = null;
    await startChat();
  }

  void _resetChat() {
    messages.clear();
    sessionId = null;
    activeLessonId = null;
    completion = null;
    practiceCompleted = null;
    pending = null;
    chatError = null;
  }

  Future<void> reloadSavedChat() async {
    if (chatting || audioActive) return;
    _resetChat();
    await startChat();
  }

  @override
  void dispose() {
    _disposed = true;
    _authEpoch++;
    journal.removeListener(journalChanged);
    journal.dispose();
    api.close();
    super.dispose();
  }
}

Dashboard demoDashboard(
        {String native = 'hu', String ui = 'hu', int completed = 0}) =>
    Dashboard(
      nativeLanguage: native,
      targetLanguage: 'en',
      appLanguage: ui,
      username: 'Alex',
      currentLevel: 'A1',
      completed: completed,
      nextLesson: completed < 3
          ? {
              'id': completed + 1,
              'title': UiText.get(
                  ui,
                  [
                    'demoLessonIntro',
                    'demoLessonCafe',
                    'demoLessonCity'
                  ][completed])
            }
          : null,
      levels: [
        CourseLevel(
            level: 'A1',
            title: UiText.get(ui, 'demoLevelA1'),
            status: 'current',
            lessons: List.generate(
                3,
                (i) => Lesson(
                    id: i + 1,
                    title: UiText.get(
                        ui,
                        [
                          'demoLessonIntro',
                          'demoLessonCafe',
                          'demoLessonCity'
                        ][i]),
                    status: i < completed
                        ? 'completed'
                        : i == completed
                            ? 'available'
                            : 'locked')))
      ],
    );
