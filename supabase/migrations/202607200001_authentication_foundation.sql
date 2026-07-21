create extension if not exists citext with schema extensions;

create type public.account_role as enum ('member', 'trusted_elder', 'admin');
create type public.account_status as enum ('pending', 'approved', 'suspended', 'closed');
create type public.review_status as enum ('pending', 'approved', 'rejected', 'withdrawn');
create type public.invitation_status as enum ('pending', 'accepted', 'expired', 'revoked');

create table public.people (
  id uuid primary key default gen_random_uuid(),
  display_name text not null check (length(btrim(display_name)) between 1 and 160),
  birth_date date,
  city text,
  administrative_region text,
  country_code text check (country_code is null or country_code ~ '^[A-Z]{2}$'),
  phone_e164 text check (phone_e164 is null or phone_e164 ~ '^\+[1-9][0-9]{7,14}$'),
  contact_email extensions.citext,
  biography text check (biography is null or length(biography) <= 1000),
  photo_path text,
  is_verified boolean not null default false,
  row_version bigint not null default 1 check (row_version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.accounts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  person_id uuid unique references public.people(id) on delete restrict,
  role public.account_role not null default 'member',
  status public.account_status not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((status = 'approved') = (person_id is not null))
);

create or replace function public.create_pending_account()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.accounts(user_id, status, role)
  values (new.id, 'pending', 'member')
  on conflict (user_id) do nothing;
  return new;
end;
$$;

create trigger create_pending_account_after_auth_user
after insert on auth.users
for each row execute function public.create_pending_account();

create table public.invitations (
  id uuid primary key default gen_random_uuid(),
  invited_email extensions.citext not null,
  target_person_id uuid not null references public.people(id) on delete restrict,
  invited_by uuid not null references public.accounts(user_id) on delete restrict,
  token_hash text not null unique,
  status public.invitation_status not null default 'pending',
  expires_at timestamptz not null,
  accepted_by uuid references public.accounts(user_id) on delete restrict,
  created_at timestamptz not null default now(),
  check (expires_at > created_at)
);

create unique index one_pending_invitation_per_person
on public.invitations(target_person_id)
where status = 'pending';

create table public.claims (
  id uuid primary key default gen_random_uuid(),
  invitation_id uuid not null unique references public.invitations(id) on delete restrict,
  claimant_user_id uuid not null references public.accounts(user_id) on delete restrict,
  target_person_id uuid not null references public.people(id) on delete restrict,
  private_note text check (private_note is null or length(private_note) <= 2000),
  status public.review_status not null default 'pending',
  reviewed_by uuid references public.accounts(user_id) on delete restrict,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  check (reviewed_by is null or reviewed_by <> claimant_user_id),
  check ((status in ('approved', 'rejected')) = (reviewed_by is not null and reviewed_at is not null))
);

create table public.app_policies (
  singleton boolean primary key default true check (singleton),
  cousin_depth_limit smallint check (cousin_depth_limit between 1 and 20),
  unlimited_depth boolean not null default false,
  contact_visibility text not null default 'permitted_relatives'
    check (contact_visibility in ('permitted_relatives', 'per_field_consent', 'approved_connection')),
  invitation_lifetime_hours integer not null default 72
    check (invitation_lifetime_hours between 1 and 720),
  updated_at timestamptz not null default now(),
  check (unlimited_depth or cousin_depth_limit is not null)
);

insert into public.app_policies(singleton, cousin_depth_limit)
values (true, 3);

create table public.audit_events (
  id bigint generated always as identity primary key,
  actor_user_id uuid references public.accounts(user_id) on delete restrict,
  action text not null,
  target_type text not null,
  target_id uuid,
  outcome text not null check (outcome in ('succeeded', 'denied', 'failed')),
  correlation_id uuid not null default gen_random_uuid(),
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);
