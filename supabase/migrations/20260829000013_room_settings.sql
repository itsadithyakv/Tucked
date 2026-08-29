-- 0013 room settings: the sleep policy's direct-visual-check interval
-- (s. 33.1 — the frequency is set by the centre's sleep policy; the room
-- device prompts at this interval).

alter table public.centre
  add column sleep_check_interval_minutes integer not null default 15
  check (sleep_check_interval_minutes between 5 and 30);
