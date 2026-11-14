import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'api.dart';
import 'ui_text.dart';

class JournalState extends ChangeNotifier {
  final TutorApi api;
  String get uiLanguage => api.interfaceLanguage?.call() ?? 'hu';
  String tr(String key) => UiText.get(uiLanguage, key);
  final String Function() profile;
  final bool demo;
  Map<String, dynamic>? data;
  Map<String, dynamic>? pendingJournal;
  Map<String, dynamic>? pendingDiscussion;
  final Map<String, List<Map<String, String>>> discussions = {};
  bool loading = false, writing = false, discussing = false;
  String? error, journalError, discussionError;
  int _epoch = 0;
  JournalState({required this.api, required this.profile, required this.demo});
  List<Map<String, dynamic>> get entries => (data?['journal'] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  void clear() {
    _epoch++;
    data = null;
    pendingJournal = null;
    pendingDiscussion = null;
    discussions.clear();
    loading = false;
    writing = false;
    discussing = false;
    error = null;
    journalError = null;
    discussionError = null;
    notifyListeners();
  }

  Future<void> load() async {
    if (loading || (!demo && profile().isEmpty)) {
      return;
    }
    final epoch = _epoch;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = demo
          ? demoJournal(language: uiLanguage)
          : await api.journalSummary(profile());
      if (epoch == _epoch) {
        data = result;
        final ids = entries.map((entry) => entry['id']).toSet();
        discussions.removeWhere((id, _) => !ids.contains(id));
        for (final entry in entries) {
          if (entry['discussion'] is List) {
            discussions[entry['id'] as String] = [
              for (final item in entry['discussion'] as List) ...[
                {'role': 'user', 'text': item['message'] as String? ?? ''},
                {'role': 'assistant', 'text': item['text'] as String? ?? ''}
              ]
            ];
          }
        }
      }
    } catch (e) {
      if (epoch == _epoch) {
        error = readable(e, uiLanguage);
      }
    } finally {
      if (epoch == _epoch) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> write(String text, {bool retry = false}) async {
    if (writing || (!retry && pendingJournal != null)) {
      return false;
    }
    if (!retry) {
      pendingJournal = {
        'profile_id': profile(),
        'request_id': const Uuid().v4(),
        'content': text
      };
    }
    if (pendingJournal == null) {
      return false;
    }
    final epoch = _epoch;
    writing = true;
    journalError = null;
    notifyListeners();
    try {
      if (demo) {
        throw ApiFailure(tr('demoJournal'));
      }
      final result =
          await api.journal(Map<String, dynamic>.from(pendingJournal!));
      if (epoch != _epoch) {
        return false;
      }
      pendingJournal = null;
      final existing = entries.where((e) => e['id'] != result['id']).toList();
      data ??= {};
      data!['journal'] = [result, ...existing];
      await load();
      return true;
    } catch (e) {
      if (epoch == _epoch) {
        journalError = readable(e, uiLanguage);
      }
      return false;
    } finally {
      if (epoch == _epoch) {
        writing = false;
        notifyListeners();
      }
    }
  }

  Future<bool> discuss(String entry, String message,
      {bool retry = false}) async {
    if (discussing || (!retry && pendingDiscussion != null)) {
      return false;
    }
    if (!retry) {
      pendingDiscussion = {
        'profile_id': profile(),
        'entry_id': entry,
        'request_id': const Uuid().v4(),
        'message': message
      };
    }
    if (pendingDiscussion == null) {
      return false;
    }
    final epoch = _epoch;
    discussing = true;
    discussionError = null;
    notifyListeners();
    try {
      if (demo) {
        throw ApiFailure(tr('demoDiscussion'));
      }
      final payload = Map<String, dynamic>.from(pendingDiscussion!);
      final result = await api.discuss(payload);
      if (epoch != _epoch) {
        return false;
      }
      discussions.putIfAbsent(payload['entry_id'] as String, () => []).addAll([
        {'role': 'user', 'text': payload['message'] as String},
        {'role': 'assistant', 'text': result['text'] as String? ?? ''}
      ]);
      pendingDiscussion = null;
      await load();
      return true;
    } catch (e) {
      if (epoch == _epoch) {
        discussionError = readable(e, uiLanguage);
      }
      return false;
    } finally {
      if (epoch == _epoch) {
        discussing = false;
        notifyListeners();
      }
    }
  }

  Future<bool> delete(String entry) async {
    if (writing || discussing || pendingDiscussion?['entry_id'] == entry) {
      error = tr('finishPendingQuestion');
      notifyListeners();
      return false;
    }
    final epoch = _epoch;
    try {
      if (!demo) {
        await api.deleteJournal(profile(), entry);
      }
      if (epoch != _epoch) {
        return false;
      }
      data?['journal'] = entries.where((e) => e['id'] != entry).toList();
      discussions.remove(entry);
      notifyListeners();
      return true;
    } catch (e) {
      if (epoch == _epoch) {
        error = readable(e, uiLanguage);
        notifyListeners();
      }
      return false;
    }
  }

  static String readable(Object error, [String locale = 'hu']) =>
      error is ApiFailure ? error.message : UiText.get(locale, 'networkError');
  @override
  void dispose() {
    _epoch++;
    super.dispose();
  }
}

Map<String, dynamic> demoJournal({String language = 'hu'}) => {
      'journal': [
        {
          'id': 'recorded-journal',
          'created_at': '2026-10-29T09:00:00Z',
          'content': 'Yesterday I go to the café and ordered a tea.',
          'feedback': {
            'text': 'Use “went” for a completed past event.',
            'corrections': [
              {
                'wrong_sentence': 'I go',
                'corrected_sentence': 'I went',
                'grammar_rule': 'Past simple'
              }
            ]
          },
          'discussion': [
            {
              'message': 'Why should I use went?',
              'text':
                  'Yesterday refers to a completed past event. The past form of go is went.'
            }
          ]
        }
      ]
    };
