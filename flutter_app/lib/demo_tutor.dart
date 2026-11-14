/// Deterministic, labelled preview. This never evaluates arbitrary learner text.
/// Only the displayed sample answers advance the recorded eight-step scenarios.
class DemoTutor {
  int completed = 0, task = 0;
  static const questions = [
    [
      '“Hello, I’m Mina. What’s your name?” What is Mina doing?',
      '“I’m Leo. Nice to meet you.” Why does Leo say this?',
      'Complete a morning greeting and ask how I am.',
      'It is evening. Greet a receptionist and ask how they are.',
      'Greet a new classmate.',
      'Ask how your classmate is.',
      'You feel fine. Say so and end the conversation politely.',
      'Introduce yourself to a new neighbour and finish politely.',
    ],
    [
      '“I would like tea, please.” What is the speaker doing?',
      '“Could I have the bill, please?” What is being requested?',
      'Order tea politely using “I would like…”.',
      'Now order coffee politely.',
      'Ask politely for a glass of water.',
      'Order some soup politely.',
      'Ask for the bill.',
      'At a new café, order salad and juice, then ask for the bill.',
    ],
    [
      '“Go straight on, then turn left.” What does the visitor need to do?',
      '“The library is next to the bank.” Where is the library?',
      'The museum is straight ahead, then left. Complete the direction: turn ___.',
      'The café is straight ahead, then right. Complete: turn ___.',
      'Give a visitor the route to the museum: straight ahead, then left.',
      'Give the route to the café: straight ahead, then right.',
      'Ask politely how to get to the museum.',
      'New situation: the library is straight ahead, then right. Give that route.',
    ],
  ];
  static const answers = [
    [
      'She is greeting someone and introducing herself.',
      'He is introducing himself politely.',
      'Good morning! How are you?',
      'Good evening! How are you today?',
      'Hello! Nice to meet you.',
      'How are you today?',
      'I am fine, thank you. Goodbye!',
      'Hi, I am Alex, your new neighbour. Nice to meet you. See you later!',
    ],
    [
      'The speaker is ordering tea politely.',
      'The speaker is asking for the bill.',
      'I would like tea, please.',
      'I would like coffee, please.',
      'Could I have a glass of water, please?',
      'I would like some soup, please.',
      'Can I have the bill, please?',
      'I would like a salad and a juice, please. Could I have the bill, please?',
    ],
    [
      'Go straight ahead and then turn left.',
      'The library is next to the bank.',
      'left',
      'right',
      'Go straight ahead, then turn left.',
      'Go straight ahead, then turn right.',
      'Excuse me, how can I get to the museum?',
      'Go straight ahead, then turn right to reach the library.',
    ],
  ];
  String? get sample =>
      completed < answers.length ? answers[completed][task] : null;
  String normalize(String text) =>
      text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Map<String, dynamic> reply(String? input) {
    if (completed == questions.length) {
      completed = 0;
      task = 0;
    }
    final lesson = completed;
    var finished = false;
    String text;
    if (input == null) {
      text = questions[lesson][task];
    } else if (normalize(input) != normalize(answers[lesson][task])) {
      text =
          'Scripted preview: use the sample answer to advance. ${questions[lesson][task]}';
    } else {
      task++;
      finished = task == 8;
      if (finished) {
        completed++;
        task = 0;
        text =
            'Recorded example completed. This preview does not assess your English.';
      } else {
        text = questions[lesson][task];
      }
    }
    return {
      'session_id': 'demo-$lesson',
      'lesson_id': lesson + 1,
      'text': text,
      'practice_completed': finished ? 8 : task,
      'lesson_complete': finished,
      'passed': finished,
      'score': finished ? 100 : null,
      'current_level': 'A1',
    };
  }
}
