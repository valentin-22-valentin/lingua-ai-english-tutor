import 'ui_text.dart';
import 'package:flutter/material.dart';
import 'app_controller.dart';
import 'screens.dart';
import 'theme_compat.dart';

class JournalScreen extends StatefulWidget {
  final AppController controller;
  const JournalScreen({super.key, required this.controller});
  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  late final TextEditingController composer;
  @override
  void initState() {
    super.initState();
    composer = TextEditingController(
        text: widget.controller.journal.pendingJournal?['content'] as String? ??
            '');
    if (widget.controller.journal.data == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.controller.journal.load();
      });
    }
  }

  @override
  void dispose() {
    composer.dispose();
    super.dispose();
  }

  Future<void> write({bool retry = false}) async {
    final text = composer.text.trim();
    if (!retry && text.isEmpty) {
      return;
    }
    if (await widget.controller.journal.write(text, retry: retry) && mounted) {
      composer.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.controller.journal, cs = Theme.of(context).colorScheme;
    if (p.loading && p.data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (p.error != null && p.data == null) {
      return StatusPane(
          icon: Icons.cloud_off_outlined,
          title: UiText.of(context, 'journalSafe'),
          message: p.error!,
          action: UiText.of(context, 'retry'),
          onAction: p.load);
    }
    return RefreshIndicator(
        onRefresh: p.load,
        child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(
                MediaQuery.sizeOf(context).width < 600 ? 22 : 38),
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 960),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (p.error != null)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: ErrorStrip(
                                    message: p.error!, retry: p.load)),
                          Text(UiText.of(context, 'journalLabel'),
                              style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 2.4,
                                  fontWeight: FontWeight.w600,
                                  color: cs.primary)),
                          const SizedBox(height: 14),
                          Text(UiText.of(context, 'journalTitle'),
                              style: MediaQuery.sizeOf(context).width < 600
                                  ? Theme.of(context).textTheme.headlineMedium
                                  : Theme.of(context).textTheme.displaySmall),
                          const SizedBox(height: 12),
                          Text(UiText.of(context, 'journalHelp'),
                              style: TextStyle(color: cs.onSurfaceVariant)),
                          const SizedBox(height: 28),
                          Row(children: [
                            Expanded(
                                child: Text(
                                    UiText.of(context, 'journalQuestion'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge)),
                            Icon(Icons.edit_note_rounded, color: cs.primary)
                          ]),
                          const SizedBox(height: 10),
                          TextField(
                              controller: composer,
                              enabled: !p.writing && p.pendingJournal == null,
                              minLines: 4,
                              maxLines: 8,
                              maxLength: 1200,
                              decoration: InputDecoration(
                                  hintText: UiText.get(
                                      widget.controller.targetLanguage,
                                      'journalHint'),
                                  contentPadding: const EdgeInsets.all(20))),
                          const SizedBox(height: 10),
                          Wrap(
                              spacing: 16,
                              runSpacing: 12,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                FilledButton.icon(
                                    onPressed:
                                        p.writing || p.pendingJournal != null
                                            ? null
                                            : write,
                                    icon: p.writing
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2))
                                        : const Icon(
                                            Icons.arrow_forward_rounded,
                                            size: 18),
                                    label: Text(p.writing
                                        ? UiText.of(context, 'journalReading')
                                        : UiText.of(
                                            context, 'journalFeedback'))),
                                Text(UiText.of(context, 'journalPrivacyCredit'),
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: cs.onSurfaceVariant))
                              ]),
                          const SizedBox(height: 14),
                          Text(UiText.of(context, 'journalScope'),
                              style: TextStyle(
                                  fontSize: 12, color: cs.onSurfaceVariant)),
                          if (p.journalError != null)
                            Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: ErrorStrip(
                                    message: p.journalError!,
                                    retry: () => write(retry: true))),
                          const SizedBox(height: 36),
                          const Divider(),
                          const SizedBox(height: 20),
                          Text(UiText.of(context, 'journalHistory'),
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 18),
                          if (p.entries.isEmpty)
                            Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 35, horizontal: 24),
                                decoration: BoxDecoration(
                                    border:
                                        Border.all(color: cs.outlineVariant),
                                    borderRadius: BorderRadius.circular(16)),
                                child: Column(children: [
                                  Icon(Icons.menu_book_outlined,
                                      size: 29, color: cs.primary),
                                  const SizedBox(height: 14),
                                  Text(UiText.of(context, 'journalEmpty')),
                                  const SizedBox(height: 7),
                                  Text(UiText.of(context, 'journalEmptyHelp'),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: cs.onSurfaceVariant))
                                ]))
                          else
                            for (final entry in p.entries)
                              JournalTile(
                                  entry: entry, controller: widget.controller),
                          const SizedBox(height: 36),
                          const SizedBox(height: 30),
                        ])))));
  }
}

class JournalTile extends StatelessWidget {
  final Map<String, dynamic> entry;
  final AppController controller;
  const JournalTile({super.key, required this.entry, required this.controller});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) => JournalDetail(
                            controller: controller, entry: entry))),
                child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(
                                entryDate(entry['created_at'] as String?,
                                    context: context),
                                style: TextStyle(
                                    fontSize: 10,
                                    letterSpacing: .7,
                                    color: cs.primary)),
                            const SizedBox(height: 8),
                            Text(entry['content'] as String? ?? '',
                                maxLines: 3, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 10),
                            Text(UiText.of(context, 'viewFeedback'),
                                style: TextStyle(
                                    fontSize: 11, color: cs.onSurfaceVariant))
                          ])),
                      const SizedBox(width: 16),
                      const Icon(Icons.arrow_forward_rounded, size: 19)
                    ])))));
  }
}

String entryDate(String? source, {BuildContext? context}) {
  final date = DateTime.tryParse(source ?? '')?.toLocal();
  return date == null
      ? UiText.get(
          context == null ? 'hu' : Localizations.localeOf(context).languageCode,
          'journalEntry')
      : context != null
          ? MaterialLocalizations.of(context).formatMediumDate(date)
          : '${date.year}. ${date.month.toString().padLeft(2, '0')}. ${date.day.toString().padLeft(2, '0')}.';
}

class JournalDetail extends StatefulWidget {
  final AppController controller;
  final Map<String, dynamic> entry;
  const JournalDetail(
      {super.key, required this.controller, required this.entry});
  @override
  State<JournalDetail> createState() => _JournalDetailState();
}

class _JournalDetailState extends State<JournalDetail> {
  final question = TextEditingController();
  bool deleting = false;
  String get id => widget.entry['id'] as String;
  @override
  void initState() {
    super.initState();
    if (widget.controller.journal.pendingDiscussion?['entry_id'] == id) {
      question.text =
          widget.controller.journal.pendingDiscussion?['message'] as String? ??
              '';
    }
    widget.controller.addListener(changed);
  }

  void changed() {
    if (!mounted) {
      return;
    }
    if (!widget.controller.configured) {
      Navigator.popUntil(context, (route) => route.isFirst);
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(changed);
    question.dispose();
    super.dispose();
  }

  Future<void> ask({bool retry = false}) async {
    final text = question.text.trim();
    if (!retry && text.isEmpty) {
      return;
    }
    if (await widget.controller.journal.discuss(id, text, retry: retry) &&
        mounted) {
      question.clear();
    }
  }

  Future<void> remove() async {
    final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(UiText.of(context, 'journalDeleteTitle')),
                content: Text(UiText.of(context, 'journalDeleteHelp')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(UiText.of(context, 'cancel'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(UiText.of(context, 'delete')))
                ]));
    if (confirm != true || !mounted) {
      return;
    }
    setState(() => deleting = true);
    final result = await widget.controller.journal.delete(id);
    if (!mounted) {
      return;
    }
    if (result) {
      Navigator.pop(context);
    } else {
      setState(() => deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.controller.journal, cs = Theme.of(context).colorScheme;
    final feedback = Map<String, dynamic>.from(widget.entry['feedback'] ?? {});
    final corrections = feedback['corrections'] as List? ?? [];
    return Scaffold(
        appBar:
            AppBar(title: Text(UiText.of(context, 'yourJournal')), actions: [
          IconButton(
              onPressed: deleting || p.discussing ? null : remove,
              tooltip: UiText.of(context, 'deleteEntry'),
              icon: const Icon(Icons.delete_outline_rounded))
        ]),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 740),
                child: SingleChildScrollView(
                    padding: const EdgeInsets.all(26),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              entryDate(widget.entry['created_at'] as String?,
                                  context: context),
                              style:
                                  TextStyle(fontSize: 11, color: cs.primary)),
                          const SizedBox(height: 15),
                          SelectableText(
                              widget.entry['content'] as String? ?? '',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(height: 1.7)),
                          const SizedBox(height: 28),
                          const Divider(),
                          const SizedBox(height: 25),
                          Text(UiText.of(context, 'smallCorrection'),
                              style:
                                  Theme.of(context).textTheme.headlineMedium),
                          const SizedBox(height: 14),
                          SelectableText(feedback['text'] as String? ??
                              UiText.of(context, 'noFeedback')),
                          for (final raw in corrections.take(1)) ...[
                            const SizedBox(height: 20),
                            Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(21),
                                decoration: BoxDecoration(
                                    color: cs.surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(16)),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(UiText.of(context, 'yourOriginal'),
                                          style: TextStyle(
                                              fontSize: 9,
                                              letterSpacing: 1.6,
                                              color: cs.onSurfaceVariant)),
                                      const SizedBox(height: 9),
                                      SelectableText(
                                          raw['wrong_sentence'] as String? ??
                                              '',
                                          style:
                                              TextStyle(color: cs.secondary)),
                                      const SizedBox(height: 20),
                                      Text(UiText.of(context, 'moreNatural'),
                                          style: TextStyle(
                                              fontSize: 9,
                                              letterSpacing: 1.6,
                                              color: cs.primary)),
                                      const SizedBox(height: 9),
                                      SelectableText(
                                          raw['corrected_sentence']
                                                  as String? ??
                                              '',
                                          style: TextStyle(
                                              color: cs.primary,
                                              fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 14),
                                      SelectableText(
                                          raw['grammar_rule'] as String? ?? '',
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: cs.onSurfaceVariant))
                                    ]))
                          ],
                          const SizedBox(height: 32),
                          Text(UiText.of(context, 'letsDiscuss'),
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 9),
                          Text(UiText.of(context, 'discussionHelp'),
                              style: TextStyle(
                                  fontSize: 12, color: cs.onSurfaceVariant)),
                          const SizedBox(height: 20),
                          for (final item
                              in p.discussions[id] ?? <Map<String, String>>[])
                            Padding(
                                padding: const EdgeInsets.only(bottom: 18),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          item['role'] == 'user'
                                              ? UiText.of(context, 'youLabel')
                                              : 'LINGUA',
                                          style: TextStyle(
                                              fontSize: 9,
                                              letterSpacing: 1.7,
                                              color: cs.primary)),
                                      const SizedBox(height: 6),
                                      SelectableText(item['text']!)
                                    ])),
                          if (p.pendingDiscussion != null &&
                              p.pendingDiscussion?['entry_id'] != id)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Text(
                                    UiText.of(
                                        context, 'otherDiscussionPending'),
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: cs.onSurfaceVariant))),
                          TextField(
                              controller: question,
                              enabled:
                                  !p.discussing && p.pendingDiscussion == null,
                              minLines: 2,
                              maxLines: 4,
                              maxLength: 600,
                              decoration: InputDecoration(
                                  hintText:
                                      UiText.of(context, 'discussionHint'))),
                          const SizedBox(height: 12),
                          FilledButton(
                              onPressed:
                                  p.discussing || p.pendingDiscussion != null
                                      ? null
                                      : ask,
                              child: Text(p.discussing
                                  ? UiText.of(context, 'discussionAnswering')
                                  : UiText.of(context, 'askQuestion'))),
                          if (p.discussionError != null &&
                              p.pendingDiscussion?['entry_id'] == id)
                            Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: ErrorStrip(
                                    message: p.discussionError!,
                                    retry: () => ask(retry: true))),
                          if (p.error != null)
                            Padding(
                                padding: const EdgeInsets.only(top: 15),
                                child: Text(p.error!,
                                    style: TextStyle(color: cs.error))),
                        ])))));
  }
}
