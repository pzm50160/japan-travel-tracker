-- ============================================================
--  旅遊記帳 — 修正資料列權限 (RLS)
--
--  現況診斷（2026-08-18）：
--    RLS 已啟用，但 trips / members / expenses 上各有一條
--    「public read write」政策，對象 {public}、條件 true、動作 ALL
--    → 任何未登入者都能讀取、修改、刪除全部資料
--    另外 user_trips 的「own_rows」政策未限制 trip_id
--    → 任何登入者可自行插入紀錄取得任意旅程存取權
--
--  本檔會移除上述政策，改成「必須是該旅程成員」
--
--  執行位置：Supabase 後台 → SQL Editor → 貼上 → Run
--  可重複執行。還原指令在本檔最下方。
-- ============================================================

-- ─────────────────────────────────────────────
-- 步驟 1：輔助函式 — 判斷目前登入者是否為某旅程的成員
-- ─────────────────────────────────────────────
create or replace function public.is_trip_member(p_trip_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_trips
    where user_id = auth.uid()
      and trip_id = p_trip_id
  );
$$;

-- ─────────────────────────────────────────────
-- 步驟 2：加入旅程用的兩個函式
--   這兩個函式以「管理員權限」執行，是唯一能繞過 RLS 的入口，
--   但必須提供正確的邀請碼才會回傳資料。
-- ─────────────────────────────────────────────

-- 2a. 用邀請碼預覽旅程（尚未加入，只回傳名稱與成員清單）
create or replace function public.preview_trip_by_code(p_code text)
returns json
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_trip   public.trips%rowtype;
  v_members json;
begin
  if auth.uid() is null then
    raise exception '請先登入';
  end if;

  select * into v_trip
  from public.trips
  where upper(invite_code) = upper(trim(p_code));

  if v_trip.id is null then
    return null;                      -- 找不到邀請碼
  end if;

  select coalesce(json_agg(json_build_object(
           'id', m.id, 'name', m.name,
           'emoji', m.emoji, 'avatar_url', m.avatar_url
         )), '[]'::json)
    into v_members
  from public.members m
  where m.trip_id = v_trip.id;

  return json_build_object(
    'id',         v_trip.id,
    'name',       v_trip.name,
    'start_date', v_trip.start_date,
    'end_date',   v_trip.end_date,
    'members',    v_members
  );
end;
$$;

-- 2b. 用邀請碼正式加入旅程（寫入 user_trips，之後就靠一般規則放行）
create or replace function public.join_trip_by_code(p_code text, p_member_id text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_trip_id text;
begin
  if auth.uid() is null then
    raise exception '請先登入';
  end if;

  select id into v_trip_id
  from public.trips
  where upper(invite_code) = upper(trim(p_code));

  if v_trip_id is null then
    raise exception '邀請碼無效';
  end if;

  insert into public.user_trips (user_id, trip_id, member_id)
  values (auth.uid(), v_trip_id, p_member_id)
  on conflict (user_id, trip_id) do update set member_id = excluded.member_id;

  return v_trip_id;
end;
$$;

-- 開放給已登入的使用者呼叫；未登入者一律拒絕
revoke all on function public.preview_trip_by_code(text) from public, anon;
revoke all on function public.join_trip_by_code(text, text) from public, anon;
grant execute on function public.preview_trip_by_code(text) to authenticated;
grant execute on function public.join_trip_by_code(text, text) to authenticated;

-- ─────────────────────────────────────────────
-- 步驟 3：開啟 RLS 並建立規則
-- ─────────────────────────────────────────────

-- ─────────────────────────────────────────────
-- 步驟 3-0：移除既有的寬鬆政策（這是漏洞本體）
--   政策之間是 OR 關係，不刪掉的話新政策形同虛設
-- ─────────────────────────────────────────────
drop policy if exists "public read write" on public.trips;
drop policy if exists "public read write" on public.members;
drop policy if exists "public read write" on public.expenses;
-- user_trips 的 own_rows 未限制 trip_id，改由下方四條政策取代
drop policy if exists own_rows on public.user_trips;
-- 註：user_pack 的 own_rows 政策正確（僅存取自己的行李清單），保留不動

-- ---------- user_trips：只能看到／修改自己的 ----------
alter table public.user_trips enable row level security;
drop policy if exists ut_select on public.user_trips;
drop policy if exists ut_insert on public.user_trips;
drop policy if exists ut_update on public.user_trips;
drop policy if exists ut_delete on public.user_trips;

create policy ut_select on public.user_trips
  for select to authenticated
  using (user_id = auth.uid());

-- 只允許「建立新旅程」時自己認領（該旅程還沒有任何擁有者）。
-- 加入他人旅程一律走 join_trip_by_code()，否則就能靠猜 ID 取得存取權。
create policy ut_insert on public.user_trips
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and not exists (
      select 1 from public.user_trips existing
      where existing.trip_id = user_trips.trip_id
    )
  );

create policy ut_update on public.user_trips
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy ut_delete on public.user_trips
  for delete to authenticated
  using (user_id = auth.uid());

-- ---------- trips ----------
alter table public.trips enable row level security;
drop policy if exists trips_select on public.trips;
drop policy if exists trips_insert on public.trips;
drop policy if exists trips_update on public.trips;

create policy trips_select on public.trips
  for select to authenticated
  using (public.is_trip_member(id));

create policy trips_insert on public.trips
  for insert to authenticated
  with check (auth.uid() is not null);

create policy trips_update on public.trips
  for update to authenticated
  using (public.is_trip_member(id))
  with check (public.is_trip_member(id));

-- ---------- members ----------
alter table public.members enable row level security;
drop policy if exists members_select on public.members;
drop policy if exists members_insert on public.members;
drop policy if exists members_update on public.members;
drop policy if exists members_delete on public.members;

create policy members_select on public.members
  for select to authenticated
  using (public.is_trip_member(trip_id));

create policy members_insert on public.members
  for insert to authenticated
  with check (public.is_trip_member(trip_id));

create policy members_update on public.members
  for update to authenticated
  using (public.is_trip_member(trip_id))
  with check (public.is_trip_member(trip_id));

create policy members_delete on public.members
  for delete to authenticated
  using (public.is_trip_member(trip_id));

-- ---------- expenses ----------
alter table public.expenses enable row level security;
drop policy if exists expenses_select on public.expenses;
drop policy if exists expenses_insert on public.expenses;
drop policy if exists expenses_update on public.expenses;
drop policy if exists expenses_delete on public.expenses;

create policy expenses_select on public.expenses
  for select to authenticated
  using (public.is_trip_member(trip_id));

create policy expenses_insert on public.expenses
  for insert to authenticated
  with check (public.is_trip_member(trip_id));

create policy expenses_update on public.expenses
  for update to authenticated
  using (public.is_trip_member(trip_id))
  with check (public.is_trip_member(trip_id));

create policy expenses_delete on public.expenses
  for delete to authenticated
  using (public.is_trip_member(trip_id));

-- ---------- user_pack：既有政策已正確，不需變更 ----------


-- ─────────────────────────────────────────────
-- 步驟 4：執行後自我檢查
-- ─────────────────────────────────────────────
select tablename as 資料表, policyname as 政策, cmd as 動作,
       roles::text as 對象, qual as 條件
from pg_policies
where schemaname = 'public'
  and tablename in ('trips','members','expenses','user_trips','user_pack')
order by tablename, policyname;
-- 預期：不應再出現任何「對象 = {public} 且條件 = true」的列


-- ============================================================
--  還原指令（若 App 出問題需要緊急恢復）
--  注意：這會回到「任何人都能讀寫全部資料」的狀態，僅供緊急使用
-- ============================================================
-- create policy "public read write" on public.trips    for all to public using (true) with check (true);
-- create policy "public read write" on public.members  for all to public using (true) with check (true);
-- create policy "public read write" on public.expenses for all to public using (true) with check (true);
-- create policy own_rows on public.user_trips for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
