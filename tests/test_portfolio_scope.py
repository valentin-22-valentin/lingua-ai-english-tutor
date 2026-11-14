"""Regression checks for removing media without breaking persisted text tutoring."""
import json
from pathlib import Path

from test_tutor import fixture_db, PROFILE, SESSION, api
from backend.tutor_engine import TutorService, build_prompt, generate_reply
from tools.seed_database import load_course, lesson_prompt
from backend.curriculum import tracked_instruction
from test_tutor import ai_client, REPLY

ROOT = Path(__file__).resolve().parents[1]


def test_saved_tutor_context_never_queries_legacy_media_tables():
    db = fixture_db()
    original = db.table

    def without_media(table):
        assert table not in {
            'learning_images', 'lesson_images', 'learning_videos', 'learning_listening'
        }
        return original(table)

    db.table = without_media
    context = TutorService(db, None).context(PROFILE, SESSION)
    assert context['lesson'] and context['session']['id'] == SESSION
    assert 'visual' not in context


def test_removed_feed_and_listening_routes_are_not_served(api):
    client, _ = api
    assert client.get('/api/feed').status_code == 404
    assert client.get('/api/listening').status_code == 404
    assert client.post('/api/listening/answer', json={}).status_code == 404


def test_directions_can_be_taught_without_an_unseen_map():
    _, courses = load_course(ROOT / 'curriculum/manifest.json')
    lesson = next(row for row in courses[0][1] if row['lesson_id'] == 'A1_08')
    plan = json.dumps(lesson['teaching_plan']).lower()
    assert not any(word in plan for word in ['picture', 'shown map', 'shown north', 'visual'])
    prompt = build_prompt(
        {'native_lang_code': 'hu', 'target_lang_code': 'en'},
        {'system_prompt': lesson_prompt(lesson, 'A1'), 'passing_score': 80},
        {'hu': 'Hungarian', 'en': 'English'}, [], ['A1'])
    client = ai_client({**REPLY, 'task_passed': True})
    reply = generate_reply(client, 'gpt-4o-mini',
        prompt + tracked_instruction(4, False, prompt), [],
        'Go straight ahead, then turn left.', task_index=4, answered_turns=5)
    assert reply.task_passed
    messages = client.chat.completions.create.call_args.kwargs['messages']
    assert all(isinstance(message['content'], str) for message in messages)
