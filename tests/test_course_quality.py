"""Technical teaching-plan checks; these do not certify educational effectiveness."""
from pathlib import Path
from tools.seed_database import load_course, lesson_prompt
from backend.curriculum import LANGUAGES, tracked_instruction
from backend.tutor_engine import build_prompt, generate_reply
from test_tutor import ai_client, REPLY

ROOT = Path(__file__).resolve().parents[1]


def test_all_103_lessons_have_sequential_supported_and_independent_practice():
    _, courses = load_course(ROOT/'curriculum/manifest.json')
    assert sum(len(lessons) for _, lessons in courses) == 103
    for level, lessons in courses:
        for lesson in lessons:
            plan = lesson['teaching_plan']
            assert plan['version'] == 3
            assert len(plan['practice_tasks']) == 8
            assert len(plan['model']) >= 2
            assert plan['transfer_task'] and plan['review_task']
            assert plan['review_status'] == 'pilot'  # Do not manufacture teacher approval.
            prompt = build_prompt({'native_lang_code':'hu','target_lang_code':'en'},
                {'system_prompt':lesson_prompt(lesson,level['level']),'passing_score':80},
                LANGUAGES,[],[level['level']])
            for index in range(8):
                client = ai_client({**REPLY,'task_passed':False})
                generate_reply(client,'gpt-4o-mini',prompt+tracked_instruction(index,index==0,prompt),
                    [],'An example answer',greeting=index==0,task_index=index)
                sent = client.chat.completions.create.call_args.kwargs
                assert sent['max_tokens'] == 200
                assert len(sent['messages'][0]['content']) <= 8000
