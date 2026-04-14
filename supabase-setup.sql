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
      and is_admin = true
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

-- Make the first admin:
-- update public.approved_users
-- set approved = true,
--     is_admin = true,
--     approved_at = now()
-- where email = 'person@example.com';
