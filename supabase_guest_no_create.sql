-- ============================================================
--  免註冊（匿名）身分不得自行建立旅程
--
--  原因：
--    介面上那顆按鈕寫的是「免註冊，用邀請碼加入」，設計本意是
--    只能加入既有旅程。但 trips 的新增政策只檢查「有沒有身分」，
--    匿名身分同樣通過，所以免註冊者其實可以開新旅程。
--
--    匿名身分綁在該裝置的瀏覽器，換手機或清除資料就找不回來，
--    它建立的旅程會變成無主旅程（專案裡已經有三個這種旅程）。
--
--  前置：supabase_guest.sql 已執行（本檔沿用其中的 is_anon_user()）
--  可重複執行。還原指令在最下方。
-- ============================================================

drop policy if exists trips_insert on public.trips;
create policy trips_insert on public.trips
  for insert to authenticated
  with check (auth.uid() is not null and not public.is_anon_user());


-- ── 檢查 ────────────────────────────────────────────────
select policyname as 政策, cmd as 動作, with_check as 新增條件
from pg_policies
where schemaname='public' and tablename='trips'
order by policyname;


-- ============================================================
--  還原（讓免註冊者也能建立旅程）
-- ============================================================
-- drop policy if exists trips_insert on public.trips;
-- create policy trips_insert on public.trips
--   for insert to authenticated
--   with check (auth.uid() is not null);
