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
  check (
    (status = 'pending' and person_id is null)
    or (status in ('approved', 'suspended') and person_id is not null)
    or status = 'closed'
  )
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

create unique index one_pending_invitation_per_email
on public.invitations(invited_email)
where status = 'pending';

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

  update public.invitations as i
  set accepted_by = new.id
  where new.email is not null
    and i.invited_email = new.email
    and i.status = 'pending'
    and i.expires_at > now()
    and i.accepted_by is null;

  return new;
end;
$$;

create or replace function public.close_account_after_invitation_ends()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status = 'pending'
     and new.status in ('expired', 'revoked')
     and new.accepted_by is not null then
    update public.accounts as a
    set status = 'closed', updated_at = now()
    where a.user_id = new.accepted_by
      and a.status = 'pending';
  end if;
  return new;
end;
$$;

create trigger close_account_after_invitation_ends
after update of status on public.invitations
for each row execute function public.close_account_after_invitation_ends();

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
  invitation_lifetime_hours integer not null default 1
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

create or replace function public.prevent_audit_event_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'audit_events_are_immutable' using errcode = 'P0001';
end;
$$;

create trigger prevent_audit_event_mutation
before update or delete on public.audit_events
for each row execute function public.prevent_audit_event_mutation();

create or replace function public.current_account()
returns public.accounts
language sql
stable
security definer
set search_path = ''
as $$
  select a
  from public.accounts a
  where a.user_id = auth.uid();
$$;

create or replace function public.is_reviewer()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select a.status = 'approved' and a.role in ('trusted_elder', 'admin')
      from public.accounts a
      where a.user_id = auth.uid()
    ),
    false
  );
$$;

create or replace function public.refresh_own_account_state()
returns table(status text, role text, person_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    return;
  end if;

  update public.invitations as i
  set status = 'expired'
  where i.accepted_by = auth.uid()
    and i.status = 'pending'
    and i.expires_at <= now();

  update public.accounts as a
  set status = 'closed', updated_at = now()
  where a.user_id = auth.uid()
    and a.status = 'pending'
    and not exists (
      select 1
      from public.invitations i
      where i.accepted_by = a.user_id
        and i.status = 'pending'
        and i.expires_at > now()
    )
    and not exists (
      select 1
      from public.claims c
      where c.claimant_user_id = a.user_id
        and c.status = 'pending'
    );

  return query
  select a.status::text, a.role::text, a.person_id
  from public.accounts a
  where a.user_id = auth.uid();
end;
$$;

alter table public.people enable row level security;
alter table public.accounts enable row level security;
alter table public.invitations enable row level security;
alter table public.claims enable row level security;
alter table public.app_policies enable row level security;
alter table public.audit_events enable row level security;

grant select on public.people to authenticated;
grant select on public.accounts to authenticated;
grant select on public.invitations to authenticated;
grant select on public.claims to authenticated;
grant select on public.app_policies to authenticated;

revoke all on public.audit_events from anon, authenticated;
revoke insert, update, delete on public.audit_events from service_role;
revoke insert, update, delete on public.people from anon, authenticated;
revoke insert, update, delete on public.accounts from anon, authenticated;
revoke insert, update, delete on public.invitations from anon, authenticated;
revoke insert, update, delete on public.claims from anon, authenticated;
revoke insert, update, delete on public.app_policies from anon, authenticated;

revoke all on function public.current_account() from public;
revoke all on function public.is_reviewer() from public;
revoke all on function public.prevent_audit_event_mutation() from public;
revoke all on function public.close_account_after_invitation_ends() from public;
revoke all on function public.refresh_own_account_state() from public, anon;
grant execute on function public.current_account() to authenticated;
grant execute on function public.is_reviewer() to authenticated;
grant execute on function public.refresh_own_account_state() to authenticated;

create policy "approved members read own person only"
on public.people
for select
to authenticated
using (
  exists (
    select 1
    from public.accounts a
    where a.user_id = auth.uid()
      and a.status = 'approved'
      and a.person_id = people.id
  )
);

create policy "users read own account"
on public.accounts
for select
to authenticated
using (user_id = auth.uid());

create policy "users read own invitation"
on public.invitations
for select
to authenticated
using (lower(invited_email::text) = lower(coalesce(auth.jwt() ->> 'email', '')));

create policy "users read own claims"
on public.claims
for select
to authenticated
using (claimant_user_id = auth.uid());

create or replace function public.create_invitation_record(
  p_target_person_id uuid,
  p_normalized_email text,
  p_actor_user_id uuid,
  p_token_hash text
)
returns table(
  invitation_id uuid,
  expires_at timestamptz,
  uses_existing_auth_user boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_invitation_id uuid;
  v_expires_at timestamptz;
  v_lifetime_hours integer;
  v_normalized_email extensions.citext;
  v_existing_user_id uuid;
begin
  v_normalized_email := lower(btrim(p_normalized_email));

  update public.invitations as i
  set status = 'expired'
  where (
      i.target_person_id = p_target_person_id
      or i.invited_email = v_normalized_email
    )
    and i.status = 'pending'
    and i.expires_at <= now();

  if not exists (
    select 1
    from public.accounts a
    where a.user_id = p_actor_user_id
      and a.status = 'approved'
      and a.role in ('trusted_elder', 'admin')
  ) then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;

  if not exists (
    select 1
    from public.people p
    where p.id = p_target_person_id
      and p.is_verified
  ) or exists (
    select 1 from public.accounts a where a.person_id = p_target_person_id
  ) or exists (
    select 1
    from public.invitations i
    where i.target_person_id = p_target_person_id
      and i.status = 'pending'
  ) or exists (
    select 1
    from public.invitations i
    where i.invited_email = v_normalized_email
      and i.status = 'pending'
  ) then
    raise exception 'target_unavailable' using errcode = 'P0001';
  end if;

  select a.user_id
  into v_existing_user_id
  from auth.users u
  join public.accounts a on a.user_id = u.id
  where lower(u.email) = v_normalized_email::text
    and a.status = 'closed'
    and a.person_id is null
  limit 1;

  if v_existing_user_id is null and exists (
    select 1 from auth.users u where lower(u.email) = v_normalized_email::text
  ) then
    raise exception 'email_unavailable' using errcode = 'P0001';
  end if;

  select p.invitation_lifetime_hours
  into strict v_lifetime_hours
  from public.app_policies p
  where p.singleton;

  v_invitation_id := gen_random_uuid();
  v_expires_at := now() + make_interval(hours => v_lifetime_hours);

  if v_existing_user_id is not null then
    update public.accounts as a
    set status = 'pending', updated_at = now()
    where a.user_id = v_existing_user_id;
  end if;

  insert into public.invitations (
    id,
    invited_email,
    target_person_id,
    invited_by,
    token_hash,
    expires_at,
    accepted_by
  ) values (
    v_invitation_id,
    lower(btrim(p_normalized_email)),
    p_target_person_id,
    p_actor_user_id,
    p_token_hash,
    v_expires_at,
    v_existing_user_id
  );

  insert into public.audit_events (
    actor_user_id,
    action,
    target_type,
    target_id,
    outcome,
    metadata
  ) values (
    p_actor_user_id,
    'invitation.created',
    'person',
    p_target_person_id,
    'succeeded',
    jsonb_build_object('reactivated_existing_user', v_existing_user_id is not null)
  );

  return query
  select v_invitation_id, v_expires_at, v_existing_user_id is not null;
end;
$$;

create or replace function public.revoke_invitation_after_delivery_failure(
  p_invitation_id uuid,
  p_actor_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_target_person_id uuid;
begin
  if not exists (
    select 1
    from public.accounts a
    where a.user_id = p_actor_user_id
      and a.status = 'approved'
      and a.role in ('trusted_elder', 'admin')
  ) then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;

  update public.invitations
  set status = 'revoked'
  where id = p_invitation_id
    and invited_by = p_actor_user_id
    and status = 'pending'
  returning target_person_id into v_target_person_id;

  if v_target_person_id is null then
    raise exception 'invitation_unavailable' using errcode = 'P0001';
  end if;

  insert into public.audit_events (
    actor_user_id,
    action,
    target_type,
    target_id,
    outcome,
    metadata
  ) values (
    p_actor_user_id,
    'invitation.delivery_failed',
    'invitation',
    p_invitation_id,
    'failed',
    jsonb_build_object('target_person_id', v_target_person_id)
  );
end;
$$;

revoke all on function public.create_invitation_record(uuid, text, uuid, text)
from public, anon, authenticated;
revoke all on function public.revoke_invitation_after_delivery_failure(uuid, uuid)
from public, anon, authenticated;

grant execute on function public.create_invitation_record(uuid, text, uuid, text)
to service_role;
grant execute on function public.revoke_invitation_after_delivery_failure(uuid, uuid)
to service_role;
