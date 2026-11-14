"""Non-destructive, repeatable curriculum import (IDs and custom prompts are preserved)."""
import argparse
import json
from pathlib import Path

from backend.dependencies import get_database
from backend.curriculum import render_plan, validate_plan, LANGUAGES
from backend.placement import placement_prompt

ROOT = Path(__file__).resolve().parents[1]


def lesson_prompt(lesson, level):
    prompt = f"""You are an expert English tutor. The preferred explanation language is
{{native_language}} and they are learning {{target_language}} at {level} level.
SCENARIO: {lesson['scenario_context']}
Grammar: {', '.join(lesson['grammar_focus'])}
Vocabulary: {', '.join(lesson['vocabulary_focus'])}
Objectives: {', '.join(lesson['functional_objectives'])}
Success criteria: {lesson['success_criteria']}
Stay in your assigned role. Never supply or invent the student's turns.
Ask one question, stop, and wait for their input.
Only complete this lesson when the student's answers demonstrate the criteria.
"""
    if lesson.get('teaching_plan'):
        prompt += render_plan(lesson['teaching_plan'])
    else:
        prompt += ('Teach one useful expression with meaning and a model before asking for use. '
                   'Move from supported to independent practice, then test in a changed context. '
                   'Do not invent missing reading or listening sources. Accept valid alternative expressions. '
                   'Treat CEFR as a practice level, not certification.\n')
    return prompt


def exam_prompt(lessons, level):
    objectives = [f"{l['topic']}: {'; '.join(l['functional_objectives'])}" for l in lessons]
    return f"""You assess English practice at {level} level. Explanation language: {{native_language}}.
Assess all curriculum areas listed below through short
questions, one at a time. This is an exam, not a lesson. Do not give the answer
before the student tries. Offer brief corrections after each answer.
Ask at least 10 independent questions, covering a representative range of the
curriculum; include earlier weak areas. Keep a record of correct and attempted
answers in your conversation. End only after at least 10 answers. Compute score
as round(100 * fully_correct_answers / attempted_answers). A corrected retry does
not replace the original score. Use the structured completion and score fields.
Test communicative tasks, not just named grammar forms. Accept correct alternative
expressions. Do not infer pronunciation, listening or a certified CEFR level from text.
Curriculum:\n{chr(10).join(objectives)}
"""


def load_course(manifest_path):
    manifest_path = Path(manifest_path)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest['target_lang_code'] != 'en':
        raise ValueError('Only English courses are supported')
    # Validate the ENTIRE import before the first database write.
    courses = []
    for entry in manifest["levels"]:
        lessons = json.loads((manifest_path.parent / entry["file"]).read_text(encoding="utf-8"))
        if not lessons or len({l["lesson_id"] for l in lessons}) != len(lessons):
            raise ValueError(f"Invalid/duplicate lessons in {entry['file']}")
        for lesson in lessons:
            for field in ("topic", "scenario_context", "grammar_focus", "vocabulary_focus",
                          "functional_objectives", "success_criteria"):
                if not lesson.get(field):
                    raise ValueError(f"Missing {field} in {entry['file']}")
            if lesson["cefr_level"] != entry["level"]:
                raise ValueError(f"Level mismatch in {entry['file']}")
            if lesson.get('teaching_plan'):
                validate_plan(lesson['teaching_plan'], manifest['target_lang_code'])
            if len(lesson_prompt(lesson, entry['level'])) > 6100:
                raise ValueError(f"Lesson prompt exceeds safe budget: {lesson['lesson_id']}")
        if entry.get('include_exam', True) and len(exam_prompt(lessons, entry['level'])) > 6100:
            raise ValueError(f"Exam prompt exceeds safe budget: {entry['level']}")
        courses.append((entry, lessons))
    if len({entry['level'] for entry, _ in courses}) != len(courses):
        raise ValueError('Duplicate course level')
    return manifest, courses


def seed_database(db, manifest_path=ROOT / "curriculum/manifest.json", refresh_prompts=False):
    manifest, courses = load_course(manifest_path)
    target = manifest["target_lang_code"]
    languages = db.table("languages").select("name_en").eq("code", target).execute().data
    if not languages:
        raise ValueError("Add target language to languages first (run the SQL migration).")
    placements = db.table('chapters').select('*').eq('target_lang_code', 'en').eq('level', 'ONBOARDING').execute().data
    if len(placements) > 1:
        raise ValueError('Ambiguous placement chapter; resolve mapping before import')
    placement_lessons = (db.table('lessons').select('*').eq('chapter_id', placements[0]['id']).execute().data
                         if placements else [])
    if len(placement_lessons) > 1 or (placement_lessons and placement_lessons[0]['lesson_type'] != 'placement_test'):
        raise ValueError('Ambiguous placement lessons; resolve mapping before import')
    # Detect ambiguous mappings across the whole course before changing anything.
    for entry, lessons in courses:
        found = db.table('chapters').select('*').eq('target_lang_code', target).eq('level', entry['level']).execute().data
        if len(found) > 1:
            raise ValueError(f"Multiple {target}/{entry['level']} chapters")
        if found:
            rows = db.table('lessons').select('*').eq('chapter_id', found[0]['id']).execute().data
            orders = [r['order_index'] for r in rows if not r.get('is_level_exam')]
            if len(set(orders)) != len(orders) or sum(bool(r.get('is_level_exam')) for r in rows) > 1:
                raise ValueError(f"Ambiguous lesson mapping: {entry['level']}")
            if refresh_prompts and any(r['order_index'] < 1 or r['order_index'] > len(lessons)
                    for r in rows if not r.get('is_level_exam')):
                raise ValueError('Existing lesson outside manifest: explicit version mapping required')
            if refresh_prompts and any(r.get('title') != lessons[r['order_index']-1]['topic']
                    for r in rows if not r.get('is_level_exam') and 1 <= r['order_index'] <= len(lessons)):
                raise ValueError('Titles changed: explicit curriculum version mapping required; progress cannot be reused silently')
    for index, (entry, lessons) in enumerate(courses, 1):
        level = entry["level"]
        chapters = db.table("chapters").select("*").eq(
            "target_lang_code", target).eq("level", level).execute().data
        if len(chapters) > 1:
            raise ValueError(f"Multiple {target}/{level} chapters: specify curriculum mapping before import.")
        chapter = chapters[0] if chapters else db.table("chapters").insert({
            "target_lang_code": target, "level": level,
            "title": entry.get('title', f"{languages[0]['name_en']} {level} Course"), "order_index": index,
        }).execute().data[0]
        existing = db.table("lessons").select("*").eq("chapter_id", chapter["id"]).execute().data
        for order, lesson in enumerate(lessons, 1):
            matches = [l for l in existing if not l.get("is_level_exam") and l["order_index"] == order]
            if len(matches) > 1:
                raise ValueError(f"Duplicate lesson order {order} in {level}")
            payload = {"chapter_id": chapter["id"], "lesson_type": "interactive",
                       "title": lesson["topic"], "system_prompt": lesson_prompt(lesson, level),
                       "passing_score": manifest["lesson_passing_score"], "order_index": order,
                       "is_level_exam": False}
            if not matches:
                db.table("lessons").insert(payload).execute()
            elif refresh_prompts:
                db.table("lessons").update({"system_prompt": payload["system_prompt"]}).eq(
                    "id", matches[0]["id"]).execute()
        exams = [l for l in existing if l.get("is_level_exam")]
        if len(exams) > 1:
            raise ValueError(f"Multiple level exams in {level}")
        if not entry.get('include_exam', True):
            print(f"{target}/{level}: {len(lessons)} starter lessons ready; no full-level exam.")
            continue
        if exams and refresh_prompts:
            db.table('lessons').update({'system_prompt': exam_prompt(lessons, level)}).eq('id', exams[0]['id']).execute()
        if not exams:
            db.table("lessons").insert({
                "chapter_id": chapter["id"], "lesson_type": "interactive",
                "title": f"{level} Level Exam", "system_prompt": exam_prompt(lessons, level),
                "passing_score": manifest["exam_passing_score"],
                "order_index": max([len(lessons)] + [l["order_index"] for l in existing]) + 1,
                "is_level_exam": True,
            }).execute()
        print(f"{target}/{level}: curriculum ready; existing IDs and progress preserved.")
    chapter = placements[0] if placements else db.table('chapters').insert({
        'target_lang_code': 'en', 'level': 'ONBOARDING', 'title': 'English Placement', 'order_index': 0}).execute().data[0]
    if not placement_lessons:
        db.table('lessons').insert({'chapter_id': chapter['id'], 'title': 'English Placement',
            'lesson_type': 'placement_test', 'system_prompt': placement_prompt(),
            'passing_score': 0, 'order_index': 1, 'is_level_exam': False}).execute()
    elif refresh_prompts:
        db.table('lessons').update({'system_prompt': placement_prompt()}).eq('id', placement_lessons[0]['id']).execute()
    print('en/ONBOARDING: ten-question placement ready; existing ID preserved.')


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, default=ROOT / "curriculum/manifest.json")
    parser.add_argument("--refresh-prompts", action="store_true",
                        help="Explicitly replace existing curriculum prompts, preserving IDs")
    parser.add_argument('--check', action='store_true', help='Validate locally without database writes or API calls')
    args = parser.parse_args()
    if args.check:
        manifest, courses = load_course(args.manifest)
        print(f"{manifest['target_lang_code']}: {sum(len(rows) for _, rows in courses)} lessons validated; no cloud writes")
    else:
        seed_database(get_database(), args.manifest, args.refresh_prompts)
