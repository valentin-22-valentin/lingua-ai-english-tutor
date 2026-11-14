-- Single, readable implementations. No historical wrapper chain.
BEGIN;
-- A single source of truth for ordering across ALL chapters of the current level.
create or replace function public.tutor_next_lesson(p_profile_id uuid)
returns integer language sql stable security invoker set search_path = public as $$
    select l.id from public.profiles p
    join public.chapters c on c.target_lang_code = p.target_lang_code
        and c.level = coalesce(nullif(p.current_level, ''), 'ONBOARDING')
    join public.lessons l on l.chapter_id = c.id
    where p.id = p_profile_id and not exists (
        select 1 from public.user_progress up where up.profile_id = p.id
            and up.lesson_id = l.id and up.passed = true)
    order by c.order_index, c.id, l.order_index, l.id limit 1;
$$;

create or replace function public.tutor_start_session(p_profile_id uuid, p_lesson_id integer)
returns jsonb language plpgsql security invoker set search_path = public as $$
declare s public.chat_sessions%rowtype;
begin
    perform 1 from public.profiles where id = p_profile_id for update;
    if not found then raise sqlstate 'PT404' using message = 'Profile not found'; end if;
    if public.tutor_next_lesson(p_profile_id) is distinct from p_lesson_id then
        raise sqlstate 'PT409' using message = 'Lesson is no longer available';
    end if;
    select * into s from public.chat_sessions where profile_id = p_profile_id
        and lesson_id = p_lesson_id and status = 'active' order by started_at, id limit 1;
    if not found then
        insert into public.chat_sessions(profile_id, lesson_id, status)
            values(p_profile_id, p_lesson_id, 'active') returning * into s;
    end if;
    return to_jsonb(s);
end;
$$;

create or replace function public.tutor_onboard(p_profile_id uuid, p_mode text)
returns jsonb language plpgsql security invoker set search_path = public as $$
declare p public.profiles%rowtype; selected_level text;
begin
    select * into p from public.profiles where id = p_profile_id for update;
    if not found then raise sqlstate 'PT404' using message = 'Profile not found'; end if;
    if nullif(p.current_level, '') is not null and p.current_level <> 'ONBOARDING' then
        raise sqlstate 'PT409' using message = 'Onboarding already completed';
    end if;
    if p_mode = 'beginner' then
        select c.level into selected_level from public.chapters c
            where c.target_lang_code = p.target_lang_code and c.level <> 'ONBOARDING'
            and exists(select 1 from public.lessons l where l.chapter_id = c.id)
            order by c.order_index, c.id limit 1;
        if selected_level is null then
            raise sqlstate 'PT404' using message = 'No beginner curriculum';
        end if;
        update public.profiles set current_level = selected_level where id = p_profile_id;
        update public.chat_sessions set status = 'completed', ended_at = now(), revision = revision + 1
            where profile_id = p_profile_id and status = 'active';
    elsif p_mode = 'placement' then
        if not exists(select 1 from public.chapters c join public.lessons l on l.chapter_id = c.id
            where c.target_lang_code = p.target_lang_code and c.level = 'ONBOARDING'
            and l.lesson_type = 'placement_test') then
            raise sqlstate 'PT404' using message = 'No placement test';
        end if;
        selected_level := 'ONBOARDING';
    else
        raise sqlstate 'PT409' using message = 'Invalid onboarding mode';
    end if;
    return jsonb_build_object('current_level', selected_level);
end;
$$;

create or replace function public.tutor_commit_turn(
    p_profile_id uuid, p_session_id uuid, p_request_id uuid,
    p_expected_revision integer, p_input_text text, p_user_text text, p_reply jsonb
) returns jsonb language plpgsql security invoker set search_path = public as $$
declare
    p public.profiles%rowtype;
    s public.chat_sessions%rowtype;
    l public.lessons%rowtype;
    old_turn public.tutor_turns%rowtype;
    m public.user_mistakes%rowtype;
    item jsonb;
    result jsonb;
    score_value integer;
    finished boolean;
    passed_value boolean := false;
    next_level text;
    current_cefr text;
    current_order integer;
    review_success boolean;
    stamp timestamptz;
    expected integer := 0; evidence jsonb; prior jsonb; tracked boolean;
begin
    -- Consistent lock order serializes turns and onboarding for this profile.
    select * into p from public.profiles where id = p_profile_id for update;
    if not found then raise sqlstate 'PT404' using message = 'Profile not found'; end if;
    select * into old_turn from public.tutor_turns
        where profile_id = p_profile_id and request_id = p_request_id;
    if found then
        if old_turn.session_id <> p_session_id or old_turn.input_text is distinct from p_input_text then
            raise sqlstate 'PT409' using message = 'Request ID reused for another input';
        end if;
        return old_turn.result;
    end if;
    select * into s from public.chat_sessions where id = p_session_id
        and profile_id = p_profile_id for update;
    if not found then raise sqlstate 'PT404' using message = 'Session not found'; end if;
    if s.status <> 'active' or s.revision <> p_expected_revision
        or public.tutor_next_lesson(p_profile_id) is distinct from s.lesson_id then
        raise sqlstate 'PT409' using message = 'Stale or closed session';
    end if;
    select * into l from public.lessons where id = s.lesson_id;
    tracked := position('TEACHING_PLAN_V3' in l.system_prompt)>0;
    if tracked then
      for prior in select t.result from tutor_turns t where t.session_id=p_session_id
        and t.input_text is not null order by t.created_at,t.request_id loop
        if prior->'task_result'->>'task_index'=expected::text and prior->'task_result'->>'passed'='true'
        then expected:=expected+1; end if;
      end loop;
      evidence:=p_reply->'task_result';
      if evidence is null or jsonb_typeof(evidence)<>'object'
        or evidence->>'task_index' is distinct from expected::text
        or jsonb_typeof(evidence->'passed') is distinct from 'boolean'
        or (p_input_text is null and evidence->>'passed'='true') then
        raise sqlstate 'PT409' using message='Invalid practice evidence';
      end if;
      if p_reply->>'lesson_complete'='true' and (expected<>7 or evidence->>'passed'<>'true') then
        raise sqlstate 'PT409' using message='All eight tasks must succeed';
      end if;
    end if;
    if coalesce(btrim(p_reply->>'text'), '') = '' then
        raise sqlstate 'PT409' using message = 'Empty reply';
    end if;
    finished := (p_reply->>'lesson_complete')::boolean;
    score_value := (p_reply->>'score')::integer;
    if finished is null or (finished and (score_value is null or score_value not between 0 and 100))
        or (not finished and (score_value is not null or p_reply->>'assessed_level' is not null)) then
        raise sqlstate 'PT409' using message = 'Invalid evaluation';
    end if;
    if p_input_text is null and (finished or jsonb_array_length(p_reply->'mistakes') > 0
        or jsonb_array_length(p_reply->'reviews') > 0) then
        raise sqlstate 'PT409' using message = 'Greeting cannot assess student';
    end if;
    if finished and (l.is_level_exam or l.lesson_type='placement_test') and (
        select count(*) from public.tutor_turns where session_id = p_session_id
            and input_text is not null
    ) + (case when p_input_text is null then 0 else 1 end) < 10 then
        raise sqlstate 'PT409' using message = 'Exam needs at least ten student answers';
    end if;
    if finished and l.lesson_type = 'placement_test' then
        if not exists(select 1 from public.chapters where target_lang_code = p.target_lang_code
            and level = p_reply->>'assessed_level' and level <> 'ONBOARDING') then
            raise sqlstate 'PT409' using message = 'Invalid assessed level';
        end if;
    elsif p_reply->>'assessed_level' is not null then
        raise sqlstate 'PT409' using message = 'Only placement can assess level';
    end if;

    -- Space repeated errors at 1, 3, 7 days; mastery needs three demonstrated successes.
    for item in select value from jsonb_array_elements(p_reply->'reviews') loop
        if not (p_reply->'review_ids' @> jsonb_build_array((item->>'mistake_id')::integer)) then
            raise sqlstate 'PT409' using message = 'Unscheduled review';
        end if;
        select * into m from public.user_mistakes where id = (item->>'mistake_id')::integer
            and profile_id = p_profile_id and not mastered and next_review_at <= now() for update;
        if not found then raise sqlstate 'PT409' using message = 'Invalid review'; end if;
        review_success := (item->>'correct')::boolean;
        if review_success is null then raise sqlstate 'PT409' using message = 'Invalid review result'; end if;
        update public.user_mistakes set asked_again = true, last_reviewed_at = now(),
            review_count = case when review_success then m.review_count + 1 else 0 end,
            mastered = review_success and m.review_count + 1 >= 3,
            next_review_at = now() + case when not review_success then interval '1 day'
                when m.review_count = 0 then interval '1 day'
                when m.review_count = 1 then interval '3 days' else interval '7 days' end
            where id = m.id;
    end loop;
    for item in select value from jsonb_array_elements(p_reply->'mistakes') loop
        if coalesce(btrim(item->>'wrong_sentence'), '') = ''
            or coalesce(btrim(item->>'corrected_sentence'), '') = ''
            or position(lower(item->>'wrong_sentence') in lower(p_user_text)) = 0 then
            raise sqlstate 'PT409' using message = 'Mistake is not from student input';
        end if;
        select * into m from public.user_mistakes where profile_id = p_profile_id
            and target_lang_code='en' and wrong_sentence = item->>'wrong_sentence'
            and corrected_sentence = item->>'corrected_sentence' order by id limit 1 for update;
        if found then
            update public.user_mistakes set review_count = 0, mastered = false,
                next_review_at = now() + interval '1 day', grammar_rule = item->>'grammar_rule'
                where id = m.id;
        else
            insert into public.user_mistakes(profile_id, wrong_sentence, corrected_sentence,
                grammar_rule, next_review_at) values (p_profile_id, item->>'wrong_sentence',
                item->>'corrected_sentence', item->>'grammar_rule', now() + interval '1 day');
        end if;
    end loop;

    if finished then
        passed_value := score_value >= coalesce(l.passing_score, 80);
        if l.lesson_type = 'placement_test' then passed_value := true; end if;
        -- Preserve the best prior score; duplicate calls are handled above.
        update public.user_progress set score = greatest(coalesce(score, 0), score_value),
            passed = coalesce(passed, false) or passed_value, completed_at = now()
            where profile_id = p_profile_id and lesson_id = l.id;
        if not found then
            insert into public.user_progress(profile_id, lesson_id, score, passed)
                values(p_profile_id, l.id, score_value, passed_value);
        end if;
        if l.lesson_type = 'placement_test' then
            update public.profiles set current_level = p_reply->>'assessed_level' where id = p_profile_id;
        elsif l.is_level_exam and passed_value then
            select level into current_cefr from public.chapters where id = l.chapter_id;
            if exists(select 1 from public.chapters c join public.lessons other on other.chapter_id = c.id
                where c.target_lang_code = p.target_lang_code and c.level = current_cefr
                and not exists(select 1 from public.user_progress up where up.profile_id = p_profile_id
                    and up.lesson_id = other.id and up.passed)) then
                raise sqlstate 'PT409' using message = 'Level has unfinished lessons';
            end if;
            select max(order_index) into current_order from public.chapters
                where target_lang_code = p.target_lang_code and level = current_cefr;
            select c.level into next_level from public.chapters c
                where c.target_lang_code = p.target_lang_code and c.level <> 'ONBOARDING'
                and c.order_index > current_order
                and exists(select 1 from public.lessons next_l where next_l.chapter_id = c.id)
                order by c.order_index, c.id limit 1;
            if next_level is not null then
                update public.profiles set current_level = next_level where id = p_profile_id;
            end if;
        end if;
    end if;

    -- Both messages, error memory, progress and session state commit together.
    select greatest(clock_timestamp(), coalesce(max(created_at) + interval '2 microseconds',
        clock_timestamp())) into stamp from public.messages where session_id = p_session_id;
    -- Only actual learner messages belong in the visible transcript, not the server greeting instruction.
    if p_input_text is not null then
      insert into public.messages(session_id, role, content, created_at)
        values(p_session_id, 'user', p_input_text, stamp);
    end if;
    insert into public.messages(session_id, role, content, created_at)
        values(p_session_id, 'assistant', p_reply->>'text', stamp + interval '1 microsecond');
    update public.chat_sessions set revision = revision + 1,
        status = case when finished then 'completed' else status end,
        ended_at = case when finished then now() else ended_at end where id = p_session_id;
    select * into p from public.profiles where id = p_profile_id;
    result := jsonb_build_object('session_id', p_session_id, 'lesson_id', l.id,
        'text', p_reply->>'text', 'lesson_complete', finished, 'score', score_value,
        'passed', passed_value, 'current_level', coalesce(nullif(p.current_level, ''), 'ONBOARDING'),
        'resumed', false);
    if tracked then
      result:=result||jsonb_build_object('task_result',evidence,
        'practice_completed',expected+case when evidence->>'passed'='true' then 1 else 0 end);
    end if;
    insert into public.tutor_turns(profile_id, request_id, session_id, input_text, result)
        values(p_profile_id, p_request_id, p_session_id, p_input_text, result);
    return result;
end;
$$;


-- Journal writes are idempotent on the client-generated request ID; no credits/XP.
CREATE OR REPLACE FUNCTION public.journal_summary(p_profile_id uuid)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=public AS $$
 SELECT jsonb_build_object('journal',coalesce(jsonb_agg(row_data ORDER BY created_at DESC),'[]'::jsonb))
 FROM (SELECT j.created_at,(to_jsonb(j)-'profile_id'-'request_id') || jsonb_build_object('discussion',
  (SELECT coalesce(jsonb_agg(to_jsonb(d) ORDER BY d.created_at),'[]'::jsonb) FROM
   (SELECT message,text,created_at FROM journal_discussions WHERE entry_id=j.id ORDER BY created_at DESC LIMIT 20) d)) AS row_data
  FROM journal_entries j WHERE profile_id=p_profile_id ORDER BY created_at DESC LIMIT 30) entries;
$$;
CREATE OR REPLACE FUNCTION public.journal_commit(p_profile_id uuid,p_request_id uuid,p_content text,p_language_code text,p_feedback jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public AS $$
DECLARE entry journal_entries;
BEGIN
 PERFORM 1 FROM profiles WHERE id=p_profile_id FOR UPDATE;
 IF NOT FOUND THEN RAISE SQLSTATE 'PT404' USING MESSAGE='Profile missing'; END IF;
 IF p_language_code IS DISTINCT FROM 'en' OR length(trim(p_content)) NOT BETWEEN 1 AND 1200 THEN
  RAISE SQLSTATE 'PT422' USING MESSAGE='Invalid journal'; END IF;
 SELECT * INTO entry FROM journal_entries WHERE profile_id=p_profile_id AND request_id=p_request_id;
 IF FOUND THEN
  IF entry.content IS DISTINCT FROM p_content THEN RAISE SQLSTATE 'PT409' USING MESSAGE='Request mismatch'; END IF;
 ELSE
  INSERT INTO journal_entries(profile_id,request_id,content,language_code,feedback)
   VALUES(p_profile_id,p_request_id,p_content,'en',p_feedback) RETURNING * INTO entry;
 END IF;
 RETURN to_jsonb(entry)-'profile_id'-'request_id';
END $$;
CREATE OR REPLACE FUNCTION public.journal_discuss_commit(p_profile_id uuid,p_entry_id uuid,p_request_id uuid,p_message text,p_text text)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public AS $$
DECLARE discussion journal_discussions;
BEGIN
 PERFORM 1 FROM profiles WHERE id=p_profile_id FOR UPDATE;
 IF NOT EXISTS(SELECT 1 FROM journal_entries WHERE id=p_entry_id AND profile_id=p_profile_id) THEN
  RAISE SQLSTATE 'PT404' USING MESSAGE='Entry missing'; END IF;
 SELECT * INTO discussion FROM journal_discussions WHERE profile_id=p_profile_id AND request_id=p_request_id;
 IF FOUND THEN
  IF discussion.entry_id<>p_entry_id OR discussion.message IS DISTINCT FROM p_message THEN
   RAISE SQLSTATE 'PT409' USING MESSAGE='Request mismatch'; END IF;
 ELSE
  INSERT INTO journal_discussions(profile_id,entry_id,request_id,message,text)
   VALUES(p_profile_id,p_entry_id,p_request_id,p_message,p_text) RETURNING * INTO discussion;
 END IF;
 RETURN jsonb_build_object('text',discussion.text);
END $$;
CREATE OR REPLACE FUNCTION public.journal_delete(p_profile_id uuid,p_entry_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public AS $$
DECLARE saved_request uuid;
BEGIN
 PERFORM 1 FROM profiles WHERE id=p_profile_id FOR UPDATE;
 SELECT request_id INTO saved_request FROM journal_entries WHERE profile_id=p_profile_id AND id=p_entry_id;
 -- Upgrade compatibility: earlier deployments cached journal text in this table.
 IF to_regclass('public.usage_requests') IS NOT NULL AND saved_request IS NOT NULL THEN
  EXECUTE 'DELETE FROM public.usage_requests WHERE profile_id=$1 AND (request_id=$2 OR request_id IN
   (SELECT request_id FROM public.journal_discussions WHERE entry_id=$3))'
   USING p_profile_id,saved_request,p_entry_id;
 END IF;
 DELETE FROM journal_entries WHERE profile_id=p_profile_id AND id=p_entry_id;
 IF NOT FOUND THEN RAISE SQLSTATE 'PT404' USING MESSAGE='Entry missing'; END IF;
 RETURN jsonb_build_object('deleted',true);
END $$;
CREATE OR REPLACE FUNCTION public.tutor_set_languages(p_profile_id uuid,p_native text,p_target text,p_app text,p_expected_target text)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public AS $$
DECLARE learner profiles;
BEGIN
 IF p_target IS DISTINCT FROM 'en' OR p_native IS NULL OR p_app IS NULL
  OR p_native NOT IN ('hu','en','ro','es','fr','de') OR p_app NOT IN ('hu','en','ro','es','fr','de') THEN
  RAISE SQLSTATE 'PT422' USING MESSAGE='Invalid English preferences'; END IF;
 SELECT * INTO learner FROM profiles WHERE id=p_profile_id FOR UPDATE;
 IF NOT FOUND THEN RAISE SQLSTATE 'PT404' USING MESSAGE='Profile missing'; END IF;
 IF learner.target_lang_code IS DISTINCT FROM p_expected_target THEN
  RAISE SQLSTATE 'PT409' USING MESSAGE='Preferences changed'; END IF;
 UPDATE profiles SET native_lang_code=p_native,app_lang_code=p_app WHERE id=p_profile_id;
 RETURN jsonb_build_object('native_language',p_native,'target_language','en','app_language',p_app);
END $$;
DO $$ DECLARE signature text; BEGIN
 FOREACH signature IN ARRAY ARRAY['tutor_next_lesson(uuid)','tutor_start_session(uuid,integer)',
 'tutor_onboard(uuid,text)','tutor_commit_turn(uuid,uuid,uuid,integer,text,text,jsonb)',
 'journal_summary(uuid)','journal_commit(uuid,uuid,text,text,jsonb)',
 'journal_discuss_commit(uuid,uuid,uuid,text,text)','journal_delete(uuid,uuid)',
 'tutor_set_languages(uuid,text,text,text,text)'] LOOP
  EXECUTE 'REVOKE ALL ON FUNCTION public.'||signature||' FROM PUBLIC,anon,authenticated';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.'||signature||' TO service_role';
 END LOOP;
END $$;
-- Close legacy active sessions belonging to a different current lesson.
-- Preserve all messages and scores; these sessions remain readable in history.
UPDATE chat_sessions SET status='completed',ended_at=coalesce(ended_at,now()),revision=revision+1
 WHERE status='active' AND public.tutor_next_lesson(profile_id) IS DISTINCT FROM lesson_id;
INSERT INTO schema_releases(id) VALUES(9) ON CONFLICT DO NOTHING;
NOTIFY pgrst,'reload schema';
COMMIT;
