"""Validated lesson plans. No API calls; course content is authored and versioned locally."""
import json

LANGUAGES = {'hu': 'Magyar', 'en': 'English', 'ro': 'Română',
             'es': 'Español', 'fr': 'Français', 'de': 'Deutsch'}
PLAN_MARKER = 'TEACHING_PLAN_V2'
MIN_ANSWERS = 8
TRACKED_MARKER = 'TEACHING_PLAN_V3'


def tracked_progress(turns):
    """Replay only sequential, persisted task evidence; legacy turns prove nothing."""
    index = 0
    for turn in turns:
        evidence = (turn.get('result') or {}).get('task_result')
        if (turn.get('input_text') is not None and isinstance(evidence, dict)
                and type(evidence.get('task_index')) is int
                and evidence['task_index'] == index and evidence.get('passed') is True):
            index += 1
    return index


def tracked_instruction(index, greeting=False, prompt=''):
    tasks = []
    models = []
    label = 'Lesson materials (examples are not student evidence):'
    if label in prompt:
        try:
            plan, _ = json.JSONDecoder().raw_decode(prompt.split(label, 1)[1].lstrip())
            tasks = plan.get('practice_tasks', [])
            models = plan.get('model', [])
        except (ValueError, AttributeError):
            pass
    focus = ''
    if len(tasks) == 8 and 0 <= index < 8:
        focus = '\nCURRENT TASK: ' + tasks[index]
        if index < 7:
            focus += '\nNEXT TASK ONLY IF CURRENT ANSWER SUCCEEDS: ' + tasks[index + 1]
    assessment = ''
    if index < 2:
        assessment = (
            '\nCOMPREHENSION ONLY: a correct native-language meaning or paraphrase PASSES. '
            'Accept informal synonyms and a correct translation of the whole model, even if '
            'the previous question asked about only part of it. Do not require a target-language reply, name, '
            'repetition or roleplay. If meaning is correct, task_passed=true NOW. '
            'Native meaning answers are not grammar mistakes. Evaluate the answer, not the next question.')
        if len(models) > index:
            assessment += '\nMODEL WHOSE MEANING/PURPOSE THE STUDENT IS ANSWERING: ' + models[index]
        if index == 0 and len(models) > 1:
            assessment += '\nOn success, teach this second model and ask its meaning/purpose: ' + models[1]
    return (f'\nTRACKED PRACTICE: current task index={index} (zero-based, 8 tasks). '
            'task_passed evaluates ONLY the latest answer to this task, never the next question. '
            'Acknowledge-only and skip requests do not pass independent tasks. Model repetition '
            'unrelated to the task is not mastery; correctly reusing a fixed phrase in the new task IS valid. '
            'If successful ask the next task; otherwise explain briefly and retry the same skill '
            'with different details. Complete only after task 7 succeeds; never complete earlier. '
            + ('Greeting: task_passed=false. MUST explain model 1 briefly in the native language, '
               'show that model, then ask ONE supported meaning question. Do not start an independent roleplay yet.' if greeting else
               'Judge communicative success, accepting valid alternatives and minor unrelated errors.') + focus + assessment)


def validate_plan(plan, target):
    if target != 'en' or not isinstance(plan, dict) or plan.get('version') not in (2, 3) or plan.get('target_language') != target:
        raise ValueError('Invalid teaching plan version or target language')
    for key in ('can_do', 'model', 'guided_tasks', 'independent_tasks', 'transfer_task', 'review_task'):
        value = plan.get(key)
        if not value or not isinstance(value, (str, list)):
            raise ValueError(f'Missing teaching plan {key}')
        if isinstance(value, list) and any(not isinstance(item, str) or not item.strip() for item in value):
            raise ValueError(f'Invalid teaching plan {key}')
        if key in ('can_do', 'transfer_task', 'review_task') and not isinstance(value, str):
            raise ValueError(f'Invalid teaching plan {key}')
    if not isinstance(plan['model'], list) or len(plan['model']) < 2:
        raise ValueError('At least two model examples required')
    for key in ('guided_tasks', 'independent_tasks'):
        if not isinstance(plan[key], list) or len(plan[key]) < 2:
            raise ValueError(f'Two {key} required')
    if plan.get('review_status') not in ('draft', 'pilot', 'teacher_reviewed'):
        raise ValueError('Explicit editorial status required')
    if plan['version'] == 3:
        tasks = plan.get('practice_tasks')
        if (not isinstance(tasks, list) or len(tasks) != 8
                or any(not isinstance(t, str) or not t.strip() for t in tasks)):
            raise ValueError('Eight concrete practice tasks required')
        questions=plan.get('learner_questions',{})
        if (not isinstance(questions,dict) or any(
                key not in {str(i) for i in range(2,8)} or not isinstance(value,str)
                or not value.strip() for key,value in questions.items())):
            raise ValueError('Invalid authored learner question mapping')


def render_plan(plan):
    validate_plan(plan, plan['target_language'])
    # V3 practice_tasks already contains these exercises verbatim. Keep the full
    # authoring plan in JSON, but avoid sending duplicate instructions each turn.
    materials = {k: v for k, v in plan.items() if plan['version'] != 3 or k not in {
        'guided_tasks', 'independent_tasks', 'transfer_task', 'scope_note',
        'source_text', 'language_note', 'pronunciation_focus'}}
    return f"""{PLAN_MARKER} {TRACKED_MARKER if plan['version'] == 3 else ''}
Lesson materials (examples are not student evidence):
{json.dumps(materials, ensure_ascii=False)}
Teach one small grammar chunk, explain meaning briefly in the native language,
show one model, then ask ONE task. Introduce at most 3 expressions per turn.
Use sentence frames in guided practice; fade hints in independent practice.
If confused, explain differently and retry a new example; do not escalate.
Accept valid alternatives, dialects, fictional details and useful fixed phrases.
Correct one relevant error gently and invite self-repair. Minor unrelated errors
do not fail communicative success. Complete only after independent AND transfer
success. Score task achievement (40), comprehensibility (30), language control (30).
Never invent unseen media or listening results. Visible text/source_text is reading,
not listening. Transcripts cannot establish pronunciation or spoken fluency.
Use short turns within recording limits. This is practice, not CEFR certification.
"""


def stage_instruction(answered_turns):
    """Server-selected earliest stage; passing this turn count never proves mastery."""
    if answered_turns < 2:
        return 'INTRODUCE: teach one small chunk using a model; ask a supported comprehension task. No completion.'
    if answered_turns < 5:
        return 'GUIDED: offer a sentence frame, practise one task; repair confusion before progressing. No completion.'
    if answered_turns < 7:
        return 'INDEPENDENT: remove frames only if ready; elicit original answers. No completion.'
    return ('TRANSFER: only if prior independent answers succeeded, use transfer_task in a changed context '
            'without giving its answer; otherwise continue supported practice. Complete only on demonstrated success.')
