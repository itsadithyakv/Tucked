-- 0017 announcements: quiet centre-wide notices (Later channel — never push,
-- they appear in the family app's home). Supervisors post; members read.

create table public.announcement (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  title text not null,
  body text not null,
  created_by uuid not null references public.person (id),
  published_at timestamptz not null default now()
);

create index announcement_centre_recent on public.announcement (centre_id, published_at desc);

alter table public.announcement enable row level security;

create policy announcement_select on public.announcement
  for select using (centre_id in (select app.member_centre_ids()));

create policy announcement_insert on public.announcement
  for insert with check (
    app.has_role(centre_id, array['supervisor', 'licensee_admin']::public.role_id[])
    and created_by = app.current_person_id()
  );

create trigger announcement_audit
  after insert on public.announcement
  for each row execute function app.audit_row();

create trigger announcement_no_delete
  before delete on public.announcement
  for each row execute function app.block_mutation();
