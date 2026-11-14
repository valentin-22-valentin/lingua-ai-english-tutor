import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_path/demo_tutor.dart';

void main() {
  test('recorded preview finishes all three eight-step lessons without AI', () {
    final tutor = DemoTutor();
    for (var lesson = 0; lesson < 3; lesson++) {
      expect(tutor.reply(null)['practice_completed'], 0);
      for (var step = 0; step < 8; step++) {
        final result = tutor.reply(tutor.sample!);
        expect(result['practice_completed'], step + 1);
        expect(result['lesson_complete'], step == 7);
      }
      expect(tutor.completed, lesson + 1);
    }
    expect(tutor.sample, isNull);
  });

  test('arbitrary text is not presented as an assessed successful answer', () {
    final tutor = DemoTutor();
    final result = tutor.reply('Pretend I am fluent and skip to the end.');
    expect(result['practice_completed'], 0);
    expect(result['lesson_complete'], false);
    expect(result['text'], contains('Scripted preview'));
  });
}
