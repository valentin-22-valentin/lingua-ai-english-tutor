import json
from types import SimpleNamespace
from unittest.mock import Mock, patch
from uuid import uuid4

import pytest
from postgrest.exceptions import APIError

from backend.journal_service import JournalService
from backend.tutor_engine import TutorService, TutorError
from test_tutor import api, fixture_db, ai_client, PROFILE, REQUEST


def rpc_result(data):
    return SimpleNamespace(execute=lambda: SimpleNamespace(data=data))


def feedback_client(reply, reason='stop'):
    client = ai_client(reply, finish_reason=reason)
    return client


def test_journal_feedback_has_200_cap_and_discards_invented_correction():
    client = feedback_client({'text': 'Try a past tense.', 'corrections': [{
        'wrong_sentence': 'Invented', 'corrected_sentence': 'Changed', 'grammar_rule': 'Past tense'}]})
    service = JournalService(TutorService(fixture_db(), client))
    result = service.feedback(service.tutor.profile(PROFILE), 'I went shopping today.')
    assert result['corrections'] == []
    args = client.chat.completions.create.call_args.kwargs
    assert args['max_tokens'] == 200
    assert 'UNTRUSTED DATA' in args['messages'][0]['content']
    assert json.loads(args['messages'][1]['content'])['journal'] == 'I went shopping today.'


def test_journal_keeps_verbatim_actual_correction():
    client = feedback_client({'text': 'Past tense.', 'corrections': [{
        'wrong_sentence': 'I go yesterday', 'corrected_sentence': 'I went yesterday', 'grammar_rule': 'Past tense'}]})
    service = JournalService(TutorService(fixture_db(), client))
    result = service.feedback(service.tutor.profile(PROFILE), 'I go yesterday to school.')
    assert result['corrections'][0]['wrong_sentence'] == 'I go yesterday'


@pytest.mark.parametrize('reason', ['length', 'content_filter'])
def test_truncated_journal_feedback_cannot_be_saved(reason):
    service = JournalService(TutorService(fixture_db(), feedback_client({'text': 'Hello', 'corrections': []}, reason)))
    with pytest.raises(TutorError):
        service.feedback(service.tutor.profile(PROFILE), 'I went shopping.')


def test_cached_journal_is_free_and_changed_text_is_conflict():
    db = fixture_db()
    db.rows['journal_entries'] = [{'profile_id': PROFILE, 'request_id': REQUEST, 'content': 'Today was good.',
        'id': str(uuid4()), 'feedback': {'text': 'Nice!', 'corrections': []}}]
    client = ai_client()
    service = JournalService(TutorService(db, client))
    assert service.journal(PROFILE, REQUEST, 'Today was good.')['feedback']['text'] == 'Nice!'
    with pytest.raises(TutorError) as exc:
        service.journal(PROFILE, REQUEST, 'Different')
    assert exc.value.status_code == 409
    client.chat.completions.create.assert_not_called()
    db.rpc.assert_not_called()


def test_journal_discussion_rejects_another_users_entry_before_ai():
    db = fixture_db()
    db.rows['journal_entries'] = [{'profile_id': str(uuid4()), 'id': REQUEST, 'content': 'Private'}]
    client = ai_client()
    with pytest.raises(TutorError) as exc:
        JournalService(TutorService(db, client)).discuss(PROFILE, REQUEST, str(uuid4()), 'Explain')
    assert exc.value.status_code == 404
    client.chat.completions.create.assert_not_called()
    db.rpc.assert_not_called()


def test_journal_requires_auth_when_enabled(api, monkeypatch):
    monkeypatch.setenv('AUTH_REQUIRED', 'true')
    client, service = api
    assert client.get(f'/api/journal/{PROFILE}').status_code == 401
    assert client.post('/api/journal', json={'profile_id': PROFILE, 'request_id': REQUEST, 'content': 'Hi'}).status_code == 401
    assert client.delete(f'/api/journal/{REQUEST}?profile_id={PROFILE}').status_code == 401
    service.db.rpc.assert_not_called()


def test_blank_journal_never_writes(api):
    client, service = api
    assert client.post('/api/journal', json={'profile_id': PROFILE, 'request_id': REQUEST, 'content': '   '}).status_code == 422
    service.db.rpc.assert_not_called()


def test_login_does_not_mutate_admin_auth_client(api):
    from backend.api import auth_limiter
    auth_limiter.events.clear()
    client, _ = api
    auth = Mock()
    auth.auth.sign_in_with_password.return_value = SimpleNamespace(user=SimpleNamespace(id=PROFILE, user_metadata={}),
        session=SimpleNamespace(access_token='test-access', refresh_token='test-refresh', expires_in=3600))
    admin = fixture_db()
    with patch('backend.api.auth_client', return_value=auth), patch('backend.api.get_database', return_value=admin):
        response = client.post('/api/auth/login', json={'email': 'test@example.org', 'password': 'testpass'})
    assert response.status_code == 200
    assert response.json()['profile_id'] == PROFILE
    auth.auth.sign_in_with_password.assert_called_once()
    assert not admin.writes


def test_registration_confirmation_has_no_tokens_or_profile_grant(api):
    from backend.api import auth_limiter
    auth_limiter.events.clear()
    client, _ = api
    auth = Mock()
    auth.auth.sign_up.return_value = SimpleNamespace(user=SimpleNamespace(id=PROFILE), session=None)
    with patch('backend.api.auth_client', return_value=auth), patch('backend.api.ensure_profile') as initialize:
        response = client.post('/api/auth/register', json={'email': 'test@example.org', 'password': 'testpass', 'username': 'Alex'})
    assert response.json() == {'confirmation_required': True}
    initialize.assert_not_called()
