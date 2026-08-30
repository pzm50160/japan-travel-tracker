-- 把「真實時間」與「排序位置」拆成兩個欄位
--
-- 起因：sort_order 一個欄位同時被拿來排序、又被拿來顯示列表上的 🕐 時間。
-- 掃描時讀不到收據上印的時間就退回「掃描當下的時間」，於是凌晨補掃的收據
-- 整批顯示成 🕐 01:50 這種根本不存在的用餐時間。
--
-- time_min     真實時間（當天分鐘數 0~1439）。只有「收據上印的」或「使用者自己填的」
--              才會有值；null ＝ 不明，列表就不顯示時間。
-- sort_manual  這筆的位置是手動拖曳排出來的（不再跟著時間走），列表上標一個 ↕。
--
-- 舊資料刻意不回填 time_min：現有的 sort_order 有一部分是掃描當下的時間、不是真的，
-- 回填等於把錯的時間變成正式資料。舊帳目維持「不顯示時間」，要的話進去自己填。
-- 排序不受影響 —— 排序仍然看 sort_order，舊值原封不動。

alter table public.expenses add column if not exists time_min    smallint;
alter table public.expenses add column if not exists sort_manual boolean not null default false;

comment on column public.expenses.time_min    is '真實時間（當天分鐘數 0~1439），null＝不明，不顯示';
comment on column public.expenses.sort_manual is '位置是手動拖曳排出來的，列表標 ↕';

-- 確認用：兩個欄位都在就會回一列
select column_name, data_type, column_default
from information_schema.columns
where table_schema='public' and table_name='expenses' and column_name in ('time_min','sort_manual');
