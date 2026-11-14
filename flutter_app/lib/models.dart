class Lesson {
  final int id;
  final String title, status, type;
  final bool exam;
  Lesson(
      {required this.id,
      required this.title,
      required this.status,
      this.type = 'lesson',
      this.exam = false});
  factory Lesson.fromJson(Map<String, dynamic> json) => Lesson(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',
      status: json['status'] as String? ?? 'locked',
      type: json['lesson_type'] as String? ?? 'lesson',
      exam: json['is_level_exam'] == true);
}

class CourseLevel {
  final String level, title, status;
  final List<Lesson> lessons;
  CourseLevel(
      {required this.level,
      required this.title,
      required this.status,
      required this.lessons});
  factory CourseLevel.fromJson(Map<String, dynamic> json) => CourseLevel(
      level: json['level'] as String,
      title: json['title'] as String? ?? '',
      status: json['status'] as String? ?? 'locked',
      lessons: (json['lessons'] as List? ?? [])
          .map((e) => Lesson.fromJson(Map<String, dynamic>.from(e)))
          .toList());
}

class Dashboard {
  final String username,
      currentLevel,
      nativeLanguage,
      targetLanguage,
      appLanguage;
  final List<CourseLevel> levels;
  final int completed;
  final Map<String, dynamic>? nextLesson;
  Dashboard(
      {required this.username,
      this.nativeLanguage = "hu",
      this.targetLanguage = "en",
      this.appLanguage = "hu",
      required this.currentLevel,
      required this.levels,
      this.completed = 0,
      this.nextLesson});
  factory Dashboard.fromJson(Map<String, dynamic> json) {
    final profile = Map<String, dynamic>.from(json['profile'] ?? {});
    return Dashboard(
        nativeLanguage: profile['native_language'] as String? ?? 'hu',
        targetLanguage: profile['target_language'] as String? ?? 'en',
        appLanguage: profile['app_language'] as String? ?? 'hu',
        username: profile['username'] as String? ?? '',
        currentLevel: profile['current_level'] as String? ?? 'ONBOARDING',
        levels: (json['levels'] as List? ?? [])
            .map((e) => CourseLevel.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        completed: (json['completed_lessons'] as List? ?? []).length,
        nextLesson: json['next_lesson'] == null
            ? null
            : Map<String, dynamic>.from(json['next_lesson']));
  }
}

class ChatMessage {
  final String text;
  final bool user;
  ChatMessage(this.text, {this.user = false});
}
