"""Local development REST API. See README.md before exposing it publicly."""
import logging
import os
from pathlib import Path
from typing import Literal
from uuid import UUID
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, Request, UploadFile, File, Form, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response
from openai import OpenAIError
from postgrest.exceptions import APIError
from pydantic import BaseModel, ConfigDict, Field, field_validator

from backend.dependencies import get_database, get_tutor
from backend.tutor_engine import TutorError, TutorService
from backend.usage_limits import UsageLimiter
from backend.journal_service import JournalService
from backend.auth_service import auth_client, session_response, ensure_profile

@asynccontextmanager
async def lifespan(app):
    from backend.runtime_settings import validate_runtime
    validate_runtime()
    yield


app = FastAPI(title="AI Language Tutor API", version="3.0", lifespan=lifespan)
origins = [o.strip() for o in os.getenv("CORS_ORIGINS", "*").split(",") if o.strip()]
app.add_middleware(CORSMiddleware, allow_origins=origins,
                   allow_credentials="*" not in origins,
                   allow_methods=["GET", "POST", "DELETE"], allow_headers=["Content-Type", "Authorization"])
limiter = UsageLimiter()
auth_limiter = UsageLimiter(count=6)


def authorize_profile(profile_id, request):
    header = request.headers.get("authorization", "")
    required = os.getenv("AUTH_REQUIRED", "true").lower() == "true"
    if not header:
        if required:
            raise TutorError(401, "Bejelentkezés szükséges.")
        return
    if not header.startswith("Bearer "):
        raise TutorError(401, "Érvénytelen bejelentkezés.")
    try:
        user = get_database().auth.get_user(header[7:]).user
    except Exception as exc:
        raise TutorError(401, "A bejelentkezés lejárt.") from exc
    if not user or str(user.id) != str(profile_id):
        raise TutorError(403, "Ehhez a profilhoz nincs hozzáférésed.")


def claim_ai_request(profile_id, request):
    authorize_profile(profile_id, request)
    limiter.claim("profile:" + str(profile_id))
    limiter.claim("ip:" + (request.client.host if request.client else "unknown"))


class ChatRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    profile_id: UUID
    request_id: UUID
    session_id: UUID | None = None
    message: str | None = Field(default=None, max_length=1200)

    @field_validator("message")
    @classmethod
    def validate_message(cls, value):
        if value is not None:
            value = value.strip()
            if not value:
                raise ValueError("Az üzenet nem lehet üres. Kezdéshez küldj null értéket.")
        return value


class OnboardingRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    profile_id: UUID
    mode: Literal["placement", "beginner"]


class LanguageSettingsRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    profile_id: UUID
    native_language: Literal['hu', 'en', 'ro', 'es', 'fr', 'de']
    target_language: Literal['en'] = 'en'
    app_language: Literal['hu', 'en', 'ro', 'es', 'fr', 'de']
    expected_target: Literal['en'] = 'en'


class InterfaceLanguageRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    profile_id: UUID
    app_language: Literal['hu', 'en', 'ro', 'es', 'fr', 'de']


@app.post('/api/profile/interface-language')
def set_interface_language(body: InterfaceLanguageRequest, request: Request,
                          tutor: TutorService = Depends(get_tutor)):
    # Interface preference never resets a course, closes chat, or calls the model.
    authorize_profile(body.profile_id, request)
    tutor.profile(str(body.profile_id))
    tutor.db.table('profiles').update({'app_lang_code': body.app_language}).eq(
        'id', str(body.profile_id)).execute()
    return {'app_language': body.app_language}


@app.post('/api/profile/languages')
def set_languages(body: LanguageSettingsRequest, request: Request,
                  tutor: TutorService = Depends(get_tutor)):
    authorize_profile(body.profile_id, request)
    if not tutor.db.table('schema_releases').select('id').eq('id', 9).limit(1).execute().data:
        raise TutorError(503, 'A 9-es adatbázisséma szükséges: futtasd a database/schema.sql és database/functions.sql fájlokat.')
    return tutor.db.rpc('tutor_set_languages', {'p_profile_id': str(body.profile_id),
        'p_native': body.native_language, 'p_target': body.target_language,
        'p_app': body.app_language, 'p_expected_target': body.expected_target}).execute().data


@app.exception_handler(TutorError)
def tutor_error_handler(request, exc):
    return JSONResponse(status_code=exc.status_code, content={"detail": str(exc)})


@app.exception_handler(APIError)
def database_error_handler(request, exc):
    if exc.code == "PT409":
        status, detail = 409, "A beszélgetés állapota megváltozott. Töltsd újra, majd próbáld újra."
    elif exc.code == "PT404":
        status, detail = 404, "A kért adat nem található."
    elif exc.code == "PT422":
        status, detail = 422, "Érvénytelen beállítás."
    elif exc.code in ("PGRST202", "PGRST205", "42703"):
        status, detail = 503, "Az adatbázis frissítése szükséges: futtasd a projekt SQL-migrációját."
    else:
        status, detail = 500, "Adatbázisművelet sikertelen."
    logging.error("Database operation failed (code=%s)", exc.code)
    return JSONResponse(status_code=status, content={"detail": detail})


@app.exception_handler(OpenAIError)
def ai_error_handler(request, exc):
    logging.error("OpenAI request failed (%s)", type(exc).__name__)
    return JSONResponse(status_code=502, content={"detail": "Az AI szolgáltatás nem elérhető. Próbáld újra."})


@app.get("/")
def root():
    return {"status": "ok", "message": "AI Language Tutor API fut!"}


@app.get('/health/live')
def live():
    return {'status': 'ok'}


@app.get('/health/ready')
def ready():
    try:
        rows = get_database().table('schema_releases').select('id').eq('id', 9).limit(1).execute().data
        if not rows:
            raise ValueError('Migration missing')
    except Exception:
        return JSONResponse(status_code=503, content={'status': 'unavailable', 'required_migration': 9})
    return {'status': 'ready'}


@app.get("/api/dashboard/{profile_id}")
def get_dashboard(profile_id: UUID, request: Request, tutor: TutorService = Depends(get_tutor)):
    authorize_profile(profile_id, request)
    return tutor.dashboard(str(profile_id))


@app.post("/api/chat")
def chat(body: ChatRequest, request: Request, tutor: TutorService = Depends(get_tutor)):
    claim_ai_request(body.profile_id, request)
    return tutor.chat(str(body.profile_id), body.message, str(body.request_id),
                      str(body.session_id) if body.session_id else None)


@app.get('/api/sessions/{profile_id}')
def sessions(profile_id: UUID, request: Request, offset: int = Query(0, ge=0),
             limit: int = Query(20, ge=1, le=50), tutor: TutorService = Depends(get_tutor)):
    authorize_profile(profile_id, request)
    return tutor.sessions(str(profile_id), offset, limit)


@app.get('/api/sessions/{profile_id}/{session_id}')
def transcript(profile_id: UUID, session_id: UUID, request: Request,
               offset: int = Query(0, ge=0), limit: int = Query(100, ge=1, le=200),
               tutor: TutorService = Depends(get_tutor)):
    authorize_profile(profile_id, request)
    return tutor.transcript(str(profile_id), str(session_id), offset, limit)


@app.post("/api/onboarding")
def onboarding(body: OnboardingRequest, request: Request, tutor: TutorService = Depends(get_tutor)):
    authorize_profile(body.profile_id, request)
    return tutor.onboard(str(body.profile_id), body.mode)


@app.post("/api/transcribe")
async def transcribe(request: Request, profile_id: UUID = Form(...), file: UploadFile = File(...),
                     tutor: TutorService = Depends(get_tutor)):
    from starlette.concurrency import run_in_threadpool
    # The token check is a blocking network call; keep it off the event loop.
    await run_in_threadpool(claim_ai_request, profile_id, request)
    await run_in_threadpool(tutor.profile, str(profile_id))
    try:
        data = await file.read(10 * 1024 * 1024 + 1)
    finally:
        await file.close()
    if not data or len(data) > 10 * 1024 * 1024:
        raise TutorError(413, "A hangfelvétel legfeljebb 10 MB lehet.")
    mime = file.content_type or "application/octet-stream"
    if mime not in {"audio/wav", "audio/x-wav"}:
        raise TutorError(415, "PCM WAV hangfelvételt küldj. Az alkalmazás ezt automatikusan előállítja.")
    from backend.audio_validation import validate_recording
    data = validate_recording(data)
    def action():
        result = tutor.client.audio.transcriptions.create(model=os.getenv("STT_MODEL", "whisper-1"),
            file=(Path(file.filename or "speech.wav").name, data, mime))
        return {"text": result.text.strip()}
    return await run_in_threadpool(action)


class SpeechRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    profile_id: UUID
    session_id: UUID
    text: str = Field(min_length=1, max_length=1200)


@app.post("/api/speech")
def speech(body: SpeechRequest, request: Request, tutor: TutorService = Depends(get_tutor)):
    claim_ai_request(body.profile_id, request)
    sessions = tutor.db.table("chat_sessions").select("id").eq(
        "id", str(body.session_id)).eq("profile_id", str(body.profile_id)).execute().data
    if not sessions:
        raise TutorError(404, "Beszélgetés nem található.")
    messages = tutor.db.table("messages").select("id").eq("session_id", str(body.session_id)).eq(
        "role", "assistant").eq("content", body.text).limit(1).execute().data
    if not messages:
        raise TutorError(422, "Csak a tanár mentett válasza olvasható fel.")
    def action():
        audio = tutor.client.audio.speech.create(model=os.getenv("TTS_MODEL", "tts-1"),
                                               voice=os.getenv("TTS_VOICE", "nova"), input=body.text)
        return audio.content
    return Response(content=action(), media_type="audio/mpeg")


class JournalRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    profile_id: UUID
    request_id: UUID
    content: str = Field(min_length=1, max_length=1200)

    @field_validator('content')
    @classmethod
    def nonempty(cls, value):
        if not value.strip():
            raise ValueError('A napló nem lehet üres.')
        return value.strip()


class JournalDiscussionRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    profile_id: UUID
    request_id: UUID
    entry_id: UUID
    message: str = Field(min_length=1, max_length=600)

    @field_validator('message')
    @classmethod
    def nonempty(cls, value):
        if not value.strip():
            raise ValueError('Az üzenet nem lehet üres.')
        return value.strip()


@app.get('/api/journal/{profile_id}')
def journal_list(profile_id: UUID, request: Request, tutor: TutorService = Depends(get_tutor)):
    authorize_profile(profile_id, request)
    return JournalService(tutor).summary(str(profile_id))


@app.post('/api/journal')
def journal(body: JournalRequest, request: Request, tutor: TutorService = Depends(get_tutor)):
    claim_ai_request(body.profile_id, request)
    return JournalService(tutor).journal(str(body.profile_id), str(body.request_id), body.content)


@app.post('/api/journal/discuss')
def journal_discuss(body: JournalDiscussionRequest, request: Request, tutor: TutorService = Depends(get_tutor)):
    claim_ai_request(body.profile_id, request)
    return JournalService(tutor).discuss(str(body.profile_id), str(body.entry_id), str(body.request_id), body.message)


@app.delete('/api/journal/{entry_id}')
def journal_delete(entry_id: UUID, profile_id: UUID, request: Request, tutor: TutorService = Depends(get_tutor)):
    authorize_profile(profile_id, request)
    return JournalService(tutor).delete(str(profile_id), str(entry_id))


class LoginRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    email: str = Field(min_length=3, max_length=254)
    password: str = Field(min_length=1, max_length=128)


class RegisterRequest(LoginRequest):
    password: str = Field(min_length=8, max_length=128)
    username: str = Field(min_length=2, max_length=24)


class RefreshRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    refresh_token: str = Field(min_length=1, max_length=8192)


def auth_limit(request):
    auth_limiter.claim('auth:' + (request.client.host if request.client else 'unknown'))


@app.post('/api/auth/login')
def login(body: LoginRequest, request: Request):
    auth_limit(request)
    try:
        response = auth_client().auth.sign_in_with_password({'email': body.email, 'password': body.password})
    except Exception as exc:
        raise TutorError(401, 'Nem sikerült bejelentkezni. Ellenőrizd az adatokat és az e-mail megerősítését.') from exc
    ensure_profile(get_database(), response.user, (response.user.user_metadata or {}).get('username', 'Tanuló'))
    return session_response(response)


@app.post('/api/auth/register')
def register(body: RegisterRequest, request: Request):
    auth_limit(request)
    try:
        response = auth_client().auth.sign_up({'email': body.email, 'password': body.password,
            'options': {'data': {'username': body.username}}})
    except Exception as exc:
        raise TutorError(400, 'A regisztráció nem sikerült. Ellenőrizd az adatokat, vagy próbálj bejelentkezni.') from exc
    if response.session:
        ensure_profile(get_database(), response.user, body.username)
    return session_response(response)


@app.post('/api/auth/refresh')
def refresh_auth(body: RefreshRequest, request: Request):
    auth_limit(request)
    try:
        return session_response(auth_client().auth.refresh_session(body.refresh_token))
    except Exception as exc:
        raise TutorError(401, 'A bejelentkezés lejárt. Jelentkezz be újra.') from exc


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=os.getenv("API_HOST", "127.0.0.1"),
                port=int(os.getenv("API_PORT", "8000")))
