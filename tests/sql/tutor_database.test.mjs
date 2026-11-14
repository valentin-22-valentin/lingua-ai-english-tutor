// Real PostgreSQL/PLpgSQL in memory; no cloud writes or credentials.
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { test, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

const db = new PGlite();
const profile = randomUUID();
const schema=readFileSync(new URL('../../database/schema.sql',import.meta.url),'utf8');
const functions=readFileSync(new URL('../../database/functions.sql',import.meta.url),'utf8');
before(async()=>{
 await db.exec('CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role BYPASSRLS; CREATE SCHEMA auth; CREATE TABLE auth.users(id uuid PRIMARY KEY);');
 await db.exec(schema); await db.exec(functions);
 await db.exec(schema); await db.exec(functions);
 await db.query('INSERT INTO auth.users(id) VALUES($1)',[profile]);
});
after(async()=>{await db.close();});
beforeEach(async () => {
  await db.exec(`TRUNCATE tutor_turns, messages, user_mistakes, user_progress, chat_sessions, lessons, chapters, profiles RESTART IDENTITY CASCADE;`);
  await db.query(`INSERT INTO profiles(id, username, native_lang_code, target_lang_code, app_lang_code, current_level)
    VALUES($1, 'Test student', 'hu', 'en', 'hu', 'A1')`, [profile]);
  await db.exec(`INSERT INTO chapters(id, target_lang_code, level, title, order_index) VALUES
    (0, 'en', 'ONBOARDING', 'Placement', 0), (1, 'en', 'A1', 'First chapter', 1),
    (2, 'en', 'A1', 'Second chapter', 2), (3, 'en', 'A2', 'Next level', 3);
    INSERT INTO lessons(id, chapter_id, title, lesson_type, system_prompt, passing_score, order_index, is_level_exam) VALUES
    (0, 0, 'Placement', 'placement_test', 'Assess', 0, 1, false),
    (1, 1, 'First lesson', 'interactive', 'Greet', 80, 1, false),
    (2, 2, 'Second lesson', 'interactive', 'Practise', 80, 1, false),
    (3, 2, 'Exam', 'interactive', 'Exam', 85, 2, true),
    (4, 3, 'Next lesson', 'interactive', 'Continue', 80, 1, false);`);
});

const reply = (extra = {}) => ({text: 'How are you?', mistakes: [], reviews: [], review_ids: [],
  lesson_complete: false, score: null, assessed_level: null, ...extra});

test('tracked practice persists evidence, resumes and commits completion exactly once', async () => {
  await db.exec("UPDATE lessons SET system_prompt='TEACHING_PLAN_V3' WHERE id=1");
  const s = await start();
  const request = randomUUID();
  const first = reply({task_result: {task_index: 0, passed: true}});
  const saved = await commit(s, first, {request});
  assert.deepEqual(saved.task_result, first.task_result);
  assert.deepEqual(await commit(s, first, {request}), saved);
  assert.equal(await count('tutor_turns'), 1);
  assert.equal((await start()).id, s.id);
  for (let index=1; index<8; index++) {
    await commit(s, reply({task_result: {task_index:index,passed:true},
      lesson_complete:index===7,score:index===7?100:null}), {revision:index});
  }
  assert.equal(await count('user_progress'),1);
  assert.equal((await db.query('SELECT status FROM chat_sessions WHERE id=$1',[s.id])).rows[0].status,'completed');
});

test('tracked practice refuses missing evidence, skipped tasks and early completion atomically', async () => {
  await db.exec("UPDATE lessons SET system_prompt='TEACHING_PLAN_V3' WHERE id=1");
  const s = await start();
  for (const bad of [reply(),reply({task_result:{task_index:7,passed:true}}),
    reply({task_result:{task_index:0,passed:true},lesson_complete:true,score:100})]) {
    await assert.rejects(commit(s,bad),{code:'PT409'});
  }
  assert.equal(await count('messages'),0);
  assert.equal(await count('user_progress'),0);
});

test('failed tracked task stays at same task and greeting cannot advance it', async () => {
  await db.exec("UPDATE lessons SET system_prompt='TEACHING_PLAN_V3' WHERE id=1");
  const s = await start();
  await assert.rejects(commit(s,reply({task_result:{task_index:0,passed:true}}),{input:null}),{code:'PT409'});
  await commit(s,reply({task_result:{task_index:0,passed:false}}));
  await commit(s,reply({task_result:{task_index:0,passed:true}}),{revision:1});
  assert.equal(await count('tutor_turns'),2);
});
async function start(lesson = 1) {
  return (await db.query('SELECT tutor_start_session($1, $2) AS result', [profile, lesson])).rows[0].result;
}
async function commit(session, data, {revision = session.revision, input = 'Hello', request = randomUUID()} = {}) {
  return (await db.query(`SELECT tutor_commit_turn($1, $2, $3, $4, $5, $6, $7::jsonb) AS result`,
    [profile, session.id, request, revision, input, input ?? 'Start the lesson.', JSON.stringify(data)])).rows[0].result;
}

test('server greeting is not saved as a fake learner message', async () => {
  const s = await start();
  await commit(s,reply(),{input:null});
  const messages=(await db.query('SELECT role,content FROM messages ORDER BY created_at,id')).rows;
  assert.deepEqual(messages,[{role:'assistant',content:'How are you?'}]);
});

test('upgrading closes mismatched legacy sessions without deleting conversations', async () => {
  const s=await start();
  await commit(s,reply());
  await db.query("UPDATE profiles SET current_level='A2' WHERE id=$1",[profile]);
  await db.exec(functions);
  assert.equal((await db.query('SELECT status FROM chat_sessions WHERE id=$1',[s.id])).rows[0].status,'completed');
  assert.equal(await count('messages'),2);
  assert.equal(await count('user_progress'),0);
  assert.equal((await start(4)).lesson_id,4);
});
async function count(table) {
  return (await db.query(`SELECT count(*)::integer AS n FROM ${table}`)).rows[0].n;
}
async function passEarlierLessons() {
  await db.query(`INSERT INTO user_progress(profile_id, lesson_id, score, passed) VALUES($1, 1, 90, true),($1, 2, 90, true)`, [profile]);
}

test('start resumes one active session and prevents skipping lessons', async () => {
  const first = await start();
  assert.equal((await start()).id, first.id);
  assert.equal(await count('chat_sessions'), 1);
  await assert.rejects(start(4), {code: 'PT409'});
});

test('turn atomically persists both messages and separate mistake metadata', async () => {
  const s = await start();
  const result = await commit(s, reply({mistakes: [{wrong_sentence: 'I goes', corrected_sentence: 'I go', grammar_rule: 'Agreement'}]}), {input: 'I goes home'});
  assert.equal(result.text, 'How are you?');
  assert.equal(await count('messages'), 2);
  const m = (await db.query('SELECT * FROM user_mistakes')).rows[0];
  assert.equal(m.corrected_sentence, 'I go');
  assert.equal(m.mastered, false);
  assert.ok(new Date(m.next_review_at) > new Date(m.created_at));
  const messages = (await db.query('SELECT role, content FROM messages ORDER BY created_at, id')).rows;
  assert.deepEqual(messages.map(m => m.role), ['user', 'assistant']);
  assert.equal(messages[1].content, result.text);
});

test('failure after memory writes rolls back all effects', async () => {
  await db.exec(`CREATE FUNCTION reject_test_message() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN RAISE EXCEPTION 'simulated write failure'; END; $$;
    CREATE TRIGGER test_failure BEFORE INSERT ON messages FOR EACH ROW EXECUTE FUNCTION reject_test_message();`);
  const s = await start();
  try {
    await assert.rejects(commit(s, reply({lesson_complete: true, score: 95,
      mistakes: [{wrong_sentence: 'I goes', corrected_sentence: 'I go', grammar_rule: 'Agreement'}]}), {input: 'I goes'}));
    assert.equal(await count('user_mistakes'), 0);
    assert.equal(await count('user_progress'), 0);
    assert.equal(await count('messages'), 0);
    assert.equal(await count('tutor_turns'), 0);
    assert.equal((await db.query('SELECT revision, status FROM chat_sessions')).rows[0].status, 'active');
  } finally {
    await db.exec('DROP TRIGGER test_failure ON messages; DROP FUNCTION reject_test_message();');
  }
});

test('retry is idempotent even after completion; changed input is a conflict', async () => {
  const s = await start();
  const request = randomUUID();
  const first = await commit(s, reply({lesson_complete: true, score: 90}), {request});
  assert.deepEqual(await commit(s, reply({lesson_complete: true, score: 90}), {request}), first);
  assert.equal(await count('messages'), 2);
  assert.equal(await count('user_progress'), 1);
  await assert.rejects(commit(s, reply(), {request, input: 'Different'}), {code: 'PT409'});
});

test('stale revision cannot save a conflicting turn', async () => {
  const s = await start();
  await commit(s, reply());
  await assert.rejects(commit(s, reply()), {code: 'PT409'});
  assert.equal(await count('messages'), 2);
});

test('failed lesson closes session, preserves score, and stays available for retry', async () => {
  const s = await start();
  const result = await commit(s, reply({lesson_complete: true, score: 60}));
  assert.equal(result.passed, false);
  assert.equal((await db.query('SELECT score FROM user_progress')).rows[0].score, 60);
  assert.equal((await start()).lesson_id, 1);
  assert.equal(await count('chat_sessions'), 2);
});

test('completion moves to next chapter without promoting the CEFR level', async () => {
  await commit(await start(), reply({lesson_complete: true, score: 90}));
  assert.equal((await start(2)).lesson_id, 2);
  assert.equal((await db.query('SELECT current_level FROM profiles')).rows[0].current_level, 'A1');
});

test('exam enforces ten answers and 85 percent; passed exam unlocks next level', async () => {
  await passEarlierLessons();
  const s = await start(3);
  await assert.rejects(commit(s, reply({lesson_complete: true, score: 90})), {code: 'PT409'});
  for (let revision = 0; revision < 9; revision++) await commit(s, reply(), {revision});
  const result = await commit(s, reply({lesson_complete: true, score: 85}), {revision: 9});
  assert.equal(result.passed, true);
  assert.equal(result.current_level, 'A2');
  assert.equal((await start(4)).lesson_id, 4);
});

test('failed exam keeps current level and can be retried', async () => {
  await passEarlierLessons();
  const s = await start(3);
  for (let revision = 0; revision < 9; revision++) await commit(s, reply(), {revision});
  const result = await commit(s, reply({lesson_complete: true, score: 84}), {revision: 9});
  assert.equal(result.passed, false);
  assert.equal(result.current_level, 'A1');
  assert.notEqual((await start(3)).id, s.id);
});

test('placement accepts only available levels and updates the profile', async () => {
  await db.query('UPDATE profiles SET current_level = NULL WHERE id = $1', [profile]);
  const s = await start(0);
  await assert.rejects(commit(s, reply({lesson_complete: true, score: 90, assessed_level: 'C2'})), {code: 'PT409'});
  for(let revision=0;revision<9;revision++) await commit(s,reply(),{revision});
  const result = await commit(s, reply({lesson_complete: true, score: 70, assessed_level: 'A2'}),{revision:9});
  assert.equal(result.current_level, 'A2');
});

test('beginner onboarding uses database ordering and cannot reset an existing learner', async () => {
  await assert.rejects(db.query('SELECT tutor_onboard($1, $2)', [profile, 'beginner']), {code: 'PT409'});
  await db.query('UPDATE profiles SET current_level = NULL WHERE id = $1', [profile]);
  const result = (await db.query('SELECT tutor_onboard($1, $2) AS result', [profile, 'beginner'])).rows[0].result;
  assert.equal(result.current_level, 'A1');
});

test('reviews schedule successes, reach mastery, and repeated errors reset mastery', async () => {
  const s = await start();
  await db.query(`INSERT INTO user_mistakes(profile_id, wrong_sentence, corrected_sentence, grammar_rule, next_review_at)
    VALUES($1, 'I goes', 'I go', 'Agreement', now() - interval '1 day')`, [profile]);
  const id = (await db.query('SELECT id FROM user_mistakes')).rows[0].id;
  for (let revision = 0; revision < 3; revision++) {
    await commit(s, reply({review_ids: [id], reviews: [{mistake_id: id, correct: true}]}), {revision});
    if (revision < 2) await db.exec(`UPDATE user_mistakes SET next_review_at = now() - interval '1 day'`);
  }
  let m = (await db.query('SELECT review_count, mastered, asked_again FROM user_mistakes')).rows[0];
  assert.deepEqual(m, {review_count: 3, mastered: true, asked_again: true});
  await commit(s, reply({mistakes: [{wrong_sentence: 'I goes', corrected_sentence: 'I go', grammar_rule: 'Agreement'}]}),
    {revision: 3, input: 'I goes'});
  m = (await db.query('SELECT review_count, mastered FROM user_mistakes')).rows[0];
  assert.deepEqual(m, {review_count: 0, mastered: false});
  assert.equal(await count('user_mistakes'), 1);
});

test('other learner mistake IDs and unoffered review IDs are rejected', async () => {
  const s = await start();
  await assert.rejects(commit(s, reply({reviews: [{mistake_id: 999, correct: true}]})), {code: 'PT409'});
  await assert.rejects(commit(s, reply({review_ids: [999], reviews: [{mistake_id: 999, correct: true}]})), {code: 'PT409'});
  assert.equal(await count('messages'), 0);
});

test('database functions are not callable by browser roles', async () => {
  const rows = (await db.query(`SELECT has_function_privilege('anon', 'tutor_commit_turn(uuid,uuid,uuid,integer,text,text,jsonb)', 'EXECUTE') AS anon,
    has_function_privilege('authenticated', 'tutor_start_session(uuid,integer)', 'EXECUTE') AS authenticated`)).rows;
  assert.deepEqual(rows[0], {anon: false, authenticated: false});
});

test('backend service role can call functions while RLS protects browser roles', async () => {
  await db.exec('SET ROLE service_role');
  try {
    const session = await start();
    assert.equal((await commit(session, reply())).text, 'How are you?');
  } finally {
    await db.exec('RESET ROLE');
  }
  await db.exec('GRANT SELECT ON tutor_turns TO anon; SET ROLE anon');
  try {
    assert.equal(await count('tutor_turns'), 0);
  } finally {
    await db.exec('RESET ROLE');
  }
});


const journalCommit=async(request=randomUUID(),content='Today I cooked dinner.') =>
 (await db.query('SELECT journal_commit($1,$2,$3,$4,$5::jsonb) AS result',
 [profile,request,content,'en',JSON.stringify({text:'Good work.',corrections:[]})])).rows[0].result;
test('journal saves without credits; duplicate request returns the same entry',async()=>{
 const request=randomUUID(); const first=await journalCommit(request);
 assert.deepEqual(await journalCommit(request),first);
 assert.equal(await count('journal_entries'),1);
 await assert.rejects(journalCommit(request,'Changed text'),{code:'PT409'});
 const listing=(await db.query('SELECT journal_summary($1) AS result',[profile])).rows[0].result;
 assert.equal(listing.journal[0].content,'Today I cooked dinner.');
 assert.equal(listing.journal[0].profile_id,undefined);
 assert.equal(listing.credits,undefined);
});
test('discussion is private and retry-safe; deletion removes discussion text',async()=>{
 const entry=await journalCommit(); const request=randomUUID();
 const discuss=async(owner=profile,message='Why this tense?') =>
  (await db.query('SELECT journal_discuss_commit($1,$2,$3,$4,$5) AS result',
   [owner,entry.id,request,message,'Use past tense.'])).rows[0].result;
 assert.deepEqual(await discuss(),await discuss());
 await assert.rejects(discuss(profile,'A different question'),{code:'PT409'});
 await assert.rejects(discuss(randomUUID()),{code:'PT404'});
 const summary=(await db.query('SELECT journal_summary($1) AS result',[profile])).rows[0].result;
 assert.equal(summary.journal[0].discussion[0].text,'Use past tense.');
 await db.query('SELECT journal_delete($1,$2)',[profile,entry.id]);
 assert.equal(await count('journal_entries'),0); assert.equal(await count('journal_discussions'),0);
});
test('all explanation languages preserve the active English lesson',async()=>{
 const session=await start();
 for(const native of ['hu','en','ro','es','fr','de']){
  const result=(await db.query('SELECT tutor_set_languages($1,$2,$3,$4,$5) AS result',[profile,native,'en','fr','en'])).rows[0].result;
  assert.equal(result.target_language,'en'); assert.equal(result.native_language,native);
  assert.equal((await db.query('SELECT status FROM chat_sessions WHERE id=$1',[session.id])).rows[0].status,'active');
 }
 await assert.rejects(db.query('SELECT tutor_set_languages($1,$2,$3,$4,$5)',[profile,'hu','de','hu','en']),{code:'PT422'});
});
test('journal RPCs are backend-only and fresh schema contains no retired tables',async()=>{
 for(const signature of ['journal_summary(uuid)','journal_commit(uuid,uuid,text,text,jsonb)',
 'journal_discuss_commit(uuid,uuid,uuid,text,text)','journal_delete(uuid,uuid)']){
  assert.equal((await db.query("SELECT has_function_privilege('authenticated',$1,'EXECUTE') AS allowed",[signature])).rows[0].allowed,false);
 }
 for(const table of ['usage_requests','practice_events','learning_images','learning_videos'])
  assert.equal((await db.query('SELECT to_regclass($1) AS name',[table])).rows[0].name,null);
});

test('upgraded installations delete historical private journal cache too',async()=>{
 await db.exec('CREATE TABLE usage_requests(profile_id uuid,request_id uuid,result jsonb)');
 try {
  const request=randomUUID(); const entry=await journalCommit(request);
  await db.query('INSERT INTO usage_requests VALUES($1,$2,$3::jsonb)',[profile,request,JSON.stringify({private:'Old journal text'})]);
  await db.query('SELECT journal_delete($1,$2)',[profile,entry.id]);
  assert.equal(await count('usage_requests'),0);
 } finally { await db.exec('DROP TABLE usage_requests'); }
});
