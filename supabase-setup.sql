-- Roster Dashboard Pro
-- Run this in the Supabase SQL editor.
-- The anon key used by the frontend is expected to be public.
-- Security comes from RLS plus the approved_users gate below.

create extension if not exists pgcrypto;

create table if not exists public.approved_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text unique not null,
  approved boolean not null default false,
  is_admin boolean not null default false,
  requested_at timestamptz not null default now(),
  approved_at timestamptz not null default now()
);

alter table public.approved_users
  alter column approved_at drop not null;

alter table public.approved_users
  add column if not exists approved boolean not null default false,
  add column if not exists is_admin boolean not null default false,
  add column if not exists requested_at timestamptz not null default now(),
  add column if not exists approved_by uuid references auth.users(id) on delete set null;

update public.approved_users
set approved = true
where approved_at is not null;

create table if not exists public.rosters (
  user_id uuid not null references auth.users(id) on delete cascade,
  date date not null,
  am_milk text not null default '',
  am_yard text not null default '',
  am_assist text not null default '',
  am_tmr_feed text not null default '',
  pm_milk text not null default '',
  pm_yard text not null default '',
  pm_assist text not null default '',
  night_check text not null default '',
  night_milk text not null default '',
  night_yard text not null default '',
  training_other text not null default '',
  holiday text not null default '',
  y_feed text not null default '',
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, date)
);

create table if not exists public.custom_staff (
  user_id uuid primary key references auth.users(id) on delete cascade,
  names text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.colours (
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  colour text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, name)
);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.approved_users (user_id, email, approved, is_admin, requested_at, approved_at)
  values (new.id, coalesce(new.email, ''), false, false, now(), null)
  on conflict (user_id) do update
  set email = excluded.email;
  return new;
end;
$$;

create or replace function public.is_admin(check_user uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.approved_users
    where user_id = check_user
      and approved = true
      and is_admin = true
  );
$$;

create or replace function public.is_approved(check_user uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.approved_users
    where user_id = check_user
      and approved = true
  );
$$;

drop trigger if exists rosters_set_updated_at on public.rosters;
create trigger rosters_set_updated_at
before update on public.rosters
for each row
execute function public.set_updated_at();

drop trigger if exists custom_staff_set_updated_at on public.custom_staff;
create trigger custom_staff_set_updated_at
before update on public.custom_staff
for each row
execute function public.set_updated_at();

drop trigger if exists colours_set_updated_at on public.colours;
create trigger colours_set_updated_at
before update on public.colours
for each row
execute function public.set_updated_at();

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row
execute function public.handle_new_user();

insert into public.approved_users (user_id, email, approved, is_admin, requested_at, approved_at)
select id, coalesce(email, ''), false, false, now(), null
from auth.users
on conflict (user_id) do update
set email = excluded.email;

alter table public.approved_users enable row level security;
alter table public.rosters enable row level security;
alter table public.custom_staff enable row level security;
alter table public.colours enable row level security;

drop policy if exists "users can view approval rows" on public.approved_users;
create policy "users can view approval rows"
on public.approved_users
for select
to authenticated
using (auth.uid() = user_id or public.is_admin(auth.uid()));

drop policy if exists "admins can update approval rows" on public.approved_users;
create policy "admins can update approval rows"
on public.approved_users
for update
to authenticated
using (public.is_admin(auth.uid()))
with check (public.is_admin(auth.uid()));

drop policy if exists "approved users manage own rosters" on public.rosters;
create policy "approved users manage own rosters"
on public.rosters
for all
to authenticated
using (
  auth.uid() = user_id
  and exists (
    select 1
    from public.approved_users au
    where au.user_id = auth.uid()
      and au.approved = true
  )
)
with check (
  auth.uid() = user_id
  and exists (
    select 1
    from public.approved_users au
    where au.user_id = auth.uid()
      and au.approved = true
  )
);

drop policy if exists "approved users manage own custom staff" on public.custom_staff;
create policy "approved users manage own custom staff"
on public.custom_staff
for all
to authenticated
using (
  auth.uid() = user_id
  and exists (
    select 1
    from public.approved_users au
    where au.user_id = auth.uid()
      and au.approved = true
  )
)
with check (
  auth.uid() = user_id
  and exists (
    select 1
    from public.approved_users au
    where au.user_id = auth.uid()
      and au.approved = true
  )
);

drop policy if exists "approved users manage own colours" on public.colours;
create policy "approved users manage own colours"
on public.colours
for all
to authenticated
using (
  auth.uid() = user_id
  and exists (
    select 1
    from public.approved_users au
    where au.user_id = auth.uid()
      and au.approved = true
  )
)
with check (
  auth.uid() = user_id
  and exists (
    select 1
    from public.approved_users au
    where au.user_id = auth.uid()
      and au.approved = true
  )
);

-- Shared roster tables used by the current app.
-- Re-run this file after deploying app updates to create these tables
-- and migrate the newest data out of the older per-user tables.

create table if not exists public.shared_rosters (
  date date primary key,
  am_milk text not null default '',
  am_yard text not null default '',
  am_assist text not null default '',
  am_tmr_feed text not null default '',
  pm_milk text not null default '',
  pm_yard text not null default '',
  pm_assist text not null default '',
  night_check text not null default '',
  night_milk text not null default '',
  night_yard text not null default '',
  training_other text not null default '',
  holiday text not null default '',
  y_feed text not null default '',
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);

create table if not exists public.shared_custom_staff (
  id integer primary key default 1 check (id = 1),
  names text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);

create table if not exists public.shared_colours (
  name text primary key,
  colour text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);

alter table public.shared_rosters
  add column if not exists updated_by uuid references auth.users(id) on delete set null;

alter table public.shared_custom_staff
  add column if not exists updated_by uuid references auth.users(id) on delete set null;

alter table public.shared_colours
  add column if not exists updated_by uuid references auth.users(id) on delete set null;

drop trigger if exists shared_rosters_set_updated_at on public.shared_rosters;
create trigger shared_rosters_set_updated_at
before update on public.shared_rosters
for each row
execute function public.set_updated_at();

drop trigger if exists shared_custom_staff_set_updated_at on public.shared_custom_staff;
create trigger shared_custom_staff_set_updated_at
before update on public.shared_custom_staff
for each row
execute function public.set_updated_at();

drop trigger if exists shared_colours_set_updated_at on public.shared_colours;
create trigger shared_colours_set_updated_at
before update on public.shared_colours
for each row
execute function public.set_updated_at();

insert into public.shared_rosters (
  date, am_milk, am_yard, am_assist, am_tmr_feed,
  pm_milk, pm_yard, pm_assist, night_check, night_milk, night_yard,
  training_other, holiday, y_feed, notes, created_at, updated_at, updated_by
)
select distinct on (date)
  date, am_milk, am_yard, am_assist, am_tmr_feed,
  pm_milk, pm_yard, pm_assist, night_check, night_milk, night_yard,
  training_other, holiday, y_feed, notes,
  coalesce(created_at, now()),
  coalesce(updated_at, now()),
  user_id
from public.rosters
where not exists (
  select 1
  from public.shared_rosters
)
order by date, updated_at desc nulls last, created_at desc nulls last, user_id;

insert into public.shared_custom_staff (
  id, names, created_at, updated_at, updated_by
)
select
  1,
  names,
  coalesce(created_at, now()),
  coalesce(updated_at, now()),
  user_id
from public.custom_staff
where not exists (
  select 1
  from public.shared_custom_staff
)
order by updated_at desc nulls last, created_at desc nulls last, user_id
limit 1;

insert into public.shared_colours (
  name, colour, created_at, updated_at, updated_by
)
select distinct on (name)
  name,
  colour,
  coalesce(created_at, now()),
  coalesce(updated_at, now()),
  user_id
from public.colours
where not exists (
  select 1
  from public.shared_colours
)
order by name, updated_at desc nulls last, created_at desc nulls last, user_id;

alter table public.shared_rosters enable row level security;
alter table public.shared_custom_staff enable row level security;
alter table public.shared_colours enable row level security;

drop policy if exists "approved users can view shared rosters" on public.shared_rosters;
create policy "approved users can view shared rosters"
on public.shared_rosters
for select
to authenticated
using (public.is_approved(auth.uid()));

drop policy if exists "admins manage shared rosters" on public.shared_rosters;
create policy "admins manage shared rosters"
on public.shared_rosters
for all
to authenticated
using (public.is_admin(auth.uid()))
with check (public.is_admin(auth.uid()));

drop policy if exists "approved users can view shared custom staff" on public.shared_custom_staff;
create policy "approved users can view shared custom staff"
on public.shared_custom_staff
for select
to authenticated
using (public.is_approved(auth.uid()));

drop policy if exists "admins manage shared custom staff" on public.shared_custom_staff;
create policy "admins manage shared custom staff"
on public.shared_custom_staff
for all
to authenticated
using (public.is_admin(auth.uid()))
with check (public.is_admin(auth.uid()));

drop policy if exists "approved users can view shared colours" on public.shared_colours;
create policy "approved users can view shared colours"
on public.shared_colours
for select
to authenticated
using (public.is_approved(auth.uid()));

drop policy if exists "admins manage shared colours" on public.shared_colours;
create policy "admins manage shared colours"
on public.shared_colours
for all
to authenticated
using (public.is_admin(auth.uid()))
with check (public.is_admin(auth.uid()));

-- Make the first admin:
-- update public.approved_users
-- set approved = true,
--     is_admin = true,
--     approved_at = now()
-- where email = 'person@example.com';
