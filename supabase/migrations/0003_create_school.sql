-- EduManager Cloud — PR-E: atomic school self-onboarding
-- Additive and transactional. Run only after PR-B.2 is live.
-- This RPC creates the tenant row and its first admin membership atomically.
-- It stores no plaintext password. The caller must have a verified Supabase Auth email.
begin;
select pg_advisory_xact_lock(hashtextextended('edumanager:create-school:v1', 0));

create or replace function public.create_school(p_school_code text, p_school_name text)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user uuid := auth.uid();
  v_confirmed_at timestamptz;
  v_code text := upper(trim(coalesce(p_school_code, '')));
  v_name text := trim(coalesce(p_school_name, ''));
  v_data jsonb;
  v_master jsonb;
  v_entry jsonb;
  v_classes jsonb;
  v_subjects jsonb;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select email_confirmed_at into v_confirmed_at from auth.users where id = v_user;
  if v_confirmed_at is null then raise exception 'Verify your email before creating a school'; end if;
  if v_code !~ '^[A-Z0-9][A-Z0-9_-]{2,19}$' or v_code = '__MASTER__' or v_code = 'DEMO' then
    raise exception 'Invalid school code';
  end if;
  if length(v_name) < 2 or length(v_name) > 100 then raise exception 'Invalid school name'; end if;

  -- Idempotent retry for the same verified user and same school code.
  if exists (select 1 from public.memberships where user_id = v_user and school_id = v_code and role = 'admin') then
    return jsonb_build_object('school_code', v_code, 'already_created', true);
  end if;
  if exists (select 1 from public.school_data where id = v_code) then
    raise exception 'School code is unavailable';
  end if;

  v_classes := jsonb_build_array(
    jsonb_build_object('id','sample-c1','name','Primary 1','sample',true),
    jsonb_build_object('id','sample-c2','name','Primary 2','sample',true),
    jsonb_build_object('id','sample-c3','name','Primary 3','sample',true),
    jsonb_build_object('id','sample-c4','name','JSS 1','sample',true)
  );
  v_subjects := jsonb_build_object(
    'sample-c1', jsonb_build_array('Numeracy','Literacy','Rhymes'),
    'sample-c2', jsonb_build_array('English Language','Mathematics','Basic Science'),
    'sample-c3', jsonb_build_array('English Language','Mathematics','Basic Science'),
    'sample-c4', jsonb_build_array('English Language','Mathematics','Basic Science','Social Studies')
  );
  select jsonb_build_object(
    'settings', jsonb_build_object(
      'code',v_code,'schoolName',v_name,'shortName',v_name,'address','Nigeria',
      'motto','Knowledge • Character • Service','session','2026/2027','term','First Term',
      'status','active','receiptSeq',0,'grade',jsonb_build_object('ca1',20,'ca2',20,'exam',60),
      'sampleData',true,'theme','green','modules',jsonb_build_object()
    ),
    'users',jsonb_build_array(jsonb_build_object(
      'id',v_user::text,'name',coalesce((select raw_user_meta_data->>'name' from auth.users where id=v_user),'School Administrator'),
      'username',coalesce((select email from auth.users where id=v_user),''),'role','admin','classes',jsonb_build_array(),'staffId','STAFF/001','photo',''
    )),
    'classes',v_classes,'students','[]'::jsonb,'subjects',v_subjects,
    'attendance','{}'::jsonb,'results','{}'::jsonb,'fees','{}'::jsonb,
    'payments','[]'::jsonb,'applicants','[]'::jsonb,'remarks','{}'::jsonb
  ) into v_data;

  insert into public.school_data(id,data) values (v_code,v_data);
  insert into public.memberships(user_id,school_id,role) values (v_user,v_code,'admin');

  v_entry := jsonb_build_object('code',v_code,'name',v_name,'status','active','type','school','createdAt',now());
  insert into public.school_data(id,data)
    values ('__master__',jsonb_build_object('platform',jsonb_build_object('name','EduManager Cloud'),'schools',jsonb_build_array(v_entry),'pins','[]'::jsonb,'batches','[]'::jsonb))
    on conflict (id) do nothing;
  select data into v_master from public.school_data where id='__master__' for update;
  if not exists (
    select 1 from jsonb_array_elements(coalesce(v_master->'schools','[]'::jsonb)) x
    where upper(coalesce(x->>'code','')) = v_code
  ) then
    update public.school_data
       set data = jsonb_set(coalesce(data,'{}'::jsonb),'{schools}',
             coalesce(data->'schools','[]'::jsonb) || jsonb_build_array(v_entry),true),
           updated_at = now()
     where id='__master__';
  end if;

  return jsonb_build_object('school_code',v_code,'already_created',false);
end;
$$;

revoke all on function public.create_school(text,text) from public, anon;
grant execute on function public.create_school(text,text) to authenticated;

commit;

-- Rollback (run only after reverting PR-E code and confirming no new schools depend on this RPC):
-- begin;
-- select pg_advisory_xact_lock(hashtextextended('edumanager:create-school:v1', 0));
-- revoke execute on function public.create_school(text,text) from authenticated;
-- drop function if exists public.create_school(text,text);
-- commit;
