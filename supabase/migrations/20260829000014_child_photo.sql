-- 0014: child profile photo (photos/{centre_id}/{child_id}/profile.jpg in the
-- private photos bucket; consent-gated like every photo). Rooms show initials
-- until a photo exists.

alter table public.child
  add column photo_path text;
