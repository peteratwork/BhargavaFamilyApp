begin;

select plan(6);

select has_table('public', 'people', 'people table exists');
select has_table('public', 'accounts', 'accounts table exists');
select has_table('public', 'invitations', 'invitations table exists');
select has_table('public', 'claims', 'claims table exists');
select has_table('public', 'app_policies', 'app policies table exists');
select has_table('public', 'audit_events', 'audit events table exists');

select * from finish();
rollback;
