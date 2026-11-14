import 'package:flutter/widgets.dart';
import 'ui_text_data.dart';

/// Fixed interface copy. User messages and course content keep their own language.
class UiText {
  static const codes = ['hu', 'en', 'ro', 'es', 'fr', 'de'];
  static const names = {
    'hu': 'Magyar',
    'en': 'English',
    'ro': 'Română',
    'es': 'Español',
    'fr': 'Français',
    'de': 'Deutsch'
  };
  static Set<String> get keys => uiTranslations['en']!.keys.toSet();

  /// Translate server messages we recognize; never translate learner content.
  /// Unrecognized backend errors use a safe localized category until the API
  /// exposes stable error codes. Hungarian retains its existing detailed copy.
  static String serverError(String locale, String? detail, int status) {
    if (locale == 'hu' && detail != null) return detail;
    if (detail != null) {
      for (final entry in uiTranslations['hu']!.entries) {
        if (entry.value == detail &&
            !entry.value.contains(RegExp(r'\{\w+\}'))) {
          return get(locale, entry.key);
        }
      }
    }
    final key = switch (status) {
      401 => 'sessionExpired',
      403 => 'accessDenied',
      404 => 'resourceNotFound',
      409 => 'sessionChanged',
      413 => 'requestTooLarge',
      429 => 'rateLimited',
      400 || 415 || 422 => 'invalidInput',
      502 => 'aiResponseFailed',
      >= 500 => 'serviceUnavailable',
      _ => 'requestFailed',
    };
    return get(locale, key);
  }

  static String get(String locale, String key,
      {Map<String, Object> params = const {}}) {
    final resource = uiTranslations[locale] ?? uiTranslations['en']!;
    final value = resource[key];
    if (value == null) {
      throw ArgumentError.value(key, 'key', 'Unknown UI message');
    }
    return value.replaceAllMapped(RegExp(r'\{(\w+)\}'), (match) {
      final name = match.group(1)!;
      if (!params.containsKey(name)) {
        throw ArgumentError('Missing placeholder $name for $key');
      }
      return params[name].toString();
    });
  }

  static String format(String locale, String key, Map<String, Object> params) =>
      get(locale, key, params: params);
  static String of(BuildContext context, String key,
          {Map<String, Object> params = const {}}) =>
      get(Localizations.localeOf(context).languageCode, key, params: params);
}
