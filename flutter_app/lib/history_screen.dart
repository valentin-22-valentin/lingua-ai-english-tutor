import 'package:flutter/material.dart';
import 'app_controller.dart';
import 'journal_state.dart';

/// Read-only history. Opening an old session never sends an AI request or resumes it.
class HistoryScreen extends StatefulWidget {
  final AppController controller;
  const HistoryScreen({super.key, required this.controller});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final sessions = <Map<String, dynamic>>[];
  final messages = <Map<String, dynamic>>[];
  Map<String, dynamic>? selected;
  bool loading = false, moreSessions = false, moreMessages = false;
  String? error;
  int operation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) load();
    });
  }

  Future<void> load({bool more = false}) async {
    final c = widget.controller;
    final profile = c.profileId;
    final request = ++operation;
    final session = selected?['id'] as String?;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final offset =
          more ? (session == null ? sessions.length : messages.length) : 0;
      final result = c.demo
          ? <String, dynamic>{'sessions': [], 'has_more': false}
          : session == null
              ? await c.api.sessions(profile, offset)
              : await c.api.transcript(profile, session, offset);
      if (!mounted || request != operation || profile != c.profileId) return;
      setState(() {
        final target = session == null ? sessions : messages;
        if (!more) target.clear();
        target.addAll(
            (result[session == null ? 'sessions' : 'messages'] as List? ?? [])
                .map((row) => Map<String, dynamic>.from(row)));
        if (session == null) {
          moreSessions = result['has_more'] == true;
        } else {
          moreMessages = result['has_more'] == true;
        }
      });
    } catch (e) {
      if (mounted && request == operation && profile == c.profileId) {
        setState(() => error = JournalState.readable(e, c.appLanguage));
      }
    } finally {
      if (mounted && request == operation) setState(() => loading = false);
    }
  }

  String date(String? value) {
    final parsed = DateTime.tryParse(value ?? '')?.toLocal();
    if (parsed == null) return '';
    final labels = MaterialLocalizations.of(context);
    return '${labels.formatMediumDate(parsed)} · ${labels.formatTimeOfDay(TimeOfDay.fromDateTime(parsed))}';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final colors = Theme.of(context).colorScheme;
    return Center(
        child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 860),
      child: ListView(padding: const EdgeInsets.all(24), children: [
        Row(children: [
          if (selected != null)
            IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                      operation++;
                      selected = null;
                      loading = false;
                      error = null;
                    })),
          Expanded(
              child: Text(selected?['title'] as String? ?? c.tr('historyTitle'),
                  style: Theme.of(context).textTheme.headlineSmall)),
          IconButton(
              tooltip: c.tr('retry'),
              onPressed: loading ? null : () => load(),
              icon: const Icon(Icons.refresh)),
        ]),
        const SizedBox(height: 12),
        Text(c.tr(selected == null ? 'historyHelp' : 'historyReadOnly')),
        const SizedBox(height: 24),
        if (selected == null && sessions.isEmpty && !loading && error == null)
          Text(c.tr(c.demo ? 'historyDemo' : 'historyEmpty')),
        if (selected == null)
          ...sessions.map((row) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.chat_bubble_outline),
                title: Text(row['title'] as String? ?? 'English practice'),
                subtitle: Text(
                    '${date(row['started_at'] as String?)}\n${c.tr(row['status'] == 'active' ? 'historyActive' : 'historyClosed')}'),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: loading
                    ? null
                    : () {
                        setState(() {
                          selected = row;
                          messages.clear();
                          moreMessages = false;
                        });
                        load();
                      },
              )),
        if (selected != null)
          ...messages.map((message) => Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: colors.surfaceVariant,
                    borderRadius: BorderRadius.circular(12)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          c.tr(
                              message['role'] == 'user' ? 'youLabel' : 'tutor'),
                          style: TextStyle(
                              color: colors.primary,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      SelectableText(message['content'] as String? ?? ''),
                    ]),
              )),
        if (error != null) ...[
          Text(error!, style: TextStyle(color: colors.error)),
          TextButton(
              onPressed: loading ? null : () => load(more: true),
              child: Text(c.tr('retry'))),
        ],
        if (loading) const Center(child: CircularProgressIndicator()),
        if (!loading && (selected == null ? moreSessions : moreMessages))
          OutlinedButton(
              onPressed: () => load(more: true),
              child: Text(c.tr('historyMore'))),
      ]),
    ));
  }
}
