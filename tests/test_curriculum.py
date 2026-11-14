import json
from pathlib import Path
import pytest

from backend.curriculum import LANGUAGES, validate_plan, stage_instruction
from tools.seed_database import load_course, lesson_prompt, exam_prompt, seed_database
from backend.tutor_engine import TutorError, TutorService, build_prompt, generate_reply
from test_tutor import MemoryDB, PROFILE, SESSION, REPLY, ai_client, fixture_db, api

ROOT = Path(__file__).resolve().parents[1]


def test_all_courses_validate_and_fit_actual_tutor_prompt():
    manifests = [ROOT/'curriculum/manifest.json']
    assert len(manifests) == 1
    for path in manifests:
        manifest, courses = load_course(path)
        target = manifest['target_lang_code']
        for entry, lessons in courses:
            for lesson in lessons:
                prompt = build_prompt({'native_lang_code':'hu' if target!='hu' else 'en',
                    'target_lang_code':target}, {'system_prompt':lesson_prompt(lesson,entry['level']),
                    'passing_score':80}, LANGUAGES, [], ['A1'])
                assert max(len(prompt + stage_instruction(n)) for n in [0,3,5,7]) < 7600, lesson['lesson_id']
            if entry.get('include_exam', True):
                prompt=build_prompt({'native_lang_code':'hu','target_lang_code':target},
                    {'system_prompt':exam_prompt(lessons,entry['level']),'passing_score':85},LANGUAGES,[],['A1'])
                assert len(prompt)<8000


def test_a1_models_are_original_typed_material_not_fake_listening():
    lessons=json.loads((ROOT/'curriculum/a1.json').read_text(encoding='utf-8'))
    assert len(lessons)==21
    for lesson in lessons:
        plan=lesson['teaching_plan']
        validate_plan(plan,'en')
        assert plan['review_status']=='pilot'
        assert plan['source_text'] and plan['transfer_task']
    assert 'quickly' not in lessons[1]['scenario_context']


def test_wrong_language_plan_rejected_before_database_write(tmp_path):
    manifest,courses=load_course(ROOT/'curriculum/manifest.json')
    lesson=courses[0][1][0]
    lesson['teaching_plan']['target_language']='de'
    (tmp_path/'lesson.json').write_text(json.dumps([lesson]),encoding='utf-8')
    manifest['levels']=[{'level':'A1','file':'lesson.json'}]
    path=tmp_path/'manifest.json';path.write_text(json.dumps(manifest))
    db=MemoryDB()
    with pytest.raises(ValueError,match='target language'):
        seed_database(db,path)
    assert not db.writes


@pytest.mark.parametrize('target', ['hu', 'ro', 'es', 'fr', 'de'])
def test_other_teaching_targets_are_rejected_before_writes(tmp_path, target):
    manifest = json.loads((ROOT/'curriculum/manifest.json').read_text(encoding='utf-8'))
    manifest['target_lang_code'] = target
    file = tmp_path/'manifest.json'
    file.write_text(json.dumps(manifest), encoding='utf-8')
    db = MemoryDB()
    with pytest.raises(ValueError, match='Only English'):
        seed_database(db, file)
    assert not db.writes


def test_v2_does_not_accept_early_model_completion():
    reply={**REPLY,'lesson_complete':True,'score':100}
    with pytest.raises(TutorError):
        generate_reply(ai_client(reply),'gpt-4o-mini','TEACHING_PLAN_V2',[], 'yes',answered_turns=2)
    assert generate_reply(ai_client(reply),'gpt-4o-mini','TEACHING_PLAN_V2',[],
                          'A new independent answer',answered_turns=8).lesson_complete


def test_due_reviews_never_cross_target_languages():
    db=fixture_db()
    db.rows['user_mistakes']=[{'id':1,'profile_id':PROFILE,'mastered':False,
        'target_lang_code':'de','next_review_at':'2000-01-01','created_at':'2000-01-01',
        'wrong_sentence':'x','corrected_sentence':'y','grammar_rule':'g'}]
    assert TutorService(db,None).context(PROFILE,SESSION)['mistakes']==[]


def test_finishing_starter_does_not_request_nonexistent_exam():
    db=fixture_db()
    db.rows['user_progress']=[{'profile_id':PROFILE,'lesson_id':n,'passed':True} for n in [1,2]]
    service=TutorService(db,None)
    with pytest.raises(TutorError,match='További leckék'):
        service.next_lesson(service.profile(PROFILE))
    assert service.dashboard(PROFILE)['next_lesson'] is None


@pytest.mark.parametrize('language', ['hu', 'en', 'ro', 'es', 'fr', 'de'])
def test_english_settings_accept_every_explanation_language(api, language):
    client, service = api
    service.db.rpc.side_effect = None
    service.db.rpc.return_value.execute.return_value.data = {'target_language':'en'}
    body = {'profile_id':PROFILE,'native_language':language,'app_language':'fr'}
    assert client.post('/api/profile/languages',json=body).status_code == 200
    params = service.db.rpc.call_args.args[1]
    assert params['p_native'] == language and params['p_target'] == 'en'
    assert params['p_expected_target'] == 'en'


@pytest.mark.parametrize('target', ['hu', 'ro', 'es', 'fr', 'de'])
def test_api_cannot_be_used_to_switch_the_teaching_target(api, target):
    client, service = api
    body = {'profile_id':PROFILE,'native_language':'hu','app_language':'en',
            'target_language':target}
    assert client.post('/api/profile/languages',json=body).status_code == 422
    service.db.rpc.assert_not_called()


def test_unmigrated_non_english_profile_cannot_start_a_paid_lesson():
    db = fixture_db()
    db.rows['profiles'][0]['target_lang_code'] = 'de'
    client = ai_client()
    with pytest.raises(TutorError, match='9-es'):
        TutorService(db,client).chat(PROFILE,'Hallo', 'request')
    client.chat.completions.create.assert_not_called()


def test_preferences_cannot_call_old_session_resetting_rpc(api):
    client, service = api
    service.db.rows['schema_releases'] = [{'id': 8}]
    response = client.post('/api/profile/languages', json={
        'profile_id':PROFILE,'native_language':'de','app_language':'fr'})
    assert response.status_code == 503 and '9-es' in response.json()['detail']
    service.db.rpc.assert_not_called()


@pytest.mark.parametrize('explanation', ['hu', 'en', 'ro', 'es', 'fr', 'de'])
def test_all_explanation_preferences_keep_the_taught_language_english(explanation):
    prompt = build_prompt({'native_lang_code':explanation,'target_lang_code':'en'},
        {'system_prompt':'Practise {target_language}.','passing_score':80},
        LANGUAGES,[],['A1'])
    assert 'You teach English ONLY' in prompt
    assert f'Default explanations: {LANGUAGES[explanation]}' in prompt
    assert "question's language" in prompt
    assert 'Help alone never' in prompt
