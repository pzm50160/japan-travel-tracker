-- ============================================================
--  選用：把無人認領的舊旅程掛到你的帳號底下
--
--  現況（2026-08-18 確認）：
--    九州之旅        → 已綁 tooya47@yahoo.com.tw  ✅ 不用處理
--    南新名古屋音樂交流 → 已綁 r5500160 + ily64247   ✅ 不用處理
--    阿里山          → 已綁 r5500160              ✅ 不用處理
--    以下三個無人認領：test(7筆)、日本(1筆)、123(1筆)
--
--  RLS 修好後，無人認領的旅程任何人都看不到（資料仍在，只是沒有入口）。
--  若想保留存取權，執行本檔把它們掛到你的帳號。
--  不執行也不會有任何損壞，之後隨時可以補。
-- ============================================================

-- 把「日本」(1筆花費，建立者為『名』) 掛給 r5500160@gmail.com
insert into public.user_trips (user_id, trip_id, member_id)
select 'a6689519-874a-46f6-9b03-2dd4e6c5f8e9', m.trip_id, m.id
from public.members m
where m.trip_id = 'trip_1777680590032'
  and not exists (
    select 1 from public.user_trips ut
    where ut.trip_id = m.trip_id
      and ut.user_id = 'a6689519-874a-46f6-9b03-2dd4e6c5f8e9'
  )
limit 1;

-- 若也想保留 test(7筆) 和 123(1筆)，取消下面兩段的註解後執行

-- insert into public.user_trips (user_id, trip_id, member_id)
-- select 'a6689519-874a-46f6-9b03-2dd4e6c5f8e9', m.trip_id, m.id
-- from public.members m
-- where m.trip_id = 'trip_1779204698245'
--   and not exists (select 1 from public.user_trips ut
--                   where ut.trip_id = m.trip_id
--                     and ut.user_id = 'a6689519-874a-46f6-9b03-2dd4e6c5f8e9')
-- limit 1;

-- insert into public.user_trips (user_id, trip_id, member_id)
-- select 'a6689519-874a-46f6-9b03-2dd4e6c5f8e9', m.trip_id, m.id
-- from public.members m
-- where m.trip_id = 'trip_1777463153162'
--   and not exists (select 1 from public.user_trips ut
--                   where ut.trip_id = m.trip_id
--                     and ut.user_id = 'a6689519-874a-46f6-9b03-2dd4e6c5f8e9')
-- limit 1;


-- 執行後確認
select t.name as 旅程, coalesce(u.email,'❌無人認領') as 擁有者,
       (select count(*) from public.expenses e where e.trip_id=t.id) as 花費
from public.trips t
left join public.user_trips ut on ut.trip_id = t.id
left join auth.users u on u.id = ut.user_id
where exists (select 1 from public.expenses e where e.trip_id = t.id)
   or t.id = 'trip_1786805864728'
order by 花費 desc;
