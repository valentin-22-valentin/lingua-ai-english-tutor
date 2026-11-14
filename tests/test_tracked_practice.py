import pytest
from backend.curriculum import tracked_progress, TRACKED_MARKER
from backend.curriculum import tracked_instruction
from pathlib import Path
from tools.seed_database import load_course, lesson_prompt
from backend.tutor_engine import generate_reply
from test_tutor import REPLY, ai_client


def call(index, text='My name is Ada.', passed=True, **changes):
    client = ai_client({**REPLY, 'task_passed': passed, **changes})
    result = generate_reply(client, 'gpt-4o-mini', TRACKED_MARKER, [], text,
                            task_index=index, answered_turns=8)
    assert client.chat.completions.create.call_args.kwargs['max_tokens'] == 200
    schema = client.chat.completions.create.call_args.kwargs['response_format']['json_schema']['schema']
    assert next(iter(schema['properties'])) == 'task_passed'
    return result


def test_only_sequential_persisted_success_advances():
    rows = [{'input_text': 'x', 'result': {'task_result': {'task_index': i, 'passed': ok}}}
            for i, ok in [(0, False), (0, True), (0, True), (2, True), (1, True)]]
    assert tracked_progress(rows) == 2
    assert tracked_progress([{'input_text': None, 'result': {'task_result': {'task_index': 0, 'passed': True}}}]) == 0
    assert tracked_progress([{'input_text': 'yes', 'result': {}}] * 100) == 0


def test_early_completion_cannot_unlock_a_lesson():
    result = call(2, lesson_complete=True, score=100)
    assert not result.lesson_complete and result.score is None


@pytest.mark.parametrize('text', ['yes', 'Yes!', 'ok', 'thank you', 'igen',
                                'ja', 'nein', 'oui', 'non', 'da', 'nu', 'sí'])
def test_acknowledgement_is_not_independent_evidence(text):
    result = call(7, text, lesson_complete=True, score=100)
    assert not result.task_passed and not result.lesson_complete


def test_final_success_completes_even_if_model_forgets_completion_flag():
    result = call(7)
    assert result.lesson_complete and result.score == 100


def test_failed_transfer_keeps_practice_open():
    assert not call(7, passed=False).lesson_complete


def test_premature_score_without_completion_does_not_strand_tracked_chat():
    reply=call(6,score=100,lesson_complete=False)
    assert reply.task_passed and reply.score is None and not reply.lesson_complete


@pytest.mark.parametrize('index', [0, 1])
def test_comprehension_error_does_not_pollute_target_language_memory(index):
    reply = call(index, 'It means I am sick.', passed=False, mistakes=[{
        'wrong_sentence':'It means I am sick.', 'corrected_sentence':'It means hello.',
        'grammar_rule':'Meaning explanation'}], reviews=[{'mistake_id':999, 'correct':True}])
    assert not reply.mistakes and not reply.reviews and not reply.task_passed


def test_transfer_is_presented_even_when_model_says_goodbye():
    from backend.curriculum import render_plan
    ROOT = Path(__file__).resolve().parents[1]
    import json
    lesson = json.loads((ROOT/'curriculum/a1.json').read_text(encoding='utf-8'))[0]
    client = ai_client({**REPLY, 'text':'Goodbye!', 'task_passed':True})
    reply = generate_reply(client, 'gpt-4o-mini', render_plan(lesson['teaching_plan']),
                           [], 'Goodbye!', task_index=6, answered_turns=7)
    assert lesson['teaching_plan']['practice_tasks'][7] in reply.text
    assert not reply.lesson_complete


def test_starting_model_is_visible_even_when_ai_omits_it():
    from backend.curriculum import render_plan
    ROOT = Path(__file__).resolve().parents[1]
    import json
    lesson = json.loads((ROOT/'curriculum/a1.json').read_text(encoding='utf-8'))[0]
    client = ai_client({**REPLY, 'text':'What does this mean?', 'task_passed':False})
    reply = generate_reply(client, 'gpt-4o-mini', render_plan(lesson['teaching_plan']),
                           [], 'Start', greeting=True)
    assert lesson['teaching_plan']['model'][0] in reply.text


def test_first_success_always_teaches_and_asks_the_second_comprehension_task():
    from backend.curriculum import render_plan
    import json
    lesson = json.loads((Path(__file__).resolve().parents[1]/'curriculum/a1.json').read_text(encoding='utf-8'))[0]
    client = ai_client({**REPLY, 'text': 'Well done!', 'task_passed': True})
    reply = generate_reply(client, 'gpt-4o-mini', render_plan(lesson['teaching_plan']),
                           [], 'Hello, I am Mina. What is your name?', task_index=0, answered_turns=1)
    assert lesson['teaching_plan']['model'][1] in reply.text
    assert 'What does' in reply.text and not reply.lesson_complete


def test_comprehension_grades_the_learner_instead_of_asking_them_to_teach():
    from backend.curriculum import render_plan
    import json
    lesson = json.loads((Path(__file__).resolve().parents[1]/'curriculum/a1.json').read_text(encoding='utf-8'))[0]
    client = ai_client({**REPLY, 'task_passed': False})
    generate_reply(client, 'gpt-4o-mini', render_plan(lesson['teaching_plan']),
                   [], 'Please explain the example.', task_index=1, answered_turns=2)
    request = client.chat.completions.create.call_args.kwargs
    description = request['response_format']['json_schema']['schema']['properties']['task_passed']['description']
    assert lesson['teaching_plan']['model'][1] in description
    assert 'learner is not asked to teach' in description
    assert 'request to show, explain or repeat' in description


def test_current_task_is_explicit_and_all_real_prompts_fit():
    from backend.tutor_engine import build_prompt
    root=Path(__file__).resolve().parents[1]
    _,courses=load_course(root/'curriculum/manifest.json')
    for lesson in courses[0][1]:
        prompt=build_prompt({'native_lang_code':'hu','target_lang_code':'en'},
            {'system_prompt':lesson_prompt(lesson,'A1'),'passing_score':80},
            {'hu':'Hungarian','en':'English'},[],['A1'])
        for index in range(8):
            instruction=tracked_instruction(index,index==0,prompt)
            assert lesson['teaching_plan']['practice_tasks'][index] in instruction
            assert len(prompt+instruction)<8000
