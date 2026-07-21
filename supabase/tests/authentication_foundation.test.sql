begin;

select plan(97);

select has_table('public', 'people', 'people table exists');
select has_table('public', 'accounts', 'accounts table exists');
select has_table('public', 'invitations', 'invitations table exists');
select has_table('public', 'claims', 'claims table exists');
select has_table('public', 'app_policies', 'app policies table exists');
select has_table('public', 'audit_events', 'audit events table exists');

select has_function('public', 'current_account', 'current account helper exists');
select has_function('public', 'is_reviewer', 'reviewer helper exists');
select has_function('public', 'refresh_own_account_state', 'account lifecycle refresh exists');

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

select is(
  (select invitation_lifetime_hours from public.app_policies where singleton),
  1,
  'application invitation lifetime matches the one-hour Auth email lifetime'
);

insert into auth.users (id, email)
values
  ('11111111-1111-1111-1111-111111111111', 'admin@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'pending@example.com'),
  ('33333333-3333-3333-3333-333333333333', 'member@example.com'),
  ('44444444-4444-4444-4444-444444444444', 'elder@example.com');

insert into public.people (id, display_name, is_verified)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Approved Member', true),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Unclaimed Person', true),
  ('12121212-1212-1212-1212-121212121212', 'Trusted Elder', true);

update public.accounts
set person_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    status = 'approved',
    role = 'admin'
where user_id = '11111111-1111-1111-1111-111111111111';

update public.accounts
set person_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    status = 'approved'
where user_id = '33333333-3333-3333-3333-333333333333';

update public.accounts
set person_id = '12121212-1212-1212-1212-121212121212',
    status = 'approved',
    role = 'trusted_elder'
where user_id = '44444444-4444-4444-4444-444444444444';

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

set local role anon;

select throws_ok($$ select count(*) from public.people $$, '42501', null,
  'anonymous clients cannot read people');
select throws_ok($$ select count(*) from public.accounts $$, '42501', null,
  'anonymous clients cannot read accounts');
select throws_ok($$ select count(*) from public.invitations $$, '42501', null,
  'anonymous clients cannot read invitations');
select throws_ok($$ select count(*) from public.claims $$, '42501', null,
  'anonymous clients cannot read claims');
select throws_ok($$ select count(*) from public.app_policies $$, '42501', null,
  'anonymous clients cannot read app policies');
select throws_ok($$ select count(*) from public.audit_events $$, '42501', null,
  'anonymous clients cannot read audit events');

reset role;

select ok(
  not has_table_privilege('authenticated', 'public.people', 'INSERT')
  and not has_table_privilege('authenticated', 'public.people', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.people', 'DELETE'),
  'authenticated clients cannot mutate people directly'
);
select ok(
  not has_table_privilege('authenticated', 'public.accounts', 'INSERT')
  and not has_table_privilege('authenticated', 'public.accounts', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.accounts', 'DELETE'),
  'authenticated clients cannot mutate accounts directly'
);
select ok(
  not has_table_privilege('authenticated', 'public.invitations', 'INSERT')
  and not has_table_privilege('authenticated', 'public.invitations', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.invitations', 'DELETE'),
  'authenticated clients cannot mutate invitations directly'
);
select ok(
  not has_table_privilege('authenticated', 'public.claims', 'INSERT')
  and not has_table_privilege('authenticated', 'public.claims', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.claims', 'DELETE'),
  'authenticated clients cannot mutate claims directly'
);
select ok(
  not has_table_privilege('authenticated', 'public.app_policies', 'INSERT')
  and not has_table_privilege('authenticated', 'public.app_policies', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.app_policies', 'DELETE'),
  'authenticated clients cannot mutate app policies directly'
);
select ok(
  not has_table_privilege('authenticated', 'public.audit_events', 'INSERT')
  and not has_table_privilege('authenticated', 'public.audit_events', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.audit_events', 'DELETE'),
  'authenticated clients cannot mutate audit events directly'
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

select results_eq(
  $$ select count(*)::bigint from public.app_policies $$,
  $$ values (0::bigint) $$,
  'pending user cannot read app policies'
);

select throws_ok(
  $$ insert into public.audit_events(action, target_type, outcome)
     values ('forged', 'account', 'succeeded') $$,
  '42501',
  null,
  'authenticated client cannot forge audit events'
);

reset role;

set local request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
set local request.jwt.claims = '{"sub":"44444444-4444-4444-4444-444444444444","email":"elder@example.com","role":"authenticated"}';
set local role authenticated;

select is(public.is_reviewer(), true, 'trusted elder is recognized as a reviewer');
select results_eq($$ select count(*)::bigint from public.people $$,
  $$ values (1::bigint) $$, 'trusted elder reads only their person');
select results_eq($$ select count(*)::bigint from public.people where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' $$,
  $$ values (0::bigint) $$, 'trusted elder cannot read another person');
select results_eq($$ select count(*)::bigint from public.accounts $$,
  $$ values (1::bigint) $$, 'trusted elder reads only their account');
select results_eq($$ select count(*)::bigint from public.invitations $$,
  $$ values (0::bigint) $$, 'trusted elder cannot read another invitation');
select results_eq($$ select count(*)::bigint from public.claims $$,
  $$ values (0::bigint) $$, 'trusted elder cannot read another claim');
select results_eq($$ select count(*)::bigint from public.app_policies $$,
  $$ values (0::bigint) $$, 'trusted elder cannot read server policy configuration');
select throws_ok($$ select count(*) from public.audit_events $$, '42501', null,
  'trusted elder cannot read audit history directly');

reset role;

set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","email":"admin@example.com","role":"authenticated"}';
set local role authenticated;

select is(public.is_reviewer(), true, 'admin is recognized as a reviewer');
select results_eq($$ select count(*)::bigint from public.people $$,
  $$ values (1::bigint) $$, 'admin reads only their person through the client');
select results_eq($$ select count(*)::bigint from public.people where id = '12121212-1212-1212-1212-121212121212' $$,
  $$ values (0::bigint) $$, 'admin cannot bypass relationship visibility');
select results_eq($$ select count(*)::bigint from public.accounts $$,
  $$ values (1::bigint) $$, 'admin reads only their account through the client');
select results_eq($$ select count(*)::bigint from public.invitations $$,
  $$ values (0::bigint) $$, 'admin cannot read another invitation through the client');
select results_eq($$ select count(*)::bigint from public.claims $$,
  $$ values (0::bigint) $$, 'admin cannot read another claim through the client');
select results_eq($$ select count(*)::bigint from public.app_policies $$,
  $$ values (0::bigint) $$, 'admin cannot read server policy configuration directly');
select throws_ok($$ select count(*) from public.audit_events $$, '42501', null,
  'admin cannot read audit history directly');

reset role;

select has_function('public', 'create_invitation_record', 'transactional invitation function exists');
select has_function('public', 'revoke_invitation_after_delivery_failure', 'delivery failure compensation exists');

select ok(
  not has_function_privilege(
    'authenticated',
    'public.create_invitation_record(uuid,text,uuid,text)',
    'execute'
  ),
  'authenticated clients cannot execute invitation transaction directly'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.refresh_own_account_state()',
    'execute'
  ),
  'authenticated clients can refresh only their own account lifecycle'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.refresh_own_account_state()',
    'execute'
  ),
  'anonymous clients cannot execute account lifecycle refresh'
);

insert into public.people (id, display_name, is_verified)
values ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'Available Person', true);

select lives_ok(
  $$ select * from public.create_invitation_record(
       'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
       'newmember@example.com',
       '11111111-1111-1111-1111-111111111111',
       'new-test-token-hash'
     ) $$,
  'authorized invitation transaction succeeds'
);

select results_eq(
  $$ select count(*)::bigint from public.invitations
     where target_person_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'
       and status = 'pending' $$,
  $$ values (1::bigint) $$,
  'invitation transaction creates one pending invitation'
);

select results_eq(
  $$ select count(*)::bigint from public.audit_events
     where action = 'invitation.created'
       and target_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee' $$,
  $$ values (1::bigint) $$,
  'invitation transaction appends an audit event'
);

select throws_ok(
  $$ update public.audit_events set outcome = 'failed'
     where action = 'invitation.created' $$,
  'P0001',
  'audit_events_are_immutable',
  'audit events cannot be updated even by a privileged connection'
);

select throws_ok(
  $$ delete from public.audit_events where action = 'invitation.created' $$,
  'P0001',
  'audit_events_are_immutable',
  'audit events cannot be deleted even by a privileged connection'
);

insert into auth.users (id, email)
values ('55555555-5555-5555-5555-555555555555', 'newmember@example.com');

select results_eq(
  $$ select accepted_by from public.invitations
     where target_person_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee' $$,
  $$ values ('55555555-5555-5555-5555-555555555555'::uuid) $$,
  'Auth user creation links the active application invitation'
);

select results_eq(
  $$ select status from public.accounts
     where user_id = '55555555-5555-5555-5555-555555555555' $$,
  $$ values ('pending'::public.account_status) $$,
  'newly linked invitee starts pending'
);

select lives_ok(
  $$ select public.revoke_invitation_after_delivery_failure(
       (select id from public.invitations
        where target_person_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'),
       '11111111-1111-1111-1111-111111111111'
     ) $$,
  'delivery failure compensation succeeds'
);

select results_eq(
  $$ select count(*)::bigint from public.invitations
     where target_person_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'
       and status = 'revoked' $$,
  $$ values (1::bigint) $$,
  'delivery failure compensation revokes the pending invitation'
);

select results_eq(
  $$ select status from public.accounts
     where user_id = '55555555-5555-5555-5555-555555555555' $$,
  $$ values ('closed'::public.account_status) $$,
  'revoking an invitation closes its pending application account'
);

select lives_ok(
  $$ select * from public.create_invitation_record(
       'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
       'newmember@example.com',
       '11111111-1111-1111-1111-111111111111',
       'reactivated-test-token-hash'
     ) $$,
  'a closed unclaimed Auth identity can be invited again'
);

select results_eq(
  $$ select count(*)::bigint from public.invitations
     where target_person_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'
       and status = 'pending'
       and accepted_by = '55555555-5555-5555-5555-555555555555' $$,
  $$ values (1::bigint) $$,
  'replacement invitation reuses and links the closed Auth identity'
);

select results_eq(
  $$ select status from public.accounts
     where user_id = '55555555-5555-5555-5555-555555555555' $$,
  $$ values ('pending'::public.account_status) $$,
  'replacement invitation reactivates the closed application account'
);
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

insert into public.people (id, display_name, is_verified)
values ('ffffffff-ffff-ffff-ffff-ffffffffffff', 'Expired Invite Target', true);

insert into public.invitations (
  id, invited_email, target_person_id, invited_by, token_hash, status,
  created_at, expires_at
)
values (
  'ffffffff-ffff-ffff-ffff-000000000001',
  'expired@example.com',
  'ffffffff-ffff-ffff-ffff-ffffffffffff',
  '11111111-1111-1111-1111-111111111111',
  'expired-test-token-hash',
  'pending',
  now() - interval '2 hours',
  now() - interval '1 hour'
);

select lives_ok(
  $$ select * from public.create_invitation_record(
       'ffffffff-ffff-ffff-ffff-ffffffffffff',
       'replacement@example.com',
       '11111111-1111-1111-1111-111111111111',
       'replacement-test-token-hash'
     ) $$,
  'expired invitation does not permanently block a replacement'
);

select results_eq(
  $$ select count(*)::bigint from public.invitations
     where id = 'ffffffff-ffff-ffff-ffff-000000000001'
       and status = 'expired' $$,
  $$ values (1::bigint) $$,
  'replacement transaction marks the old invitation expired'
);

select results_eq(
  $$ select count(*)::bigint from public.invitations
     where target_person_id = 'ffffffff-ffff-ffff-ffff-ffffffffffff'
       and status = 'pending' $$,
  $$ values (1::bigint) $$,
  'replacement transaction creates one active pending invitation'
);

insert into public.people (id, display_name, is_verified)
values ('67676767-6767-6767-6767-676767676767', 'Expiring Linked Target', true);

select lives_ok(
  $$ select * from public.create_invitation_record(
       '67676767-6767-6767-6767-676767676767',
       'expiring-linked@example.com',
       '11111111-1111-1111-1111-111111111111',
       'expiring-linked-token-hash'
     ) $$,
  'an active invitation can be linked for expiry enforcement'
);

insert into auth.users (id, email)
values ('66666666-6666-6666-6666-666666666666', 'expiring-linked@example.com');

select results_eq(
  $$ select accepted_by from public.invitations
     where target_person_id = '67676767-6767-6767-6767-676767676767' $$,
  $$ values ('66666666-6666-6666-6666-666666666666'::uuid) $$,
  'active invitation is linked to its Auth identity'
);

update public.invitations
set created_at = now() - interval '2 hours',
    expires_at = now() - interval '1 hour'
where target_person_id = '67676767-6767-6767-6767-676767676767';

set local request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';
set local request.jwt.claims = '{"sub":"66666666-6666-6666-6666-666666666666","email":"expiring-linked@example.com","role":"authenticated"}';
set local role authenticated;

select results_eq(
  $$ select status from public.refresh_own_account_state() $$,
  $$ values ('closed'::text) $$,
  'an expired invitation cannot replay into pending application access'
);

reset role;

select results_eq(
  $$ select status from public.invitations
     where target_person_id = '67676767-6767-6767-6767-676767676767' $$,
  $$ values ('expired'::public.invitation_status) $$,
  'account refresh records time-based invitation expiry'
);

select results_eq(
  $$ select status from public.accounts
     where user_id = '66666666-6666-6666-6666-666666666666' $$,
  $$ values ('closed'::public.account_status) $$,
  'time-based invitation expiry closes the linked account'
);

insert into public.people (id, display_name, is_verified)
values
  ('78787878-7878-7878-7878-787878787878', 'Old Email Target', true),
  ('89898989-8989-8989-8989-898989898989', 'Replacement Email Target', true);

insert into public.invitations (
  id, invited_email, target_person_id, invited_by, token_hash, status,
  created_at, expires_at
)
values (
  '78787878-7878-7878-7878-000000000001',
  'reusable-email@example.com',
  '78787878-7878-7878-7878-787878787878',
  '11111111-1111-1111-1111-111111111111',
  'reusable-email-old-token-hash',
  'pending',
  now() - interval '2 hours',
  now() - interval '1 hour'
);

select lives_ok(
  $$ select * from public.create_invitation_record(
       '89898989-8989-8989-8989-898989898989',
       'reusable-email@example.com',
       '11111111-1111-1111-1111-111111111111',
       'reusable-email-new-token-hash'
     ) $$,
  'expired pending email on another target does not block replacement'
);

select results_eq(
  $$ select status from public.invitations
     where id = '78787878-7878-7878-7878-000000000001' $$,
  $$ values ('expired'::public.invitation_status) $$,
  'replacement expires the old pending invitation by normalized email'
);

select results_eq(
  $$ select count(*)::bigint from public.invitations
     where target_person_id = '89898989-8989-8989-8989-898989898989'
       and invited_email = 'reusable-email@example.com'
       and status = 'pending' $$,
  $$ values (1::bigint) $$,
  'replacement creates the new pending invitation after email cleanup'
);

select lives_ok(
  $$ update public.accounts
     set status = 'suspended'
     where user_id = '33333333-3333-3333-3333-333333333333' $$,
  'suspending an approved account preserves its person claim'
);

select results_eq(
  $$ select person_id from public.accounts
     where user_id = '33333333-3333-3333-3333-333333333333' $$,
  $$ values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid) $$,
  'suspended account remains linked to its claimed person'
);

select throws_ok(
  $$ select * from public.create_invitation_record(
       'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
       'takeover@example.com',
       '11111111-1111-1111-1111-111111111111',
       'takeover-test-token-hash'
     ) $$,
  'P0001',
  'target_unavailable',
  'suspended account person cannot be invited or claimed again'
);

select lives_ok(
  $$ update public.accounts
     set status = 'closed'
     where user_id = '22222222-2222-2222-2222-222222222222' $$,
  'an unclaimed pending account can be closed without assigning a person'
);

select results_eq(
  $$ select person_id from public.accounts
     where user_id = '22222222-2222-2222-2222-222222222222' $$,
  $$ values (null::uuid) $$,
  'closed unclaimed account remains unlinked'
);

select ok(
  not has_table_privilege('service_role', 'public.audit_events', 'INSERT'),
  'service role cannot insert audit rows outside protected functions'
);

select ok(
  not has_table_privilege('service_role', 'public.audit_events', 'UPDATE'),
  'service role cannot rewrite audit rows'
);

select ok(
  not has_table_privilege('service_role', 'public.audit_events', 'DELETE'),
  'service role cannot delete audit rows'
);

select * from finish();
rollback;
