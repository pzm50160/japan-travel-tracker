-- ============================================================
--  免註冊（匿名登入）模式的權限規則
--
--  前置作業（必做）：
--    Supabase 後台 → Authentication → Sign In / Providers
--    → 開啟「Allow anonymous sign-ins」
--    沒開的話 App 會顯示「免註冊模式無法啟用」
--
--  設計原則：
--    免註冊者可以「參與」——加入旅程、記帳、看分攤
--    但不能「破壞」——刪旅程、改旅程設定、移除其他成員
--    正式帳號則不受限制
--
--  可重複執行。還原指令在最下方。
-- ============================================================

-- 判斷目前身分是否為匿名（免註冊）
create or replace function public.is_anon_user()
returns boolean language sql stable as
$$ select coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false); $$;


-- ── trips：免註冊者可讀，但不能修改旅程設定 ────────────────
drop policy if exists trips_update on public.trips;
create policy trips_update on public.trips
  for update to authenticated
  using (public.is_trip_member(id) and not public.is_anon_user())
  with check (public.is_trip_member(id) and not public.is_anon_user());


-- ── members：免註冊者可新增自己，但不能移除別人 ────────────
drop policy if exists members_delete on public.members;
create policy members_delete on public.members
  for delete to authenticated
  using (public.is_trip_member(trip_id) and not public.is_anon_user());


-- ── expenses：免註冊者可正常記帳與修改自己記的帳 ───────────
--   （刪除他人帳目仍開放，因為旅伴間互相修正是常態；
--     若想更嚴格，把下面這條的註解解開，改成只能刪自己記的）
--
-- drop policy if exists expenses_delete on public.expenses;
-- create policy expenses_delete on public.expenses
--   for delete to authenticated
--   using (public.is_trip_member(trip_id)
--          and (not public.is_anon_user() or created_by = (
--                select member_id from public.user_trips
--                where user_id = auth.uid() and trip_id = expenses.trip_id)));


-- ── 檢查 ────────────────────────────────────────────────
select tablename as 資料表, policyname as 政策, cmd as 動作, qual as 條件
from pg_policies
where schemaname='public' and tablename in ('trips','members','expenses')
order by tablename, policyname;


-- ============================================================
--  還原（讓免註冊者與正式帳號權限相同）
-- ============================================================
-- drop policy if exists trips_update on public.trips;
-- create policy trips_update on public.trips for update to authenticated
--   using (public.is_trip_member(id)) with check (public.is_trip_member(id));
-- drop policy if exists members_delete on public.members;
-- create policy members_delete on public.members for delete to authenticated
--   using (public.is_trip_member(trip_id));
