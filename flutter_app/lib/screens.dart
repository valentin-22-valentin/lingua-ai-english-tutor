import 'package:flutter/material.dart';
import 'app_controller.dart';
import 'models.dart';
import 'theme_compat.dart';
import 'chat_screen.dart';
import 'auth_screen.dart';
import 'journal_screen.dart';
import 'language_settings.dart';
import 'ui_text.dart';
import 'history_screen.dart';

class AppShell extends StatelessWidget {
  final AppController controller;
  const AppShell({super.key, required this.controller});
  @override
  Widget build(BuildContext context) {
    if (!controller.configured) {
      return AuthScreen(controller: controller);
    }
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      drawer: wide
          ? null
          : Drawer(
              child: SafeArea(
                  child: Sidebar(controller: controller, drawer: true))),
      appBar: wide
          ? null
          : AppBar(
              title: const Brand(compact: true),
              centerTitle: false,
              actions: [
                  if (controller.demo)
                    const Padding(
                        padding: EdgeInsets.only(right: 8), child: DemoBadge())
                ]),
      body: Row(children: [
        if (wide) SizedBox(width: 252, child: Sidebar(controller: controller)),
        Expanded(
            child: Column(children: [
          if (wide)
            Container(
                height: 78,
                padding: const EdgeInsets.symmetric(horizontal: 38),
                decoration: BoxDecoration(
                    border:
                        Border(bottom: BorderSide(color: cs.outlineVariant))),
                child: Row(children: [
                  Text(
                      [
                        controller.tr('path'),
                        controller.tr('chat'),
                        '',
                        controller.tr('settings'),
                        controller.tr('journal'),
                        controller.tr('historyTitle')
                      ][controller.tab],
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  if (controller.demo) const DemoBadge(),
                  const SizedBox(width: 18),
                  Icon(Icons.language_rounded,
                      size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(
                      UiText.names[controller.targetLanguage] ??
                          controller.targetLanguage,
                      style: TextStyle(color: cs.onSurfaceVariant)),
                  const SizedBox(width: 24),
                  CircleAvatar(
                      radius: 18,
                      backgroundColor: cs.surfaceContainerHighest,
                      child: Text(avatarInitial(controller.dashboard?.username),
                          style: TextStyle(color: cs.primary, fontSize: 14)))
                ])),
          Expanded(
              child: AnimatedSwitcher(
                  duration: MediaQuery.of(context).disableAnimations
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  child: KeyedSubtree(
                      key: ValueKey(
                          '${controller.profileId}:${controller.contentGeneration}:${controller.tab}'),
                      child: _content()))),
        ]))
      ]),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: controller.tab == 0
                  ? 0
                  : controller.tab == 1
                      ? 1
                      : 2,
              onDestinationSelected: (index) =>
                  controller.navigate([0, 1, 3][index]),
              labelBehavior: MediaQuery.sizeOf(context).width < 380
                  ? NavigationDestinationLabelBehavior.onlyShowSelected
                  : NavigationDestinationLabelBehavior.alwaysShow,
              backgroundColor: cs.surface,
              destinations: [
                  NavigationDestination(
                      icon: const Icon(Icons.route_outlined),
                      selectedIcon: const Icon(Icons.route),
                      label: controller.tr('navLearn')),
                  NavigationDestination(
                      icon: const Icon(Icons.chat_bubble_outline_rounded),
                      selectedIcon: const Icon(Icons.chat_bubble_rounded),
                      label: controller.tr('navChat')),
                  NavigationDestination(
                      icon: const Icon(Icons.tune_rounded),
                      label: controller.tr('navProfile'))
                ]),
    );
  }

  Widget _content() => switch (controller.tab) {
        1 => ChatScreen(controller: controller),
        3 => SettingsScreen(controller: controller),
        4 => JournalScreen(controller: controller),
        5 => HistoryScreen(controller: controller),
        _ => PathScreen(controller: controller)
      };
}

String avatarInitial(String? username) {
  final name = username?.trim() ?? '';
  return name.isEmpty ? 'L' : name.characters.first.toUpperCase();
}

class Brand extends StatelessWidget {
  final bool compact;
  const Brand({super.key, this.compact = false});
  @override
  Widget build(BuildContext context) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: compact ? 31 : 36,
            height: compact ? 31 : 36,
            decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(11)),
            child: Icon(Icons.graphic_eq_rounded,
                color: Theme.of(context).colorScheme.onPrimary, size: 22)),
        const SizedBox(width: 11),
        Text('lingua',
            style: TextStyle(
                fontSize: compact ? 24 : 29,
                fontWeight: FontWeight.w600,
                letterSpacing: -1.3,
                color: Theme.of(context).colorScheme.onSurface))
      ]));
}

class DemoBadge extends StatelessWidget {
  const DemoBadge({super.key});
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.secondary),
          borderRadius: BorderRadius.circular(6)),
      child: Text(UiText.of(context, 'demoBadge'),
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
              color: Theme.of(context).colorScheme.secondary)));
}

class Sidebar extends StatelessWidget {
  final AppController controller;
  final bool drawer;
  const Sidebar({super.key, required this.controller, this.drawer = false});
  void choose(BuildContext context, int tab) {
    if (drawer) {
      Scaffold.maybeOf(context)?.closeDrawer();
    }
    controller.navigate(tab);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
        decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            border: Border(right: BorderSide(color: cs.outlineVariant))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
              padding: EdgeInsets.fromLTRB(24, 30, 24, 32), child: Brand()),
          _nav(context, 0, Icons.route_rounded, controller.tr('path')),
          _nav(context, 1, Icons.chat_bubble_outline_rounded,
              controller.tr('chat')),
          Padding(
              padding: const EdgeInsets.fromLTRB(26, 33, 20, 12),
              child: Text(UiText.of(context, 'journeyLabel'),
                  style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant))),
          Expanded(
              child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                for (final level
                    in controller.dashboard?.levels ?? <CourseLevel>[])
                  Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Material(
                          color: controller.selectedLevel == level.level &&
                                  controller.tab == 0
                              ? cs.surfaceContainerHighest
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          child: ListTile(
                              minLeadingWidth: 30,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              leading: Text(
                                  level.level == 'ONBOARDING'
                                      ? '·'
                                      : level.level,
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: level.status == 'locked'
                                          ? cs.onSurfaceVariant
                                          : cs.primary)),
                              title: Text(level.title,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurfaceVariant)),
                              trailing: Icon(
                                  level.status == 'locked'
                                      ? Icons.lock_outline_rounded
                                      : level.status == 'completed'
                                          ? Icons.check_circle_outline_rounded
                                          : Icons.arrow_forward_rounded,
                                  size: 16,
                                  color: cs.onSurfaceVariant),
                              onTap: () {
                                if (level.status == 'locked') {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(UiText.of(
                                              context, 'levelLocked'))));
                                } else {
                                  if (drawer) {
                                    Scaffold.maybeOf(context)?.closeDrawer();
                                  }
                                  controller.selectLevel(level.level);
                                }
                              })))
              ])),
          const Divider(height: 1),
          _nav(
              context, 5, Icons.history_rounded, controller.tr('historyTitle')),
          _nav(context, 3, Icons.tune_rounded, controller.tr('settings')),
          Padding(
              padding: const EdgeInsets.fromLTRB(25, 14, 25, 25),
              child: Text(UiText.of(context, 'brandMotto'),
                  style: TextStyle(
                      fontSize: 12, height: 1.6, color: cs.onSurfaceVariant))),
        ]));
  }

  Widget _nav(BuildContext context, int tab, IconData icon, String title) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: Material(
            color: controller.tab == tab
                ? cs.surfaceContainerHighest
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: ListTile(
                dense: true,
                leading: Icon(icon,
                    size: 20,
                    color: controller.tab == tab
                        ? cs.primary
                        : cs.onSurfaceVariant),
                title: Text(title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: controller.tab == tab
                            ? FontWeight.w600
                            : FontWeight.w400)),
                onTap: () => choose(context, tab))));
  }
}

class PathScreen extends StatelessWidget {
  final AppController controller;
  const PathScreen({super.key, required this.controller});
  @override
  Widget build(BuildContext context) {
    if (!controller.configured) {
      return const ConnectionWelcome();
    }
    if (controller.loading && controller.dashboard == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.error != null && controller.dashboard == null) {
      return StatusPane(
          icon: Icons.cloud_off_rounded,
          title: UiText.of(context, 'connectionInterrupted'),
          message: controller.error!,
          action: UiText.of(context, 'retry'),
          onAction: controller.refresh);
    }
    final data = controller.dashboard;
    if (data == null) {
      return StatusPane(
          icon: Icons.route_rounded,
          title: UiText.of(context, 'pathWelcome'),
          message: UiText.of(context, 'pathLoadHelp'),
          action: UiText.of(context, 'load'),
          onAction: controller.refresh);
    }
    if (data.currentLevel == 'ONBOARDING') {
      return OnboardingScreen(controller: controller);
    }
    final level = controller.level;
    final cs = Theme.of(context).colorScheme;
    return RefreshIndicator(
        onRefresh: controller.refresh,
        child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(
                MediaQuery.sizeOf(context).width < 600 ? 22 : 38),
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1040),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (controller.error != null)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: ErrorStrip(
                                    message: controller.error!,
                                    retry: controller.refresh)),
                          Wrap(spacing: 30, runSpacing: 8, children: [
                            Text(UiText.of(context, 'stepByStep'),
                                style: TextStyle(
                                    fontSize: 10,
                                    letterSpacing: 2.4,
                                    fontWeight: FontWeight.w600,
                                    color: cs.primary)),
                            Text(
                                UiText.of(context, 'lessonsCompleted',
                                    params: {'count': data.completed}),
                                style: TextStyle(
                                    fontSize: 12, color: cs.onSurfaceVariant))
                          ]),
                          const SizedBox(height: 14),
                          Text(UiText.of(context, 'nextStepTitle'),
                              style: MediaQuery.sizeOf(context).width < 600
                                  ? Theme.of(context).textTheme.headlineMedium
                                  : Theme.of(context).textTheme.displaySmall),
                          const SizedBox(height: 12),
                          Text(UiText.of(context, 'pathSubtitle'),
                              style: TextStyle(
                                  fontSize: 15, color: cs.onSurfaceVariant)),
                          const SizedBox(height: 29),
                          if (data.nextLesson != null) _continue(context, data),
                          const SizedBox(height: 34),
                          Wrap(spacing: 12, runSpacing: 10, children: [
                            for (final lv in data.levels)
                              Tooltip(
                                  message: lv.status == 'locked'
                                      ? UiText.of(context, 'unlockPrevious')
                                      : lv.title,
                                  child: ChoiceChip(
                                      label: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(lv.level),
                                            if (lv.status == 'locked') ...[
                                              const SizedBox(width: 7),
                                              const Icon(
                                                  Icons.lock_outline_rounded,
                                                  size: 13)
                                            ]
                                          ]),
                                      selected: lv.level == level?.level,
                                      onSelected: lv.status == 'locked'
                                          ? null
                                          : (_) =>
                                              controller.selectLevel(lv.level),
                                      showCheckmark: false))
                          ]),
                          const SizedBox(height: 30),
                          const Divider(),
                          const SizedBox(height: 22),
                          Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                        color: cs.surfaceContainerHighest,
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    alignment: Alignment.center,
                                    child: Text(level?.level ?? '·',
                                        style: TextStyle(
                                            color: cs.primary,
                                            fontWeight: FontWeight.bold))),
                                const SizedBox(width: 14),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(
                                          level?.title ??
                                              UiText.of(context, 'path'),
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge),
                                      Text(
                                          UiText.of(
                                              context, 'pathStations', params: {
                                            'count': level?.lessons.length ?? 0
                                          }),
                                          style: TextStyle(
                                              color: cs.onSurfaceVariant,
                                              fontSize: 12))
                                    ])),
                                const Icon(Icons.explore_outlined, size: 26)
                              ]),
                          if (level == null || level.lessons.isEmpty)
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 60),
                                child:
                                    Text(UiText.of(context, 'noCourseContent')))
                          else
                            LearningPath(
                                level: level, onStart: controller.startChat),
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 22),
                              child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.spa_outlined,
                                        color: cs.onSurfaceVariant, size: 17),
                                    const SizedBox(width: 9),
                                    Flexible(
                                        child: Text(
                                            UiText.of(context, 'progressMotto'),
                                            style: TextStyle(
                                                color: cs.onSurfaceVariant,
                                                fontSize: 12)))
                                  ])),
                        ])))));
  }

  Widget _continue(BuildContext context, Dashboard data) {
    final cs = Theme.of(context).colorScheme;
    final narrow = MediaQuery.sizeOf(context).width < 620;
    final content =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(UiText.of(context, 'continueHere'),
          style: TextStyle(
              fontSize: 10,
              letterSpacing: 2,
              color: cs.primary,
              fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Text(
          data.nextLesson!['title'] as String? ??
              UiText.of(context, 'nextLesson'),
          style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 7),
      Text(UiText.of(context, 'nextDiscovery'),
          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant))
    ]);
    final button = FilledButton(
        onPressed: controller.chatting ? null : controller.startChat,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: Text(UiText.of(context, 'letsBegin'))),
          const SizedBox(width: 18),
          const Icon(Icons.arrow_forward_rounded, size: 18)
        ]));
    return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            border: Border.all(color: cs.outlineVariant),
            borderRadius: BorderRadius.circular(20)),
        child: narrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [content, const SizedBox(height: 20), button])
            : Row(children: [
                Expanded(child: content),
                const SizedBox(width: 16),
                button
              ]));
  }
}

class LearningPath extends StatelessWidget {
  final CourseLevel level;
  final VoidCallback onStart;
  const LearningPath({super.key, required this.level, required this.onStart});
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth.clamp(0.0, 650.0);
        final extent = 170 +
            (MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.5) - 1) *
                100;
        final cs = Theme.of(context).colorScheme;
        return Center(
            child: SizedBox(
                width: width,
                child: CustomPaint(
                    painter: PathLinePainter(level.lessons.length,
                        cs.outlineVariant, cs.primary.withOpacity(.22), extent),
                    child: Column(children: [
                      for (var i = 0; i < level.lessons.length; i++)
                        SizedBox(
                            height: extent,
                            child: Align(
                                alignment: Alignment(
                                    i % 4 == 0
                                        ? -.48
                                        : i % 4 == 1
                                            ? .28
                                            : i % 4 == 2
                                                ? .48
                                                : -.28,
                                    0),
                                child: LessonNode(
                                    lesson: level.lessons[i],
                                    number: i + 1,
                                    onStart: onStart)))
                    ]))));
      });
}

class LessonNode extends StatefulWidget {
  final Lesson lesson;
  final int number;
  final VoidCallback onStart;
  const LessonNode(
      {super.key,
      required this.lesson,
      required this.number,
      required this.onStart});
  @override
  State<LessonNode> createState() => _LessonNodeState();
}

class _LessonNodeState extends State<LessonNode>
    with SingleTickerProviderStateMixin {
  late final AnimationController pulse;
  @override
  void initState() {
    super.initState();
    pulse =
        AnimationController(vsync: this, duration: const Duration(seconds: 3));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.lesson.status == 'available' &&
        !MediaQuery.of(context).disableAnimations) {
      pulse.repeat(reverse: true);
    } else {
      pulse.stop();
    }
  }

  @override
  void dispose() {
    pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final available = widget.lesson.status == 'available';
    final done = widget.lesson.status == 'completed';
    final lessonTitle = widget.lesson.title.isEmpty
        ? UiText.of(context, 'lesson')
        : widget.lesson.title;
    return SizedBox(
        width: 205,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Semantics(
              label:
                  '$lessonTitle, ${UiText.of(context, available ? 'availableStatus' : done ? 'completedStatus' : 'lockedStatus')}',
              button: available,
              child: AnimatedBuilder(
                  animation: pulse,
                  builder: (context, child) => Container(
                      padding:
                          EdgeInsets.all(available ? 5 + pulse.value * 3 : 6),
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: available
                              ? Border.all(
                                  color: cs.primary
                                      .withOpacity(.24 + pulse.value * .14),
                                  width: 1.5)
                              : null),
                      child: child),
                  child: SizedBox(
                      width: 62,
                      height: 62,
                      child: Material(
                          color: available
                              ? cs.primary
                              : done
                                  ? cs.surfaceContainerHighest
                                  : cs.surfaceContainerLow,
                          shape: CircleBorder(
                              side: BorderSide(
                                  color: available
                                      ? cs.primary
                                      : cs.outlineVariant)),
                          child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: available
                                  ? widget.onStart
                                  : () => ScaffoldMessenger.of(context)
                                      .showSnackBar(SnackBar(
                                          content: Text(done
                                              ? UiText.of(context,
                                                  'lessonAlreadyPassed')
                                              : UiText.of(context,
                                                  'lessonPreviousRequired')))),
                              child: Icon(
                                  done
                                      ? Icons.check_rounded
                                      : available
                                          ? Icons.graphic_eq_rounded
                                          : widget.lesson.exam
                                              ? Icons.outlined_flag_rounded
                                              : Icons.lock_outline_rounded,
                                  size: 25,
                                  color: available
                                      ? cs.onPrimary
                                      : done
                                          ? cs.primary
                                          : cs.onSurfaceVariant)))))),
          const SizedBox(height: 9),
          Text(lessonTitle,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: available ? FontWeight.w600 : FontWeight.w400,
                  color: available ? cs.onSurface : cs.onSurfaceVariant)),
          if (available)
            Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(UiText.of(context, 'nextStepLabel'),
                    style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                        color: cs.primary))),
        ]));
  }
}

class PathLinePainter extends CustomPainter {
  final int count;
  final Color line, accent;
  final double extent;
  PathLinePainter(this.count, this.line, this.accent, this.extent);
  @override
  void paint(Canvas canvas, Size size) {
    if (count < 2) {
      return;
    }
    final path = Path();
    double x(int i) {
      final align = i % 4 == 0
          ? -.48
          : i % 4 == 1
              ? .28
              : i % 4 == 2
                  ? .48
                  : -.28;
      return size.width / 2 + align * (size.width - 205) / 2;
    }

    path.moveTo(x(0), extent / 2 - 20);
    for (var i = 1; i < count; i++) {
      path.cubicTo(x(i - 1), (i - 1) * extent + extent, x(i), i * extent, x(i),
          i * extent + extent / 2 - 20);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant PathLinePainter oldDelegate) =>
      count != oldDelegate.count ||
      line != oldDelegate.line ||
      extent != oldDelegate.extent;
}

class SettingsScreen extends StatelessWidget {
  final AppController controller;
  const SettingsScreen({super.key, required this.controller});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 650),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 15),
                      Text(controller.tr('settingsTitle'),
                          style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 12),
                      Text(controller.tr('settingsHelp'),
                          style: TextStyle(color: cs.onSurfaceVariant)),
                      const SizedBox(height: 40),
                      Text(controller.tr('appearance'),
                          style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 2,
                              color: cs.primary)),
                      const SizedBox(height: 14),
                      for (final option in [
                        (
                          ThemeMode.light,
                          Icons.light_mode_outlined,
                          controller.tr('light'),
                          UiText.of(context, 'lightHelp')
                        ),
                        (
                          ThemeMode.dark,
                          Icons.dark_mode_outlined,
                          controller.tr('dark'),
                          UiText.of(context, 'darkHelp')
                        ),
                        (
                          ThemeMode.system,
                          Icons.brightness_auto_outlined,
                          controller.tr('system'),
                          UiText.of(context, 'systemHelp')
                        )
                      ])
                        Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Material(
                                color: controller.theme == option.$1
                                    ? cs.surfaceContainerHighest
                                    : cs.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(15),
                                child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 8),
                                    leading: Icon(option.$2, color: cs.primary),
                                    title: Text(option.$3),
                                    subtitle: Text(option.$4,
                                        style: const TextStyle(fontSize: 12)),
                                    trailing: Icon(
                                        controller.theme == option.$1
                                            ? Icons.radio_button_checked
                                            : Icons.radio_button_unchecked,
                                        color: cs.primary),
                                    onTap: () =>
                                        controller.setTheme(option.$1)))),
                      const SizedBox(height: 35),
                      const Divider(),
                      const SizedBox(height: 23),
                      Text(UiText.of(context, 'yourLearning'),
                          style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 2,
                              color: cs.primary)),
                      const SizedBox(height: 15),
                      LanguageSettings(controller: controller),
                      const SizedBox(height: 24),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading:
                            Icon(Icons.edit_note_rounded, color: cs.primary),
                        title: Text(controller.tr('journal')),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => controller.navigate(4),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.history_rounded, color: cs.primary),
                        title: Text(controller.tr('historyTitle')),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => controller.navigate(5),
                      ),
                      if (!controller.demo)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.logout_rounded, color: cs.primary),
                          title: Text(controller.tr('logout')),
                          onTap: controller.languageBusy
                              ? null
                              : () => controller.logout(),
                        ),
                      const SizedBox(height: 16),
                      Text(UiText.of(context, 'audioFeatureHelp'),
                          style: TextStyle(
                              fontSize: 13, color: cs.onSurfaceVariant)),
                      const SizedBox(height: 30),
                      if (controller.demo)
                        Text(UiText.of(context, 'demoContentNote')),
                      Text('Lingua 1.0',
                          style: TextStyle(
                              fontSize: 11, color: cs.onSurfaceVariant))
                    ]))));
  }
}

class ConnectionWelcome extends StatelessWidget {
  const ConnectionWelcome({super.key});
  @override
  Widget build(BuildContext context) => StatusPane(
      icon: Icons.waving_hand_outlined,
      title: UiText.of(context, 'connectionWelcome'),
      message: UiText.of(context, 'connectionHelp'));
}

class OnboardingScreen extends StatelessWidget {
  final AppController controller;
  const OnboardingScreen({super.key, required this.controller});
  bool get placementAvailable =>
      controller.dashboard?.levels.any(
          (level) => level.level == 'ONBOARDING' && level.lessons.isNotEmpty) ??
      false;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
      padding: const EdgeInsets.all(30),
      child: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 550),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 55),
                    Icon(Icons.explore_outlined,
                        size: 45, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 26),
                    Text(controller.tr('startTitle'),
                        style: Theme.of(context).textTheme.displaySmall),
                    const SizedBox(height: 16),
                    Text(controller.tr('startHelp')),
                    const SizedBox(height: 25),
                    LanguageSettings(controller: controller),
                    const SizedBox(height: 35),
                    FilledButton(
                        onPressed: controller.onboarding ||
                                controller.languagesSaving ||
                                controller.languageDraftDirty
                            ? null
                            : () => controller.onboard('beginner'),
                        child: Text(controller.tr('beginner'))),
                    const SizedBox(height: 14),
                    OutlinedButton(
                        onPressed: controller.onboarding ||
                                controller.languagesSaving ||
                                controller.languageDraftDirty ||
                                !placementAvailable
                            ? null
                            : () => controller.onboard('placement'),
                        child: Text(controller.tr('placement'))),
                    if (!placementAvailable)
                      Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(controller.tr('noPlacement'))),
                    if (controller.onboarding)
                      const Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator()),
                    if (controller.error != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: Text(controller.error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)))
                  ]))));
}

class StatusPane extends StatelessWidget {
  final IconData icon;
  final String title, message;
  final String? action;
  final VoidCallback? onAction;
  const StatusPane(
      {super.key,
      required this.icon,
      required this.title,
      required this.message,
      this.action,
      this.onAction});
  @override
  Widget build(BuildContext context) => Center(
      child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerLow,
                            borderRadius: BorderRadius.circular(23)),
                        child: Icon(icon,
                            size: 33,
                            color: Theme.of(context).colorScheme.primary)),
                    const SizedBox(height: 26),
                    Text(title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 15),
                    Text(message,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                    if (action != null) ...[
                      const SizedBox(height: 26),
                      FilledButton(onPressed: onAction, child: Text(action!))
                    ]
                  ]))));
}

class ErrorStrip extends StatelessWidget {
  final String message;
  final VoidCallback retry;
  const ErrorStrip({super.key, required this.message, required this.retry});
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(message,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer)),
        TextButton(onPressed: retry, child: Text(UiText.of(context, 'retry')))
      ]));
}
