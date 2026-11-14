"""Produce a local curriculum coverage report; never infer teacher approval."""
import argparse
import json
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
from tools.seed_database import load_course


def audit():
    result=[]
    for path in [ROOT/'curriculum/manifest.json']:
        manifest,courses=load_course(path)
        for entry,lessons in courses:
            rows=[]
            for index,lesson in enumerate(lessons):
                plan=lesson.get('teaching_plan',{})
                rows.append({'id':lesson['lesson_id'],'topic':lesson['topic'],
                    'previous_lesson':lessons[index-1]['lesson_id'] if index else None,
                    'goals':lesson['functional_objectives'],
                    'grammar':lesson['grammar_focus'],'vocabulary':lesson['vocabulary_focus'],
                    'review_status':plan.get('review_status','draft'),
                    'tracked_tasks':len(plan.get('practice_tasks',[])),
                    'reading_material':bool(plan.get('source_text')),
                    'listening_assessment':False,
                    'listening_practice':False})
            result.append({'language':manifest['target_lang_code'],'level':entry['level'],
                'coverage_note':manifest.get('coverage','Authored pilot; completeness not teacher-verified.'),
                'teacher_reviewed':all(r['review_status']=='teacher_reviewed' for r in rows),
                'lessons':rows})
    return result


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--output',type=Path,default=ROOT/'.cache/course_audit.json')
    parser.add_argument('--require-reviewed',action='store_true')
    args=parser.parse_args()
    result=audit()
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(f"{len(result)} language/level groups audited locally; no database or AI calls")
    if args.require_reviewed and not all(row['teacher_reviewed'] for row in result):
        print('Release gate: teacher review is still required.')
        sys.exit(1)
