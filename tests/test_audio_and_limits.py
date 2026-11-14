import json
import io
import wave
from types import SimpleNamespace
from unittest.mock import Mock

import pytest

from backend.usage_limits import UsageLimiter
from backend.tutor_engine import TutorError, TutorService, generate_reply
from test_tutor import MemoryDB, fixture_db, ai_client, PROFILE, SESSION, REQUEST, REPLY, api


def test_teacher_has_hard_200_token_cap_and_bounded_input():
    client = ai_client()
    history = [{"role": "user", "content": "x" * 1200} for _ in range(100)]
    generate_reply(client, "gpt-4o-mini", "Teach English", history, "Hi")
    arguments = client.chat.completions.create.call_args.kwargs
    assert arguments["max_tokens"] == 200
    assert len(arguments["messages"]) <= 42
    assert sum(len(m["content"]) for m in arguments["messages"]) < 17000


def test_limiter_rejects_extra_paid_requests():
    limiter = UsageLimiter(count=2)
    limiter.claim("profile")
    limiter.claim("profile")
    with pytest.raises(TutorError) as exc:
        limiter.claim("profile")
    assert exc.value.status_code == 429


def test_optional_auth_blocks_unauthenticated_public_requests(api, monkeypatch):
    monkeypatch.setenv("AUTH_REQUIRED", "true")
    client, service = api
    response = client.post("/api/chat", json={"profile_id": PROFILE, "request_id": REQUEST})
    assert response.status_code == 401
    service.chat.assert_not_called()


def test_auth_cannot_access_another_profile(api, monkeypatch):
    import backend.api as fastapi_server
    db = SimpleNamespace(auth=SimpleNamespace(get_user=lambda token: SimpleNamespace(
        user=SimpleNamespace(id="someone-else"))))
    monkeypatch.setattr(fastapi_server, "get_database", lambda: db)
    client, service = api
    response = client.get(f"/api/dashboard/{PROFILE}", headers={"Authorization": "Bearer test-token"})
    assert response.status_code == 403
    service.dashboard.assert_not_called()


def test_speech_rejects_arbitrary_text_before_calling_provider(api):
    client, service = api
    service.db = fixture_db()
    service.client = ai_client()
    response = client.post("/api/speech", json={"profile_id": PROFILE, "session_id": SESSION,
                                              "text": "Read this unrelated essay"})
    assert response.status_code == 422
    service.client.audio.speech.create.assert_not_called()


def test_saved_teacher_message_can_be_played(api):
    client, service = api
    service.db = fixture_db()
    service.db.rows["messages"] = [{"id": "1", "session_id": SESSION, "role": "assistant", "content": "Hello"}]
    service.client = ai_client()
    service.client.audio.speech.create.return_value.content = b"fake-mp3"
    response = client.post("/api/speech", json={"profile_id": PROFILE, "session_id": SESSION, "text": "Hello"})
    assert response.status_code == 200
    assert response.content == b"fake-mp3"
    assert response.headers["content-type"] == "audio/mpeg"


def test_transcription_accepts_small_wav_file(api):
    client, service = api
    service.client = ai_client()
    service.client.audio.transcriptions.create.return_value.text = " Hello "
    buffer = io.BytesIO()
    with wave.open(buffer, 'wb') as recording:
        recording.setnchannels(1)
        recording.setsampwidth(2)
        recording.setframerate(16000)
        recording.writeframes(b'\0\0' * 16000)
    response = client.post("/api/transcribe", data={"profile_id": PROFILE},
                           files={"file": ("speech.wav", buffer.getvalue(), "audio/wav")})
    assert response.status_code == 200 and response.json() == {"text": "Hello"}


def test_corrupt_or_overlong_audio_cannot_reach_paid_api(api):
    client, service = api
    service.client = ai_client()
    for data in [b'RIFFfakeWAVE', b'not audio']:
        assert client.post('/api/transcribe', data={'profile_id': PROFILE},
            files={'file': ('speech.wav', data, 'audio/wav')}).status_code == 422
    buffer = io.BytesIO()
    with wave.open(buffer, 'wb') as recording:
        recording.setnchannels(1)
        recording.setsampwidth(2)
        recording.setframerate(16000)
        recording.writeframes(b'\0\0' * 16000 * 17)
    assert client.post('/api/transcribe', data={'profile_id': PROFILE},
        files={'file': ('speech.wav', buffer.getvalue(), 'audio/wav')}).status_code == 413
    service.client.audio.transcriptions.create.assert_not_called()
    service.db.rpc.assert_not_called()


def test_transcription_forwards_only_validated_pcm_frames():
    from backend.audio_validation import validate_recording
    buffer = io.BytesIO()
    with wave.open(buffer, 'wb') as recording:
        recording.setnchannels(1); recording.setsampwidth(2); recording.setframerate(16000)
        recording.writeframes(b'\0\0' * 16000)
    canonical = validate_recording(buffer.getvalue() + b'untrusted trailing chunks' * 100)
    assert b'untrusted' not in canonical
    with wave.open(io.BytesIO(canonical), 'rb') as recording:
        assert recording.getnframes() / recording.getframerate() == 1


def test_dashboard_returns_locked_nodes_from_backend():
    db = fixture_db()
    db.rows["chapters"].append({"id": 4, "title": "Advanced", "level": "A2", "target_lang_code": "en", "order_index": 3})
    db.rows["lessons"].append({"id": 4, "title": "Advanced", "chapter_id": 4, "order_index": 1,
                              "lesson_type": "interactive", "is_level_exam": False})
    result = TutorService(db, None).dashboard(PROFILE)
    assert result["levels"][0]["lessons"][0]["status"] == "available"
    assert result["levels"][0]["lessons"][1]["status"] == "locked"
    assert result["levels"][1]["status"] == "locked"


