import copy
import json
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from postgrest.exceptions import APIError

from backend.dependencies import get_tutor
from backend.api import app
from tools.seed_database import seed_database
from backend.tutor_engine import TutorError, TutorService, build_prompt, clean_legacy_text, generate_reply


PROFILE = str(uuid4())
SESSION = str(uuid4())
REQUEST = str(uuid4())
REPLY = {"text": "How are you?", "mistakes": [], "reviews": [],
         "lesson_complete": False, "score": None, "assessed_level": None}


class MemoryQuery:
    def __init__(self, db, table):
        self.db, self.table = db, table
        self.filters, self.orders, self.limit_value = [], [], None
        self.operation, self.payload = "select", None
        self.columns = None
        self.offset = 0

    def select(self, *args):
        if args and args[0] != "*":
            self.columns = args[0].split(",")
        return self

    def eq(self, field, value):
        self.filters.append(lambda r: r.get(field) == value)
        return self

    def lte(self, field, value):
        self.filters.append(lambda r: r.get(field) <= value)
        return self

    def gt(self, field, value):
        self.filters.append(lambda r: r.get(field) > value)
        return self

    def order(self, field, desc=False):
        self.orders.append((field, desc))
        return self

    def limit(self, value):
        self.limit_value = value
        return self

    def range(self, start, end):
        self.offset, self.limit_value = start, end - start + 1
        return self

    def insert(self, payload):
        self.operation, self.payload = "insert", payload
        return self

    def update(self, payload):
        self.operation, self.payload = "update", payload
        return self

    def execute(self):
        rows = [r for r in self.db.rows.get(self.table, []) if all(f(r) for f in self.filters)]
        if self.operation == "insert":
            row = dict(self.payload)
            row.setdefault("id", max([r["id"] for r in self.db.rows.get(self.table, [])] + [0]) + 1)
            self.db.rows.setdefault(self.table, []).append(row)
            self.db.writes.append((self.table, self.operation))
            return SimpleNamespace(data=[row])
        if self.operation == "update":
            for row in rows:
                row.update(self.payload)
            self.db.writes.append((self.table, self.operation))
        for field, descending in reversed(self.orders):
            rows.sort(key=lambda r: r[field], reverse=descending)
        if self.limit_value is not None:
            rows = rows[self.offset:self.offset+self.limit_value]
        if self.columns:
            rows = [{k: r[k] for k in self.columns if k in r} for r in rows]
        return SimpleNamespace(data=copy.deepcopy(rows))


class MemoryDB:
    def __init__(self, rows=None):
        self.rows = copy.deepcopy(rows or {})
        self.writes = []
        self.rpc = Mock()

    def table(self, name):
        return MemoryQuery(self, name)


def ai_client(reply=None, finish_reason="stop", refusal=None):
    client = Mock()
    client.chat.completions.create.return_value = SimpleNamespace(choices=[SimpleNamespace(
        finish_reason=finish_reason,
        message=SimpleNamespace(content=json.dumps(reply or REPLY), refusal=refusal))])
    return client


def fixture_db(level="A1"):
    return MemoryDB({
        "profiles": [{"id": PROFILE, "current_level": level, "username": "Student",
                      "native_lang_code": "hu", "target_lang_code": "en"}],
        "chapters": [{"id": 1, "title": "First chapter", "level": "A1", "target_lang_code": "en", "order_index": 1},
                     {"id": 2, "title": "Second chapter", "level": "A1", "target_lang_code": "en", "order_index": 2},
                     {"id": 3, "title": "Placement", "level": "ONBOARDING", "target_lang_code": "en", "order_index": 0}],
        "lessons": [{"id": 1, "chapter_id": 1, "title": "First", "order_index": 1,
                     "passing_score": 80, "system_prompt": "Teach {target_language} to {native_language}.",
                     "lesson_type": "interactive"},
                    {"id": 2, "chapter_id": 2, "title": "Second", "order_index": 1,
                     "passing_score": 80, "system_prompt": "Teach {target_language}.",
                     "lesson_type": "interactive"},
                    {"id": 3, "chapter_id": 3, "title": "Placement", "order_index": 1,
                     "passing_score": 0, "system_prompt": "Assess {target_language}.",
                     "lesson_type": "placement_test"}],
        "languages": [{"code": "hu", "name_en": "Hungarian"}, {"code": "en", "name_en": "English"}],
        "chat_sessions": [{"id": SESSION, "profile_id": PROFILE, "lesson_id": 1,
                           "status": "active", "revision": 0}],
    })


@pytest.fixture
def api(monkeypatch):
    from backend.api import limiter
    limiter.events.clear()
    monkeypatch.setenv('AUTH_REQUIRED', 'false')
    service = Mock(spec=TutorService)
    service.db = fixture_db()
    service.db.rows['schema_releases'] = [{'id': 9}]
    app.dependency_overrides[get_tutor] = lambda: service
    with TestClient(app) as client:
        yield client, service
    app.dependency_overrides.clear()


def test_dashboard_keeps_missing_profile_404(api):
    client, service = api
    service.dashboard.side_effect = TutorError(404, "Felhasználó nem található.")
    assert client.get(f"/api/dashboard/{PROFILE}").status_code == 404


def test_null_level_dashboard_uses_onboarding():
    result = TutorService(fixture_db(None), None).dashboard(PROFILE)
    assert result["unlocked_level"] == "ONBOARDING"
    assert result["profile"]["current_level"] == "ONBOARDING"
    assert result["next_lesson"]["id"] == 3


def test_new_account_dashboard_allows_beginner_without_placement_content():
    db = fixture_db(None)
    db.rows['chapters'] = [row for row in db.rows['chapters'] if row['level'] != 'ONBOARDING']
    result = TutorService(db, None).dashboard(PROFILE)
    assert result['profile']['current_level'] == 'ONBOARDING'
    assert result['next_lesson'] is None
    assert result['levels'][0]['level'] == 'A1'


def test_lessons_continue_across_chapters():
    db = fixture_db()
    db.rows["user_progress"] = [{"profile_id": PROFILE, "lesson_id": 1, "passed": True}]
    assert TutorService(db, None).next_lesson(db.rows["profiles"][0])["id"] == 2


def test_completed_level_is_not_silently_promoted():
    db = fixture_db()
    db.rows["user_progress"] = [{"profile_id": PROFILE, "lesson_id": n, "passed": True} for n in (1, 2)]
    assert TutorService(db, None).dashboard(PROFILE)["next_lesson"] is None
    assert db.rows["profiles"][0]["current_level"] == "A1"


def test_prompt_resolves_languages_and_enforces_turns():
    db = fixture_db()
    prompt = build_prompt(db.rows["profiles"][0], db.rows["lessons"][0],
                          {"hu": "Hungarian", "en": "English"}, [], ["A1"])
    assert "{target_language}" not in prompt and "{native_language}" not in prompt
    assert "Hungarian" in prompt and "English" in prompt
    assert "WAIT" in prompt and "Never write the student's next line" in prompt


def test_mixed_legacy_tags_are_all_removed():
    assert clean_legacy_text("Well done. [MISTAKE: x -> y] [LEVEL_ASSESSED: A1] [LESSON_COMPLETE]") == "Well done."


@pytest.mark.parametrize("finish_reason,refusal", [("length", None), ("stop", "Refused")])
def test_truncated_or_refused_ai_is_rejected(finish_reason, refusal):
    with pytest.raises(TutorError):
        generate_reply(ai_client(finish_reason=finish_reason, refusal=refusal), "gpt-4o-mini", "", [], "Hi")


@pytest.mark.parametrize("changes", [
    {"lesson_complete": True, "score": None},
    {"lesson_complete": True, "score": 101},
    {"lesson_complete": True, "score": 50, "assessed_level": "A1"},
    {"lesson_complete": False, "score": 100},
    {"reviews": [{"mistake_id": 999, "correct": True}]},
    {"text": "Hi [LESSON_COMPLETE]"},
    {"text": ""},
])
def test_invalid_metadata_is_rejected(changes):
    with pytest.raises(TutorError):
        generate_reply(ai_client({**REPLY, **changes}), "gpt-4o-mini", "", [], "Hello")


def test_exam_cannot_finish_early():
    with pytest.raises(TutorError):
        generate_reply(ai_client({**REPLY, "lesson_complete": True, "score": 90}),
                       "gpt-4o-mini", "", [], "Answer", is_level_exam=True, answered_turns=9)


def test_valid_correction_and_review_are_separate_from_spoken_text():
    reply = {**REPLY, "text": "Magyar magyarázat. What did you do?",
             "mistakes": [{"wrong_sentence": "I goes", "corrected_sentence": "I go", "grammar_rule": "Agreement"}],
             "reviews": [{"mistake_id": 1, "correct": False}]}
    result = generate_reply(ai_client(reply), "gpt-4o-mini", "", [], "I goes home", review_ids=[1])
    assert result.text == reply["text"]
    assert result.mistakes[0].corrected_sentence == "I go"


@pytest.mark.parametrize("wrong,corrected", [
    ("he has borwn hair", "he has brown hair"),
    ("invented text", "fix"),
    ("", "yes"),
    ("yes", "yes"),
])
def test_unrelated_or_invalid_correction_does_not_block_acknowledgement(wrong, corrected):
    client = ai_client({**REPLY, "mistakes": [{
        "wrong_sentence": wrong, "corrected_sentence": corrected, "grammar_rule": "Spelling"}]})
    result = generate_reply(client, "gpt-4o-mini", "", [
        {"role": "user", "content": "he has borwn hair"}], "yes")
    assert result.text == REPLY["text"]
    assert result.mistakes == []
    assert not result.lesson_complete and result.score is None
    assert client.chat.completions.create.call_count == 1
    assert client.chat.completions.create.call_args.kwargs["max_tokens"] == 200


def test_invalid_correction_cannot_be_used_to_complete_lesson():
    client = ai_client({**REPLY, "lesson_complete": True, "score": 90, "mistakes": [{
        "wrong_sentence": "invented text", "corrected_sentence": "fix", "grammar_rule": "x"}]})
    with pytest.raises(TutorError):
        generate_reply(client, "gpt-4o-mini", "", [], "yes")


def test_chat_commits_acknowledgement_without_invented_mistake():
    db = fixture_db()
    client = ai_client({**REPLY, "mistakes": [{
        "wrong_sentence": "he has borwn hair", "corrected_sentence": "he has brown hair",
        "grammar_rule": "Spelling"}]})
    db.rpc.return_value.execute.return_value.data = {"text": REPLY["text"]}
    result = TutorService(db, client).chat(PROFILE, "yes", REQUEST, session_id=SESSION)
    assert result["text"] == REPLY["text"]
    name, params = next(call.args for call in db.rpc.call_args_list if call.args[0] == 'tutor_commit_turn')
    assert name == "tutor_commit_turn"
    assert params["p_input_text"] == "yes"
    assert params["p_reply"]["mistakes"] == []
    assert params["p_reply"]["lesson_complete"] is False
    assert client.chat.completions.create.call_count == 1


def test_ai_failure_does_not_commit_messages_or_progress():
    db = fixture_db()
    client = ai_client(finish_reason="length")
    service = TutorService(db, client)
    with pytest.raises(TutorError):
        service.chat(PROFILE, "Hello", REQUEST, SESSION)
    db.rpc.assert_not_called()
    assert not db.writes


def test_resume_does_not_call_ai():
    db = fixture_db()
    db.rows["messages"] = [{"session_id": SESSION, "id": "1", "created_at": "1",
                            "role": "assistant", "content": "Hello [MISTAKE: x -> y]"}]
    client = ai_client()
    result = TutorService(db, client).chat(PROFILE, None, REQUEST, SESSION)
    assert result["text"] == "Hello" and result["resumed"]
    client.chat.completions.create.assert_not_called()
    db.rpc.assert_not_called()


def test_repeated_request_returns_saved_result_before_ai_or_session_lookup():
    db = MemoryDB({"tutor_turns": [{"profile_id": PROFILE, "request_id": REQUEST,
                    "session_id": SESSION, "input_text": "Hello", "result": {"text": "Saved"}}]})
    client = ai_client()
    assert TutorService(db, client).chat(PROFILE, "Hello", REQUEST, SESSION) == {"text": "Saved"}
    client.chat.completions.create.assert_not_called()


def test_reusing_request_id_for_different_input_is_conflict():
    db = MemoryDB({"tutor_turns": [{"profile_id": PROFILE, "request_id": REQUEST,
                    "session_id": SESSION, "input_text": "Hello", "result": {"text": "Saved"}}]})
    with pytest.raises(TutorError) as error:
        TutorService(db, None).chat(PROFILE, "Different", REQUEST, SESSION)
    assert error.value.status_code == 409


def test_due_reviews_order_and_limit():
    db = fixture_db()
    db.rows["user_mistakes"] = [
        {"id": n, "profile_id": PROFILE, "wrong_sentence": "x", "corrected_sentence": "y",
         "grammar_rule": "g", "target_lang_code": "en", "mastered": mastered, "next_review_at": due, "created_at": str(n)}
        for n, mastered, due in [(1, False, "2000-01-01"), (2, False, "2000-01-01"),
                                 (3, True, "2000-01-01"), (4, False, "2999-01-01"),
                                 (5, False, "2001-01-01"), (6, False, "2002-01-01")]]
    context = TutorService(db, None).context(PROFILE, SESSION)
    assert [m["id"] for m in context["mistakes"]] == [2, 1, 5]


def test_exam_answer_count_excludes_greeting_and_counts_direct_first_message():
    db = fixture_db()
    db.rows["tutor_turns"] = [{"session_id": SESSION, "input_text": text}
                              for text in (None, "Answer one", "Answer two")]
    assert TutorService(db, None).context(PROFILE, SESSION)["answered_turns"] == 2
    db.rows["tutor_turns"] = [{"session_id": SESSION, "input_text": "Direct answer"}]
    assert TutorService(db, None).context(PROFILE, SESSION)["answered_turns"] == 1


def test_sql_migration_missing_has_actionable_503_without_leaking_secrets(api):
    client, service = api
    service.chat.side_effect = APIError({"code": "PGRST202", "message": "private details",
                                        "details": "secret", "hint": "hidden"})
    response = client.post("/api/chat", json={"profile_id": PROFILE, "request_id": REQUEST})
    assert response.status_code == 503
    assert "secret" not in response.text and "private" not in response.text


@pytest.mark.parametrize("message", ["", "   ", "x" * 4001])
def test_api_rejects_empty_or_oversized_input(api, message):
    client, service = api
    assert client.post("/api/chat", json={"profile_id": PROFILE, "request_id": REQUEST,
                                          "message": message}).status_code == 422
    service.chat.assert_not_called()


def test_chat_route_uses_shared_engine(api):
    client, service = api
    service.chat.return_value = {"text": "Hello"}
    response = client.post("/api/chat", json={"profile_id": PROFILE, "request_id": REQUEST,
                                              "session_id": SESSION, "message": " Hello "})
    assert response.status_code == 200
    service.chat.assert_called_once_with(PROFILE, "Hello", REQUEST, SESSION)


def test_seed_is_repeatable_and_preserves_custom_prompts_and_progress(tmp_path):
    lesson = {"lesson_id": "X1", "cefr_level": "A1", "topic": "Greeting", "scenario_context": "Cafe",
              "grammar_focus": ["present"], "vocabulary_focus": ["hi"],
              "functional_objectives": ["greet"], "success_criteria": "greet naturally"}
    (tmp_path / "lessons.json").write_text(json.dumps([lesson]), encoding="utf-8")
    manifest = {"target_lang_code": "en", "lesson_passing_score": 80, "exam_passing_score": 85,
                "levels": [{"level": "A1", "file": "lessons.json"}]}
    path = tmp_path / "manifest.json"
    path.write_text(json.dumps(manifest), encoding="utf-8")
    db = MemoryDB({"languages": [{"code": "en", "name_en": "English"}],
        "chapters": [{"id": 9, "target_lang_code": "en", "level": "A1", "order_index": 1}],
        "lessons": [{"id": 99, "chapter_id": 9, "order_index": 1, "system_prompt": "CUSTOM"}],
        "user_progress": [{"id": 1, "profile_id": PROFILE, "lesson_id": 99, "passed": True}]})
    seed_database(db, path)
    seed_database(db, path)
    assert len(db.rows["chapters"]) == 2 and len(db.rows["lessons"]) == 3
    assert db.rows["lessons"][0]["id"] == 99
    assert db.rows["lessons"][0]["system_prompt"] == "CUSTOM"
    assert db.rows["user_progress"][0]["passed"]
    assert db.rows["lessons"][1]["is_level_exam"]
    assert db.rows["lessons"][1]["passing_score"] == 85


def test_missing_curriculum_file_does_not_partially_write(tmp_path):
    path = tmp_path / "manifest.json"
    path.write_text(json.dumps({"target_lang_code": "en", "levels": [{"level": "A1", "file": "missing.json"}]}))
    db = MemoryDB()
    with pytest.raises(FileNotFoundError):
        seed_database(db, path)
    assert not db.writes


def test_entire_project_curriculum_seeds_103_lessons_and_five_exams_once():
    db = MemoryDB({"languages": [{"code": "en", "name_en": "English"}]})
    seed_database(db)
    writes = len(db.writes)
    seed_database(db)
    assert len(db.writes) == writes
    assert len(db.rows["chapters"]) == 6
    assert len(db.rows["lessons"]) == 109
    assert sum(l.get('lesson_type') == 'placement_test' for l in db.rows['lessons']) == 1
    assert sum(l["is_level_exam"] for l in db.rows["lessons"]) == 5


def test_fastapi_openapi_exposes_chat_and_onboarding(api):
    client, _ = api
    document = client.get("/openapi.json").json()
    assert "/api/chat" in document["paths"]
    assert "/api/onboarding" in document["paths"]
    assert "request_id" in document["components"]["schemas"]["ChatRequest"]["required"]
