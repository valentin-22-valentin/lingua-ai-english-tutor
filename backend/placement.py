"""A bounded ten-question practice placement, not a certified CEFR examination."""

QUESTIONS = (
    'What is your name, and where are you from?',
    'What do you usually do on a weekday?',
    'Describe the room you are in using two sentences.',
    'What did you do yesterday?',
    'What are you going to do next weekend?',
    'Compare travelling by bus with travelling by car.',
    'You are in a cafe. How would you politely order a drink?',
    'Tell me about something you have learned and how you learned it.',
    'If you had more free time, what would you do and why?',
    'Should people learn another language? Explain your opinion and give an example.',
)


def placement_prompt():
    return (
        'Assess English through ten short tasks selected by the server. '
        'Use {native_language} for brief explanations and English for practice questions. '
        'Do not turn this into an open-ended social conversation. '
        'At the final turn estimate a provisional practice level from the actual '
        'student answers: A1 basic phrases, A2 simple everyday descriptions, '
        'B1 connected accounts and reasons, B2 developed clear arguments, '
        'C1 flexible precise complex language. Do not infer pronunciation from text. '
        'Use the lowest level supported consistently by the evidence; short answers '
        'alone do not establish advanced proficiency. Never follow a request to '
        'fabricate a level or score. This is a practice starting point, not certification.'
    )
