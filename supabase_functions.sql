-- ============================================================
--  只建立三個函式（RLS 政策已完成，不要重跑整份 supabase_rls.sql）
--  請整份一次貼上執行
-- ============================================================

create or replace function public.is_trip_member(p_trip_id text)
returns boolean language sql stable security definer set search_path = public as
$fn1$
  select exists (
    select 1 from public.user_trips
    where user_id = auth.uid() and trip_id = p_trip_id
  );
$fn1$;


create or replace function public.preview_trip_by_code(p_code text)
returns json language plpgsql stable security definer set search_path = public as
$fn2$
declare
  v_trip public.trips%rowtype;
  v_members json;
begin
  if auth.uid() is null then
    raise exception '請先登入';
  end if;

  select * into v_trip from public.trips
  where upper(invite_code) = upper(trim(p_code));

  if v_trip.id is null then
    return null;
  end if;

  select coalesce(json_agg(json_build_object(
           'id', m.id, 'name', m.name,
           'emoji', m.emoji, 'avatar_url', m.avatar_url)), '[]'::json)
    into v_members
  from public.members m where m.trip_id = v_trip.id;

  return json_build_object(
    'id', v_trip.id, 'name', v_trip.name,
    'start_date', v_trip.start_date, 'end_date', v_trip.end_date,
    'members', v_members);
end;
$fn2$;


create or replace function public.join_trip_by_code(p_code text, p_member_id text)
returns text language plpgsql security definer set search_path = public as
$fn3$
declare
  v_trip_id text;
begin
  if auth.uid() is null then
    raise exception '請先登入';
  end if;

  select id into v_trip_id from public.trips
  where upper(invite_code) = upper(trim(p_code));

  if v_trip_id is null then
    raise exception '邀請碼無效';
  end if;

  if not exists (select 1 from public.user_trips
                 where user_id = auth.uid() and trip_id = v_trip_id) then
    insert into public.user_trips (user_id, trip_id, member_id)
    values (auth.uid(), v_trip_id, p_member_id);
  else
    update public.user_trips set member_id = p_member_id
    where user_id = auth.uid() and trip_id = v_trip_id;
  end if;

  return v_trip_id;
end;
$fn3$;


-- 權限：只有已登入者可呼叫
revoke all on function public.preview_trip_by_code(text) from public, anon;
revoke all on function public.join_trip_by_code(text, text) from public, anon;
grant execute on function public.preview_trip_by_code(text) to authenticated;
grant execute on function public.join_trip_by_code(text, text) to authenticated;

-- 讓 API 立即看到新函式
notify pgrst, 'reload schema';

-- 確認：應回傳 3 列
select proname as 已建立的函式
from pg_proc
where pronamespace = 'public'::regnamespace
  and proname in ('is_trip_member','preview_trip_by_code','join_trip_by_code');
