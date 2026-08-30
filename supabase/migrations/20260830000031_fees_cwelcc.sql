-- 0031 fees, the CWELCC cap, and CRA receipts (Part 2, CWELCC guidelines,
-- O. Reg. 138/15 s. 27.1). The decisions this schema encodes:
--
--   * TUCKED RECORDS MONEY; IT DOES NOT MOVE MONEY. There is no card
--     processing here and no parent-side payment fee, because a family should
--     never be charged for the privilege of paying their child care fees. The
--     centre records what it billed and what actually arrived (pre-authorised
--     debit, e-transfer, cheque). That keeps PCI scope out of a database full
--     of children's records and keeps the running cost near zero.
--   * THE CWELCC CAP IS ENFORCED IN THE DATABASE, AND THE CAP IS DATA. A base
--     fee above the cap cannot be saved at an enrolled centre. The cap sits in
--     cwelcc_parameter with effective dates, because it moves — and when it
--     moves, it is a row, not a deployment.
--   * ELIGIBILITY IS COMPUTED, NEVER TICKED: under six, or turning six before
--     30 June. Nobody can quietly mark a child ineligible to charge them more.
--   * A NON-BASE FEE MUST BE OPTIONAL. The schema cannot express a non-base
--     fee that is a condition of enrolment, because that is the violation.
--   * MONEY NEVER GATES A RECORD (§9.14). No policy in this file — or any
--     other — reads a balance. A family in arrears reads their child's record
--     and their child is signed in exactly as before. pgTAP proves it.
--   * A CRA RECEIPT IS ISSUED FROM WHAT WAS RECEIVED, not what was billed,
--     because that is what the CRA line actually is. It snapshots the payer,
--     the child, the provider and the amount, so the six-year financial record
--     survives the three-year children's-record anonymiser — and then runs out
--     on its own six-year clock.
--   * NO SOCIAL INSURANCE NUMBERS. An individual provider's receipt carries a
--     SIN; a licensed centre's carries a business number. We serve centres, we
--     store the business number, and we will not hold a SIN in a database that
--     also holds photographs of children. A provider who needs one writes it
--     on the receipt themselves.

-- ── who is issuing the receipt ──────────────────────────────────────────────
alter table public.licensee
  add column business_number text,
  -- the name that belongs on a tax receipt, where it differs from the legal name
  add column receipt_name text;

-- ── the CWELCC parameters, as data ──────────────────────────────────────────
create table public.cwelcc_parameter (
  id uuid primary key default gen_random_uuid(),
  jurisdiction_code text not null references public.jurisdiction (code),
  effective_on date not null,
  -- the most a base fee may be for an eligible child, per day
  base_fee_cap numeric(10, 2) not null check (base_fee_cap > 0),
  -- a child is eligible if under this age, or turning it before the cutoff
  eligible_under_years integer not null default 6,
  eligible_cutoff_month integer not null default 6,
  eligible_cutoff_day integer not null default 30,
  note text not null,
  unique (jurisdiction_code, effective_on)
);

insert into public.cwelcc_parameter
  (jurisdiction_code, effective_on, base_fee_cap, note) values
  ('CA-ON', '2022-12-31', 12.00,
   'Interim: fees reduced by 52.75% from the March 2022 level.'),
  ('CA-ON', '2025-01-01', 22.00,
   'Base fees capped at $22.00 per day for an eligible child, or the lower prior fee where it was lower.');

alter table public.cwelcc_parameter enable row level security;
create policy cwelcc_parameter_select on public.cwelcc_parameter for select using (true);

-- The cap in force at a centre on a date.
create or replace function app.cwelcc_cap(p_centre uuid, p_on date)
returns numeric
language sql stable security definer
set search_path = public
as $$
  select p.base_fee_cap
  from public.cwelcc_parameter p
  join public.centre c on c.jurisdiction_code = p.jurisdiction_code
  where c.id = p_centre and p.effective_on <= p_on
  order by p.effective_on desc
  limit 1
$$;

-- PostgREST-callable wrapper (the app schema is not exposed over the API).
create or replace function public.cwelcc_cap_today(p_centre uuid)
returns numeric
language sql stable security definer
set search_path = public
as $$ select app.cwelcc_cap(p_centre, current_date) $$;

-- Under six, or turning six before the cutoff (30 June) in the year of the
-- date being asked about. Computed from the date of birth, never stored.
create or replace function app.cwelcc_eligible(p_centre uuid, p_child uuid, p_on date)
returns boolean
language plpgsql stable security definer
set search_path = public
as $$
declare
  dob date;
  param public.cwelcc_parameter;
  sixth_birthday date;
  cutoff date;
begin
  select ch.date_of_birth into dob from public.child ch where ch.id = p_child;
  if dob is null then return false; end if;

  select p.* into param
  from public.cwelcc_parameter p
  join public.centre c on c.jurisdiction_code = p.jurisdiction_code
  where c.id = p_centre and p.effective_on <= p_on
  order by p.effective_on desc limit 1;
  if param.id is null then return false; end if;

  sixth_birthday := dob + make_interval(years => param.eligible_under_years);
  if p_on < sixth_birthday then return true; end if;

  -- already six: still eligible for the rest of the funding year if the
  -- birthday fell before the cutoff
  cutoff := make_date(extract(year from p_on)::int, param.eligible_cutoff_month, param.eligible_cutoff_day);
  return sixth_birthday <= cutoff and p_on <= cutoff;
end;
$$;

-- ── what the centre charges ─────────────────────────────────────────────────
create table public.fee_schedule (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  age_group_preset public.age_group_preset not null,
  -- the daily base fee for an eligible child; the unfunded fee for everyone else
  base_daily_fee numeric(10, 2) not null check (base_daily_fee >= 0),
  unfunded_daily_fee numeric(10, 2) check (unfunded_daily_fee >= 0),
  effective_on date not null,
  recorded_by uuid not null references public.person (id),
  created_at timestamptz not null default now(),
  unique (centre_id, age_group_preset, effective_on)
);

-- Non-base fees: optional, always, or they are not non-base fees.
create table public.fee_item (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  code text not null,
  label text not null,
  kind text not null check (kind in ('base', 'non_base')),
  amount numeric(10, 2) not null check (amount >= 0),
  -- what it is for, in the words the handbook uses
  description text not null,
  -- a non-base fee is never a condition of enrolment; the check below makes
  -- the alternative unrepresentable
  optional boolean not null default true,
  active boolean not null default true,
  recorded_by uuid not null references public.person (id),
  created_at timestamptz not null default now(),
  unique (centre_id, code),
  constraint non_base_fees_are_always_optional
    check (kind = 'base' or optional)
);

-- ── the ledger ──────────────────────────────────────────────────────────────
create table public.fee_charge (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  household_id uuid not null references public.household (id),
  child_id uuid references public.child (id),
  fee_item_id uuid references public.fee_item (id),
  kind text not null check (kind in ('base', 'non_base')),
  description text not null,
  period_start date not null,
  period_end date not null,
  days integer check (days is null or days > 0),
  unit_amount numeric(10, 2),
  amount numeric(10, 2) not null check (amount >= 0),
  -- what the cap was when this was charged, for the record
  cap_at_charge numeric(10, 2),
  eligible_at_charge boolean,
  recorded_by uuid not null references public.person (id),
  created_at timestamptz not null default now(),
  constraint fee_charge_period check (period_end >= period_start)
);

create index fee_charge_household on public.fee_charge (household_id, period_start);

-- A charge is never edited. A mistake is a credit note beside it.
create table public.fee_credit (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  household_id uuid not null references public.household (id),
  charge_id uuid references public.fee_charge (id),
  amount numeric(10, 2) not null check (amount > 0),
  reason text not null,
  recorded_by uuid not null references public.person (id),
  created_at timestamptz not null default now()
);

create table public.fee_payment (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  household_id uuid not null references public.household (id),
  amount numeric(10, 2) not null check (amount > 0),
  method text not null check (method in ('pre_authorised_debit', 'e_transfer', 'cheque', 'cash', 'subsidy', 'other')),
  received_on date not null,
  reference text,
  -- the person the receipt will name, where the household has more than one
  payer_person_id uuid references public.person (id),
  recorded_by uuid not null references public.person (id),
  created_at timestamptz not null default now()
);

create index fee_payment_household on public.fee_payment (household_id, received_on);

-- ── CRA receipts ────────────────────────────────────────────────────────────
create table public.cra_receipt (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  household_id uuid not null references public.household (id),
  tax_year integer not null,
  receipt_number text not null,
  -- snapshots, so the receipt still reads correctly in six years even after
  -- the children's-record anonymiser has run at three
  provider_name text not null,
  provider_business_number text,
  provider_address text not null,
  payer_name text not null,
  payer_person_id uuid references public.person (id),
  total_amount numeric(10, 2) not null check (total_amount >= 0),
  issued_at timestamptz not null default now(),
  issued_by uuid not null references public.person (id),
  -- a reissue supersedes rather than overwrites
  replaces_id uuid references public.cra_receipt (id),
  replaced_at timestamptz,
  replaced_by_id uuid references public.cra_receipt (id),
  redacted_at timestamptz,
  created_at timestamptz not null default now(),
  unique (centre_id, receipt_number)
);

create table public.cra_receipt_line (
  id uuid primary key default gen_random_uuid(),
  receipt_id uuid not null references public.cra_receipt (id),
  centre_id uuid not null references public.centre (id),
  child_id uuid references public.child (id),
  child_name text not null,
  child_date_of_birth date,
  period_start date not null,
  period_end date not null,
  amount numeric(10, 2) not null check (amount >= 0)
);

-- ── leaving CWELCC: thirty days' written notice ─────────────────────────────
create table public.cwelcc_withdrawal_notice (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  notice_given_on date not null default current_date,
  effective_on date not null,
  reason text not null,
  recorded_by uuid not null references public.person (id),
  created_at timestamptz not null default now(),
  -- CWELCC guidelines: thirty days' written notice
  constraint cwelcc_notice_is_thirty_days
    check (effective_on >= notice_given_on + 30)
);

-- Delivery proof, per parent and per employee.
create table public.cwelcc_notice_receipt (
  id uuid primary key default gen_random_uuid(),
  notice_id uuid not null references public.cwelcc_withdrawal_notice (id),
  centre_id uuid not null references public.centre (id),
  person_id uuid not null references public.person (id),
  audience text not null check (audience in ('parent', 'employee')),
  method text not null check (method in ('in_app', 'email', 'signed_paper', 'hand_delivered')),
  delivered_at timestamptz not null default now(),
  recorded_by uuid references public.person (id),
  created_at timestamptz not null default now(),
  unique (notice_id, person_id)
);

-- ── rules ───────────────────────────────────────────────────────────────────
-- The cap, at the point of saving a fee schedule.
create or replace function app.fee_schedule_rules()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  enrolled boolean;
  cap numeric;
begin
  select c.cwelcc_enrolled into enrolled from public.centre c where c.id = new.centre_id;
  if enrolled then
    cap := app.cwelcc_cap(new.centre_id, new.effective_on);
    if cap is not null and new.base_daily_fee > cap then
      raise exception 'the base fee for an eligible child cannot be more than $% a day under CWELCC (you entered $%)',
        to_char(cap, 'FM999999.00'), to_char(new.base_daily_fee, 'FM999999.00');
    end if;
  end if;
  return new;
end;
$$;

create trigger fee_schedule_rules
  before insert or update on public.fee_schedule
  for each row execute function app.fee_schedule_rules();

-- The cap again, at the point of actually charging a family — because a
-- schedule saved before the centre joined CWELCC must not become a charge
-- above the cap afterwards.
create or replace function app.fee_charge_rules()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  enrolled boolean;
  cap numeric;
  eligible boolean;
begin
  if tg_op = 'UPDATE' then
    raise exception 'a charge is never edited; record a credit note beside it';
  end if;
  if coalesce(trim(new.description), '') = '' then
    raise exception 'a charge says what it is for';
  end if;

  select c.cwelcc_enrolled into enrolled from public.centre c where c.id = new.centre_id;
  cap := app.cwelcc_cap(new.centre_id, new.period_start);
  eligible := new.child_id is not null and app.cwelcc_eligible(new.centre_id, new.child_id, new.period_start);
  new.cap_at_charge := cap;
  new.eligible_at_charge := eligible;

  if enrolled and eligible and new.kind = 'base' and new.days is not null and new.days > 0 then
    if round(new.amount / new.days, 2) > cap then
      raise exception 'that is $% a day for an eligible child; the CWELCC cap is $%',
        to_char(round(new.amount / new.days, 2), 'FM999999.00'), to_char(cap, 'FM999999.00');
    end if;
  end if;
  return new;
end;
$$;

create trigger fee_charge_rules
  before insert or update on public.fee_charge
  for each row execute function app.fee_charge_rules();

create or replace function app.cra_receipt_rules()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  -- Only the supersede and redaction fields ever move. A receipt a family has
  -- already given to the CRA cannot change under them.
  if row(new.centre_id, new.household_id, new.tax_year, new.receipt_number,
         new.provider_name, new.provider_business_number, new.payer_name,
         new.total_amount, new.issued_at, new.issued_by)
     is distinct from
     row(old.centre_id, old.household_id, old.tax_year, old.receipt_number,
         old.provider_name, old.provider_business_number, old.payer_name,
         old.total_amount, old.issued_at, old.issued_by)
     and not app.is_anonymising() then
    raise exception 'an issued receipt is never altered; issue a replacement';
  end if;
  return new;
end;
$$;

create trigger cra_receipt_rules
  before update on public.cra_receipt
  for each row execute function app.cra_receipt_rules();

-- ── visibility ──────────────────────────────────────────────────────────────
alter table public.fee_schedule enable row level security;
alter table public.fee_item enable row level security;
alter table public.fee_charge enable row level security;
alter table public.fee_credit enable row level security;
alter table public.fee_payment enable row level security;
alter table public.cra_receipt enable row level security;
alter table public.cra_receipt_line enable row level security;
alter table public.cwelcc_withdrawal_notice enable row level security;
alter table public.cwelcc_notice_receipt enable row level security;

-- What a centre charges is not a secret from the families paying it.
create policy fee_schedule_select on public.fee_schedule
  for select using (centre_id in (select app.member_centre_ids()));
create policy fee_item_select on public.fee_item
  for select using (centre_id in (select app.member_centre_ids()));

-- A family sees its own ledger; leadership sees the centre's. Educators do
-- not: what a family pays is none of the room's business.
create policy fee_charge_select on public.fee_charge
  for select using (
    app.has_role(centre_id, array['supervisor', 'licensee_admin']::public.role_id[])
    or household_id in (select app.my_household_ids())
  );
create policy fee_credit_select on public.fee_credit
  for select using (
    app.has_role(centre_id, array['supervisor', 'licensee_admin']::public.role_id[])
    or household_id in (select app.my_household_ids())
  );
create policy fee_payment_select on public.fee_payment
  for select using (
    app.has_role(centre_id, array['supervisor', 'licensee_admin']::public.role_id[])
    or household_id in (select app.my_household_ids())
  );
create policy cra_receipt_select on public.cra_receipt
  for select using (
    app.has_role(centre_id, array['supervisor', 'licensee_admin']::public.role_id[])
    or household_id in (select app.my_household_ids())
  );
create policy cra_receipt_line_select on public.cra_receipt_line
  for select using (
    app.has_role(centre_id, array['supervisor', 'licensee_admin']::public.role_id[])
    or exists (
      select 1 from public.cra_receipt r
      where r.id = cra_receipt_line.receipt_id
        and r.household_id in (select app.my_household_ids())
    )
  );

-- Leaving CWELCC is everybody's business — that is the point of the notice.
create policy cwelcc_notice_select on public.cwelcc_withdrawal_notice
  for select using (centre_id in (select app.member_centre_ids()));
create policy cwelcc_notice_receipt_select on public.cwelcc_notice_receipt
  for select using (
    app.has_role(centre_id, array['supervisor', 'licensee_admin']::public.role_id[])
    or person_id = app.current_person_id()
  );
-- Writes via RPCs only.

-- O. Reg. 138/15 s. 27.1: six years, and nothing here is ever deleted.
create trigger fee_charge_no_delete before delete on public.fee_charge
  for each row execute function app.block_mutation();
create trigger fee_credit_no_change before update or delete on public.fee_credit
  for each row execute function app.block_mutation();
create trigger fee_payment_no_change before update or delete on public.fee_payment
  for each row execute function app.block_mutation();
create trigger cra_receipt_no_delete before delete on public.cra_receipt
  for each row execute function app.block_mutation();
create trigger cra_receipt_line_no_delete before delete on public.cra_receipt_line
  for each row execute function app.block_mutation();
create trigger cwelcc_notice_no_change before update or delete on public.cwelcc_withdrawal_notice
  for each row execute function app.block_mutation();
create trigger cwelcc_notice_receipt_no_change before update or delete on public.cwelcc_notice_receipt
  for each row execute function app.block_mutation();

create trigger fee_charge_audit after insert on public.fee_charge
  for each row execute function app.audit_row();
create trigger fee_payment_audit after insert on public.fee_payment
  for each row execute function app.audit_row();
create trigger fee_credit_audit after insert on public.fee_credit
  for each row execute function app.audit_row();
create trigger cra_receipt_audit after insert or update on public.cra_receipt
  for each row execute function app.audit_row();
create trigger fee_schedule_audit after insert or update on public.fee_schedule
  for each row execute function app.audit_row();
create trigger fee_item_audit after insert or update on public.fee_item
  for each row execute function app.audit_row();
create trigger cwelcc_notice_audit after insert on public.cwelcc_withdrawal_notice
  for each row execute function app.audit_row();

-- ── what a family owes ──────────────────────────────────────────────────────
create view public.household_balance
with (security_invoker = on) as
select
  h.id as household_id,
  h.centre_id,
  h.name,
  coalesce((select sum(c.amount) from public.fee_charge c where c.household_id = h.id), 0) as charged,
  coalesce((select sum(cr.amount) from public.fee_credit cr where cr.household_id = h.id), 0) as credited,
  coalesce((select sum(p.amount) from public.fee_payment p where p.household_id = h.id), 0) as paid,
  coalesce((select sum(c.amount) from public.fee_charge c where c.household_id = h.id), 0)
    - coalesce((select sum(cr.amount) from public.fee_credit cr where cr.household_id = h.id), 0)
    - coalesce((select sum(p.amount) from public.fee_payment p where p.household_id = h.id), 0) as balance
from public.household h;

-- ── RPCs ────────────────────────────────────────────────────────────────────
create or replace function public.set_fee_schedule(
  p_centre uuid,
  p_age_group public.age_group_preset,
  p_base_daily numeric,
  p_unfunded_daily numeric,
  p_effective_on date,
  p_recorder uuid,
  p_pin text
) returns public.fee_schedule
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  result public.fee_schedule;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);
  if not exists (
    select 1 from public.person_role pr
    where pr.person_id = recorder and pr.centre_id = p_centre and pr.active
      and pr.role in ('licensee_admin', 'supervisor')
  ) then
    raise exception 'fees are set by the licensee';
  end if;

  insert into public.fee_schedule (
    centre_id, age_group_preset, base_daily_fee, unfunded_daily_fee, effective_on, recorded_by
  ) values (
    p_centre, p_age_group, p_base_daily, p_unfunded_daily,
    coalesce(p_effective_on, current_date), recorder
  )
  on conflict (centre_id, age_group_preset, effective_on)
    do update set base_daily_fee = excluded.base_daily_fee,
                  unfunded_daily_fee = excluded.unfunded_daily_fee,
                  recorded_by = excluded.recorded_by
  returning * into result;
  return result;
end;
$$;

create or replace function public.set_fee_item(
  p_centre uuid,
  p_code text,
  p_label text,
  p_kind text,
  p_amount numeric,
  p_description text,
  p_active boolean,
  p_recorder uuid,
  p_pin text
) returns public.fee_item
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  result public.fee_item;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);
  if not exists (
    select 1 from public.person_role pr
    where pr.person_id = recorder and pr.centre_id = p_centre and pr.active
      and pr.role in ('licensee_admin', 'supervisor')
  ) then
    raise exception 'fees are set by the licensee';
  end if;
  if coalesce(trim(coalesce(p_description, '')), '') = '' then
    raise exception 'say what the fee is for — the handbook has to explain it (s. 45)';
  end if;

  insert into public.fee_item (centre_id, code, label, kind, amount, description, optional, active, recorded_by)
  values (p_centre, p_code, trim(p_label), p_kind, p_amount, trim(p_description),
          p_kind <> 'base', coalesce(p_active, true), recorder)
  on conflict (centre_id, code)
    do update set label = excluded.label, kind = excluded.kind, amount = excluded.amount,
                  description = excluded.description, optional = excluded.optional,
                  active = excluded.active, recorded_by = excluded.recorded_by
  returning * into result;
  return result;
end;
$$;

create or replace function public.record_fee_charge(
  p_centre uuid,
  p_household uuid,
  p_child uuid,
  p_kind text,
  p_description text,
  p_period_start date,
  p_period_end date,
  p_days integer,
  p_amount numeric,
  p_fee_item uuid,
  p_recorder uuid,
  p_pin text
) returns public.fee_charge
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  result public.fee_charge;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);
  if not exists (
    select 1 from public.person_role pr
    where pr.person_id = recorder and pr.centre_id = p_centre and pr.active
      and pr.role in ('licensee_admin', 'supervisor')
  ) then
    raise exception 'fees are recorded by the licensee';
  end if;

  insert into public.fee_charge (
    centre_id, household_id, child_id, fee_item_id, kind, description,
    period_start, period_end, days, unit_amount, amount, recorded_by
  ) values (
    p_centre, p_household, p_child, p_fee_item, p_kind, trim(p_description),
    p_period_start, coalesce(p_period_end, p_period_start), p_days,
    case when p_days is not null and p_days > 0 then round(p_amount / p_days, 2) else null end,
    p_amount, recorder
  ) returning * into result;
  return result;
end;
$$;

create or replace function public.record_fee_credit(
  p_centre uuid,
  p_household uuid,
  p_charge uuid,
  p_amount numeric,
  p_reason text,
  p_recorder uuid,
  p_pin text
) returns public.fee_credit
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  result public.fee_credit;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);
  if coalesce(trim(coalesce(p_reason, '')), '') = '' then
    raise exception 'a credit says why — that is the whole of the correction';
  end if;
  insert into public.fee_credit (centre_id, household_id, charge_id, amount, reason, recorded_by)
  values (p_centre, p_household, p_charge, p_amount, trim(p_reason), recorder)
  returning * into result;
  return result;
end;
$$;

create or replace function public.record_fee_payment(
  p_centre uuid,
  p_household uuid,
  p_amount numeric,
  p_method text,
  p_received_on date,
  p_reference text,
  p_payer uuid,
  p_recorder uuid,
  p_pin text
) returns public.fee_payment
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  result public.fee_payment;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);
  if coalesce(p_received_on, current_date) > current_date then
    raise exception 'a payment is recorded when it arrives, not before';
  end if;

  insert into public.fee_payment (
    centre_id, household_id, amount, method, received_on, reference, payer_person_id, recorded_by
  ) values (
    p_centre, p_household, p_amount, p_method, coalesce(p_received_on, current_date),
    nullif(trim(coalesce(p_reference, '')), ''), p_payer, recorder
  ) returning * into result;
  return result;
end;
$$;

-- ── the February one-tap ────────────────────────────────────────────────────
-- Issued from what was RECEIVED in the year, allocated across the household's
-- children in proportion to what each was charged — the standard, defensible
-- method, and the one an auditor can reproduce from the ledger.
create or replace function public.issue_cra_receipt(
  p_centre uuid,
  p_household uuid,
  p_year integer,
  p_recorder uuid,
  p_pin text
) returns public.cra_receipt
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  ctr public.centre;
  lic public.licensee;
  paid numeric;
  charged numeric;
  payer_id uuid;
  payer text;
  seq integer;
  previous public.cra_receipt;
  result public.cra_receipt;
  kid record;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);
  if not exists (
    select 1 from public.person_role pr
    where pr.person_id = recorder and pr.centre_id = p_centre and pr.active
      and pr.role in ('licensee_admin', 'supervisor')
  ) then
    raise exception 'receipts are issued by the licensee';
  end if;
  if p_year > extract(year from current_date)::int then
    raise exception 'that tax year has not happened yet';
  end if;

  select * into ctr from public.centre where id = p_centre;
  select * into lic from public.licensee where id = ctr.licensee_id;
  if coalesce(trim(coalesce(lic.business_number, '')), '') = '' then
    raise exception 'add the licensee''s business number before issuing receipts — the CRA needs it on the receipt';
  end if;

  select coalesce(sum(amount), 0) into paid
  from public.fee_payment
  where household_id = p_household and extract(year from received_on) = p_year;
  if paid = 0 then
    raise exception 'no payments were received from this family in %', p_year;
  end if;

  -- an earlier receipt for the same year is superseded, not overwritten
  select * into previous from public.cra_receipt
  where household_id = p_household and tax_year = p_year and replaced_at is null;

  select coalesce(sum(amount), 0) into charged
  from public.fee_charge
  where household_id = p_household
    and extract(year from period_start) = p_year;

  select hm.person_id, p.full_name into payer_id, payer
  from public.household_member hm
  join public.person p on p.id = hm.person_id
  where hm.household_id = p_household and hm.revoked_at is null and hm.can_bill
  order by hm.created_at
  limit 1;
  if payer is null then
    select hm.person_id, p.full_name into payer_id, payer
    from public.household_member hm
    join public.person p on p.id = hm.person_id
    where hm.household_id = p_household and hm.revoked_at is null
    order by hm.created_at limit 1;
  end if;
  if payer is null then
    raise exception 'this household has nobody to address the receipt to';
  end if;

  select coalesce(max(substring(receipt_number from '\d+$')::int), 0) + 1 into seq
  from public.cra_receipt where centre_id = p_centre and tax_year = p_year;

  insert into public.cra_receipt (
    centre_id, household_id, tax_year, receipt_number, provider_name,
    provider_business_number, provider_address, payer_name, payer_person_id,
    total_amount, issued_by, replaces_id
  ) values (
    p_centre, p_household, p_year,
    p_year::text || '-' || lpad(seq::text, 4, '0'),
    coalesce(nullif(trim(coalesce(lic.receipt_name, '')), ''), lic.legal_name),
    lic.business_number, ctr.address, payer, payer_id,
    paid, recorder, previous.id
  ) returning * into result;

  -- one line per child, the year's payments split by what each was charged
  for kid in
    select
      ch.id, ch.full_name, ch.date_of_birth,
      coalesce(sum(fc.amount), 0) as child_charged,
      min(fc.period_start) as first_period,
      max(fc.period_end) as last_period
    from public.child_household chh
    join public.child ch on ch.id = chh.child_id
    left join public.fee_charge fc
      on fc.child_id = ch.id and fc.household_id = p_household
        and extract(year from fc.period_start) = p_year
    where chh.household_id = p_household
    group by ch.id, ch.full_name, ch.date_of_birth
  loop
    insert into public.cra_receipt_line (
      receipt_id, centre_id, child_id, child_name, child_date_of_birth,
      period_start, period_end, amount
    ) values (
      result.id, p_centre, kid.id, kid.full_name, kid.date_of_birth,
      coalesce(kid.first_period, make_date(p_year, 1, 1)),
      coalesce(kid.last_period, make_date(p_year, 12, 31)),
      case when charged > 0 then round(paid * (kid.child_charged / charged), 2) else 0 end
    );
  end loop;

  if previous.id is not null then
    update public.cra_receipt
    set replaced_at = now(), replaced_by_id = result.id
    where id = previous.id;
  end if;

  -- O. Reg. 138/15 s. 27.1: six years, counted from the end of the tax year
  insert into public.retention_clock (centre_id, subject_table, subject_id, kind, starts_at, purge_after)
  values (p_centre, 'cra_receipt', result.id::text, 'financial',
          make_date(p_year, 12, 31), make_date(p_year + 6, 12, 31))
  on conflict (subject_table, subject_id, kind) do nothing;

  return result;
end;
$$;

-- ── leaving CWELCC ──────────────────────────────────────────────────────────
create or replace function public.record_cwelcc_withdrawal(
  p_centre uuid,
  p_effective_on date,
  p_reason text,
  p_recorder uuid,
  p_pin text
) returns public.cwelcc_withdrawal_notice
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  result public.cwelcc_withdrawal_notice;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);
  if not exists (
    select 1 from public.person_role pr
    where pr.person_id = recorder and pr.centre_id = p_centre and pr.active
      and pr.role = 'licensee_admin'
  ) then
    raise exception 'only the licensee withdraws from CWELCC';
  end if;
  if coalesce(trim(coalesce(p_reason, '')), '') = '' then
    raise exception 'record why — every family and every employee is about to be told';
  end if;

  insert into public.cwelcc_withdrawal_notice (centre_id, effective_on, reason, recorded_by)
  values (p_centre, p_effective_on, trim(p_reason), recorder)
  returning * into result;

  -- the notice itself, to every consenting parent and every employee
  insert into public.notification (
    centre_id, recipient_person_id, channel, event_type, title, body,
    requires_acknowledgement, created_by, ref_id
  )
  select distinct
    p_centre, pr.person_id, 'now'::public.notification_channel, 'cwelcc_withdrawal',
    'Important: fees are changing on ' || to_char(result.effective_on, 'FMDD Mon YYYY'),
    'The centre is leaving the Canada-Wide Early Learning and Child Care system with effect from ' ||
    to_char(result.effective_on, 'FMDD Mon YYYY') || '. ' || result.reason,
    true, recorder, result.id
  from public.person_role pr
  where pr.centre_id = p_centre and pr.active;
  return result;
end;
$$;

create or replace function public.record_cwelcc_notice_delivery(
  p_notice uuid,
  p_person uuid,
  p_audience text,
  p_method text,
  p_recorder uuid,
  p_pin text
) returns public.cwelcc_notice_receipt
language plpgsql security definer
set search_path = public
as $$
declare
  n public.cwelcc_withdrawal_notice;
  recorder uuid;
  result public.cwelcc_notice_receipt;
begin
  select * into n from public.cwelcc_withdrawal_notice where id = p_notice;
  if n.id is null then raise exception 'notice not found'; end if;
  recorder := app.resolve_recorder(n.centre_id, p_recorder, p_pin);

  insert into public.cwelcc_notice_receipt (
    notice_id, centre_id, person_id, audience, method, recorded_by
  ) values (p_notice, n.centre_id, p_person, p_audience, p_method, recorder)
  on conflict (notice_id, person_id) do nothing
  returning * into result;
  if result.id is null then raise exception 'that person has already been served'; end if;
  return result;
end;
$$;

-- ── six years, then the snapshots go ────────────────────────────────────────
-- The receipt row and its amounts stay forever — they are the licensee's own
-- accounting. What goes at six years is the personal information the CRA duty
-- was keeping alive: the payer's name and the children's names and birth dates.
create or replace function app.redact_cra_receipt(p_receipt uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  r public.cra_receipt;
  clock public.retention_clock;
begin
  select * into r from public.cra_receipt where id = p_receipt;
  if r.id is null then raise exception 'receipt not found'; end if;
  if r.redacted_at is not null then return; end if;

  select * into clock from public.retention_clock
  where subject_table = 'cra_receipt' and subject_id = p_receipt::text and kind = 'financial';
  if clock.id is null or clock.purge_after > current_date then
    raise exception 'a financial record is kept six years (O. Reg. 138/15 s. 27.1) — never redacted before';
  end if;

  perform set_config('app.anonymising', 'on', true);
  update public.cra_receipt
  set payer_name = 'Redacted after six years', payer_person_id = null, redacted_at = now()
  where id = p_receipt;
  update public.cra_receipt_line
  set child_name = 'Redacted after six years', child_date_of_birth = null
  where receipt_id = p_receipt;
  update public.retention_clock set anonymised_at = now() where id = clock.id;
  perform set_config('app.anonymising', '', true);
end;
$$;

create or replace function app.run_financial_sweep()
returns integer
language plpgsql security definer
set search_path = public
as $$
declare
  clock record;
  n integer := 0;
begin
  for clock in
    select subject_id from public.retention_clock
    where kind = 'financial' and subject_table = 'cra_receipt'
      and purge_after <= current_date and anonymised_at is null
  loop
    perform app.redact_cra_receipt(clock.subject_id::uuid);
    n := n + 1;
  end loop;
  return n;
end;
$$;

select cron.schedule('financial-sweep', '50 2 * * *', $$select app.run_financial_sweep()$$);

-- cra_receipt_line has no update guard of its own: the redactor above needs to
-- reach it, and RLS gives no client an update path.
create trigger cra_receipt_line_audit after insert on public.cra_receipt_line
  for each row execute function app.audit_row();
