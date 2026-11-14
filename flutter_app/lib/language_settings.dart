import 'package:flutter/material.dart';
import 'app_controller.dart';
import 'ui_text.dart';

/// Two independent preferences. The taught language is always English.
class LanguageSettings extends StatefulWidget {
  final AppController controller;
  const LanguageSettings({super.key, required this.controller});
  @override
  State<LanguageSettings> createState() => _LanguageSettingsState();
}

class _LanguageSettingsState extends State<LanguageSettings> {
  late String explanation, ui;
  String? notice;
  @override
  void initState() {
    super.initState();
    explanation = widget.controller.nativeLanguage;
    ui = widget.controller.appLanguage;
  }

  void changed() {
    final c = widget.controller;
    c.languageDraftDirty =
        explanation != c.nativeLanguage || ui != c.appLanguage;
    notice = null;
    c.notifyListeners();
  }

  @override
  void dispose() {
    widget.controller.languageDraftDirty = false;
    super.dispose();
  }

  Future<void> save() async {
    final c = widget.controller;
    final profile = c.profileId;
    final success = await c.updateLanguages(explanation, ui);
    if (mounted && profile == c.profileId && success) {
      setState(() => notice = c.tr('saved'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final dirty = explanation != c.nativeLanguage || ui != c.appLanguage;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c.tr('learningEnglish'),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Text(c.tr('explanationHelp'),
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            key: ValueKey('explanation-$explanation'),
            value: explanation,
            isExpanded: true,
            decoration: InputDecoration(labelText: c.tr('explanationLanguage')),
            items: [
              for (final code in UiText.codes)
                DropdownMenuItem(value: code, child: Text(UiText.names[code]!))
            ],
            onChanged: c.languageBusy
                ? null
                : (value) => setState(() {
                      explanation = value!;
                      changed();
                    }),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            key: ValueKey('interface-$ui'),
            value: ui,
            isExpanded: true,
            decoration: InputDecoration(labelText: c.tr('interface')),
            items: [
              for (final code in UiText.codes)
                DropdownMenuItem(value: code, child: Text(UiText.names[code]!))
            ],
            onChanged: c.languageBusy
                ? null
                : (value) => setState(() {
                      ui = value!;
                      changed();
                    }),
          ),
          const SizedBox(height: 12),
          Text(c.tr('englishPreferencesNote'),
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          if (c.languageError != null) ...[
            const SizedBox(height: 12),
            Text(c.languageError!, style: TextStyle(color: cs.error)),
          ],
          if (notice != null) ...[
            const SizedBox(height: 12),
            Text(notice!, style: TextStyle(color: cs.primary)),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: !dirty || c.languageBusy ? null : save,
            icon: c.languagesSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check_rounded, size: 18),
            label: Text(c.tr('save')),
          ),
          if (c.languageBusy && !c.languagesSaving) ...[
            const SizedBox(height: 8),
            Text(c.tr('busy'), style: const TextStyle(fontSize: 12)),
          ],
        ]);
      },
    );
  }
}
