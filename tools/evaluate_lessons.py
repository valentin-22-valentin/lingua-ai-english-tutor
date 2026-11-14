"""Bounded, synthetic live journeys for the three English showcase lessons.

No database writes or media dependencies. English is the default evaluation scope.
"""
import argparse
import json
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
from backend.curriculum import LANGUAGES,tracked_instruction
from tools.seed_database import load_course,lesson_prompt
from backend.tutor_engine import build_prompt,generate_reply,TutorError

EN={
 'A1_01':['Azt jelenti: szia, Mina vagyok, mi a neved?', 'Örülök, hogy megismerhetlek; udvarias válasz bemutatkozáskor.',
   'Good morning! How are you?', 'Good evening! How are you?', 'Hello, my name is Ada.',
   'How are you today?', 'I am fine, thanks. Goodbye!', 'Hello, I am Alex, your new neighbour. Nice to meet you. See you later!'],
 'A1_08':['Menj egyenesen, aztán fordulj balra.', 'A könyvtár a bank mellett van.',
   'Turn left.', 'Go straight ahead, then turn right.', 'Go straight ahead and turn left to reach the museum.',
   'Go straight ahead and turn right to reach the cafe.', 'Excuse me, how can I get to the museum?',
   'Go straight ahead and then turn right. The library is there.'],
 'A1_13':['Udvariasan levest és egy pohár vizet kérek.', 'Udvariasan elkérem a számlát.',
   'I would like tea, please.', 'I would like coffee, please.', 'Could I have a glass of water, please?',
   'I would like some soup, please.', 'Can I have the bill, please?',
   'I would like a salad and a juice, please. Could I have the bill, please?'],
}
def main():
    p=argparse.ArgumentParser()
    p.add_argument('--live',action='store_true')
    p.add_argument('--output',type=Path,default=ROOT/'.cache/evaluations/lesson_journeys.json')
    args=p.parse_args()
    if not args.live:
        print('English: 3 journeys, at most 36 generations, 200 output tokens each. --live spends API credit; no DB writes.')
        return
    from backend.dependencies import get_openai
    import os
    client=get_openai(); report=[]
    model=os.getenv('OPENAI_MODEL','gpt-4o-mini')
    _,courses=load_course(ROOT/'curriculum/manifest.json')
    for lesson in [l for l in courses[0][1] if l['lesson_id'] in EN]:
        prompt=build_prompt({'native_lang_code':'hu','target_lang_code':'en'},
            {'system_prompt':lesson_prompt(lesson,'A1'),'passing_score':80},LANGUAGES,[],['A1'])
        answers=EN[lesson['lesson_id']]
        history=[]; index=0; transcript=[]; error_type=None; failed=0; reply=None
        for turn in range(12):
            greeting=turn==0
            text='Begin the lesson.' if greeting else answers[index]
            try:
                reply=generate_reply(client,model,prompt+tracked_instruction(index,greeting,prompt),
                    history,text,greeting=greeting,answered_turns=turn,task_index=index)
            except Exception as error:
                error_type=type(error).__name__
                break
            transcript.append({'task':index,'student':None if greeting else text,'reply':reply.model_dump()})
            history.extend([{'role':'user','content':text},{'role':'assistant','content':reply.text}])
            if not greeting:
                if reply.task_passed: index+=1;failed=0
                else: failed+=1
            if index==8 or failed==2: break
        success=index==8 and error_type is None and reply is not None and reply.lesson_complete
        report.append({'language':'en','lesson':lesson['lesson_id'],'passed':success,
            'completed_tasks':index,'error_type':error_type,'turns':transcript})
        print(f'en/{lesson["lesson_id"]}: {index}/8',flush=True)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps({'synthetic':True,'model':model,'results':report},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    sys.exit(0 if all(r['passed'] for r in report) else 1)


if __name__=='__main__':main()
