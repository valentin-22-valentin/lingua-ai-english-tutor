from types import SimpleNamespace
from unittest.mock import Mock

from test_tutor import PROFILE, api
from backend.tutor_engine import TutorError


def test_interface_preference_preserves_course_and_chat(api):
    client, service = api
    profile = service.db.rows['profiles'][0]
    profile.update(app_lang_code='hu')
    before = dict(profile)
    sessions = [dict(row) for row in service.db.rows['chat_sessions']]
    response = client.post('/api/profile/interface-language', json={
        'profile_id': PROFILE, 'app_language': 'en'})
    assert response.status_code == 200
    assert response.json() == {'app_language': 'en'}
    assert profile == {**before, 'app_lang_code': 'en'}
    assert service.db.rows['chat_sessions'] == sessions
    assert service.db.writes == [('profiles', 'update')]
    service.db.rpc.assert_not_called()


def test_interface_preference_validates_locale_and_unknown_fields(api):
    client, service = api
    for payload in [
        {'profile_id': PROFILE, 'app_language': 'xx'},
        {'profile_id': PROFILE, 'app_language': 'en', 'unknown_setting': 999},
    ]:
        assert client.post('/api/profile/interface-language', json=payload).status_code == 422
    assert not service.db.writes


def test_interface_preference_requires_owner(api, monkeypatch):
    client, service = api
    monkeypatch.setenv('AUTH_REQUIRED', 'true')
    payload = {'profile_id': PROFILE, 'app_language': 'en'}
    assert client.post('/api/profile/interface-language', json=payload).status_code == 401
    database = Mock()
    database.auth.get_user.return_value = SimpleNamespace(user=SimpleNamespace(id='other'))
    monkeypatch.setattr('backend.api.get_database', lambda: database)
    assert client.post('/api/profile/interface-language', json=payload,
                       headers={'Authorization': 'Bearer test'}).status_code == 403
    assert not service.db.writes
    database.auth.get_user.return_value = SimpleNamespace(user=SimpleNamespace(id=PROFILE))
    assert client.post('/api/profile/interface-language', json=payload,
                       headers={'Authorization': 'Bearer test'}).status_code == 200


def test_interface_preference_missing_profile(api):
    client, service = api
    service.profile.side_effect = TutorError(404, 'Missing profile')
    assert client.post('/api/profile/interface-language', json={
        'profile_id': PROFILE, 'app_language': 'en'}).status_code == 404
    assert not service.db.writes
