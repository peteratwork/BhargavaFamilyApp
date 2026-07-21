begin;

select plan(19);

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

select * from finish();
rollback;
