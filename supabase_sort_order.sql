-- ============================================================
--  同一天之內的排序
--
--  問題：紀錄只依日期分組排序，同一天有好幾筆時先後是亂的
--        （原本靠 created_at，跟實際消費順序無關）。
--
--  做法：加一個 sort_order 欄位，數值 = 當天的分鐘數（0~1439）
--        - 掃描：AI 讀收據上印的時間（例如 12:38 → 758）
--        - 手動記帳：用當下時間
--        - 手動調整順序：寫入相鄰兩筆的中間值，所以用 double
--          （不必每次重新編號整天的資料）
--
--  沒有值的舊資料排在最後，不影響現有帳目。
--  可重複執行。
-- ============================================================

alter table public.expenses
  add column if not exists sort_order double precision;

comment on column public.expenses.sort_order is
  '同一天內的排序值，當天分鐘數 0~1439；手動調整時可為小數。null 表示未設定，排在最後。';


-- ── 檢查 ────────────────────────────────────────────────
select column_name as 欄位, data_type as 型別, is_nullable as 可空
from information_schema.columns
where table_schema='public' and table_name='expenses' and column_name='sort_order';


-- ============================================================
--  還原
-- ============================================================
-- alter table public.expenses drop column if exists sort_order;
