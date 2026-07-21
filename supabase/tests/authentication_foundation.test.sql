begin;

select plan(29);

select has_table('public', 'people', 'people table exists');
select has_table('public', 'accounts', 'accounts table exists');
select has_table('public', 'invitations', 'invitations table exists');
select has_table('public', 'claims', 'claims table exists');
select has_table('public', 'app_policies', 'app policies table exists');
select has_table('public', 'audit_events', 'audit events table exists');

select has_function('public', 'current_account', 'current account helper exists');
select has_function('public', 'is_reviewer', 'reviewer helper exists');

select ok((select relrowsecurity from pg_class where oid = 'public.people'::regclass), 'people RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.accounts'::regclass), 'accounts RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.invitations'::regclass), 'invitations RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.claims'::regclass), 'claims RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.app_policies'::regclass), 'app policies RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.audit_events'::regclass), 'audit events RLS enabled');

select policies_are('public', 'people', array['approved members read own person only']);
select policies_are('public', 'accounts', array['users read own account']);
select policies_are('public', 'invitations', array['users read own invitation']);
select policies_are('public', 'claims', array['users read own claims']);

select is(
  (select cousin_depth_limit from public.app_policies where singleton),
  3::smallint,
  'relationship policy defaults to third cousins'
);

insert into auth.users (id, email)
values
  ('11111111-1111-1111-1111-111111111111', 'admin@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'pending@example.com'),
  ('33333333-3333-3333-3333-333333333333', 'member@example.com');

insert into public.people (id, display_name, is_verified)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Approved Member', true),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Unclaimed Person', true);

update public.accounts
set person_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    status = 'approved',
    role = 'admin'
where user_id = '11111111-1111-1111-1111-111111111111';

update public.accounts
set person_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    status = 'approved'
where user_id = '33333333-3333-3333-3333-333333333333';

insert into public.invitations (
  id, invited_email, target_person_id, invited_by, token_hash, expires_at
)
values (
  'cccccccc-cccc-cccc-cccc-cccccccccccc',
  'pending@example.com',
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  '11111111-1111-1111-1111-111111111111',
  'test-token-hash',
  now() + interval '72 hours'
);

insert into public.claims (
  id, invitation_id, claimant_user_id, target_person_id
)
values (
  'dddddddd-dddd-dddd-dddd-dddddddddddd',
  'cccccccc-cccc-cccc-cccc-cccccccccccc',
  '22222222-2222-2222-2222-222222222222',
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
);

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","email":"pending@example.com","role":"authenticated"}';
set local role authenticated;

select results_eq(
  $$ select count(*)::bigint from public.people $$,
  $$ values (0::bigint) $$,
  'pending user cannot read people'
);

select results_eq(
  $$ select count(*)::bigint from public.accounts $$,
  $$ values (1::bigint) $$,
  'pending user reads only their account'
);

select results_eq(
  $$ select count(*)::bigint from public.invitations $$,
  $$ values (1::bigint) $$,
  'pending user reads their invitation by JWT email'
);

select results_eq(
  $$ select count(*)::bigint from public.claims $$,
  $$ values (1::bigint) $$,
  'pending user reads their claim'
);

select throws_ok(
  $$ insert into public.audit_events(action, target_type, outcome)
     values ('forged', 'account', 'succeeded') $$,
  '42501',
  null,
  'authenticated client cannot forge audit events'
);

reset role;
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
set local request.jwt.claims = '{"sub":"33333333-3333-3333-3333-333333333333","email":"member@example.com","role":"authenticated"}';
set local role authenticated;

select results_eq(
  $$ select count(*)::bigint from public.people $$,
  $$ values (1::bigint) $$,
  'approved user reads their own person'
);

select results_eq(
  $$ select count(*)::bigint from public.people
     where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' $$,
  $$ values (0::bigint) $$,
  'approved user cannot read another person'
);

select results_eq(
  $$ select count(*)::bigint from public.accounts $$,
  $$ values (1::bigint) $$,
  'approved user reads only their account'
);

select results_eq(
  $$ select count(*)::bigint from public.invitations $$,
  $$ values (0::bigint) $$,
  'approved user cannot read another email invitation'
);

select results_eq(
  $$ select count(*)::bigint from public.claims $$,
  $$ values (0::bigint) $$,
  'approved user cannot read another claim'
);

reset role;

select * from finish();
rollback;
