# Authentication Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish a repeatable Supabase backend and an invitation-gated SwiftUI email-OTP session shell that prevents unapproved users from seeing family data.

**Architecture:** PostgreSQL stores people, accounts, invitations, claims, policies, and audit events with deny-by-default row-level security. The iOS app depends on an `AuthenticationRepository` abstraction; Supabase backs production while an in-memory implementation drives previews and tests. A single `AppSession` state machine owns routing among signed-out, awaiting-email, pending-claim, approved, and failure states.

**Tech Stack:** Swift 5 / SwiftUI on iOS 17+, Swift Package Manager, supabase-swift 2.x, PostgreSQL 15+, Supabase CLI, pgTAP, Deno/TypeScript Edge Functions, Codemagic.

**Execution Environment Note:** The Windows Cloud PC does not expose nested virtualization, so Docker Desktop cannot run the local Supabase stack. Run CLI initialization and pure Deno/Swift checks locally where supported. Run every Docker-backed `supabase start`, reset, lint, and pgTAP red-green verification in `.github/workflows/backend-tests.yml` on GitHub-hosted Linux. A test is not considered verified until CI demonstrates the expected failure before implementation and a passing run afterward.

## Global Constraints

- The private beta supports no more than 100 members.
- Authentication is passwordless email OTP and account creation is invitation-only.
- An invitation targets an existing unclaimed `people` record.
- Roles are exactly `member`, `trusted_elder`, and `admin`; only admins may change roles.
- Pending users may read only their own invitation and claim state, never family data.
- Production runs in Supabase South Asia (Mumbai), `ap-south-1`.
- Birth dates are PostgreSQL `date`; timestamps are UTC `timestamptz`; phone values use E.164.
- No production secret or service-role key may enter Git, the Xcode project, the app bundle, logs, or test fixtures.
- The app must never fall back to sample family data when production configuration or authentication fails.

---

## Delivery Sequence

This plan is Phase 1 of the approved production program. Later plans, in order, will cover: verified family graph and policy-bounded discovery; profile/change review and in-app administration; persistent meetups; privacy/telemetry/release hardening. Do not pull those features into this plan.

## File Structure

- `package.json`: project-scoped Supabase CLI command and pinned tool version.
- `.github/workflows/backend-tests.yml`: Docker-backed Supabase verification for Cloud-PC development.
- `supabase/config.toml`: reproducible local Auth/Postgres configuration.
- `supabase/migrations/202607200001_authentication_foundation.sql`: identity schema, constraints, helper functions, and RLS.
- `supabase/seed.sql`: synthetic people, admin, invitation, and claim states only.
- `supabase/tests/database/authentication_foundation.test.sql`: pgTAP authorization and integrity tests.
- `supabase/functions/create-invitation/index.ts`: authenticated invitation command.
- `supabase/functions/create-invitation/handler.ts`: testable validation/orchestration logic.
- `supabase/functions/tests/create-invitation/handler.test.ts`: Deno unit tests.
- `BhargavaFamilyApp/Configuration/AppConfiguration.swift`: fail-closed runtime configuration.
- `BhargavaFamilyApp/Authentication/AuthenticationModels.swift`: session and account domain types.
- `BhargavaFamilyApp/Authentication/AuthenticationRepository.swift`: client-independent contract.
- `BhargavaFamilyApp/Authentication/SupabaseAuthenticationRepository.swift`: Supabase implementation.
- `BhargavaFamilyApp/Authentication/InMemoryAuthenticationRepository.swift`: preview/test implementation.
- `BhargavaFamilyApp/Authentication/AppSession.swift`: the sole session state machine.
- `BhargavaFamilyApp/Authentication/AuthenticationRootView.swift`: state-driven routing.
- `BhargavaFamilyApp/Authentication/SignInView.swift`: email entry and OTP request.
- `BhargavaFamilyApp/Authentication/CheckEmailView.swift`: OTP/magic-link waiting state.
- `BhargavaFamilyApp/Authentication/PendingClaimView.swift`: pending/rejected claim state.
- `BhargavaFamilyAppTests/Authentication/AppSessionTests.swift`: state-machine unit tests.
- `BhargavaFamilyAppTests/Configuration/AppConfigurationTests.swift`: fail-closed configuration tests.
- `codemagic.yaml`: backend tests, iOS tests, build-number increment, and TestFlight upload.

### Task 1: Reproducible Supabase Local Project

**Files:**
- Create: `package.json`
- Create: `.github/workflows/backend-tests.yml`
- Create: `supabase/config.toml`
- Create: `supabase/seed.sql`
- Modify: `.gitignore` if generated Supabase temp paths are not already ignored

**Interfaces:**
- Consumes: Node.js 22 locally and a Docker-capable GitHub-hosted Linux runner.
- Produces: `npx supabase <command>` and a CI stack resettable from committed files.

- [ ] **Step 1: Initialize the project-scoped CLI**

Create `package.json`:

```json
{
  "name": "bhargava-family-app-infrastructure",
  "private": true,
  "scripts": {
    "supabase": "supabase",
    "db:start": "supabase start",
    "db:reset": "supabase db reset",
    "db:test": "supabase test db",
    "functions:test": "deno test supabase/functions/tests --allow-env"
  },
  "devDependencies": {
    "supabase": "^2.40.0"
  }
}
```

Run: `npm install`

Expected: `package-lock.json` is created and `npx supabase --version` exits 0.

- [ ] **Step 2: Initialize Supabase and restrict generated state**

Run: `npm run supabase -- init`

Append these lines to `.gitignore` only if absent:

```gitignore
supabase/.branches/
supabase/.temp/
```

In `supabase/config.toml`, set:

```toml
project_id = "bhargava-family-app"

[auth]
site_url = "bhargavafamily://auth-callback"
additional_redirect_urls = ["bhargavafamily://auth-callback"]
enable_signup = false

[auth.email]
enable_signup = false
double_confirm_changes = true
enable_confirmations = true
otp_expiry = 900
otp_length = 6
```

Expected: the committed config contains no hosted project reference or secret.

- [ ] **Step 3: Add an intentionally empty seed boundary**

Create `supabase/seed.sql`:

```sql
-- Synthetic development records are added by migrations/tests that own their schema.
-- Real family information must never be committed to this file.
```

- [ ] **Step 4: Verify a clean CI reset**

Push the scaffold branch so `.github/workflows/backend-tests.yml` runs:

```bash
git push -u origin codex/authentication-foundation
```

Expected: the GitHub-hosted `Backend Tests` workflow starts Supabase, resets the database, lints it, and exits 0. No Supabase service is exposed from the Cloud PC.

- [ ] **Step 5: Commit**

```bash
git add package.json package-lock.json .gitignore supabase/config.toml supabase/seed.sql .github/workflows/backend-tests.yml docs/superpowers/plans/2026-07-20-authentication-foundation.md
git commit -m "build: initialize Supabase development stack"
```

### Task 2: Identity Schema, Constraints, and RLS

**Files:**
- Create: `supabase/migrations/202607200001_authentication_foundation.sql`
- Create: `supabase/tests/database/authentication_foundation.test.sql`

**Interfaces:**
- Consumes: Supabase `auth.users` and JWT `auth.uid()`.
- Produces: `public.people`, `public.accounts`, `public.invitations`, `public.claims`, `public.app_policies`, `public.audit_events`, `public.current_account()`, and `public.is_reviewer()`.

- [ ] **Step 1: Write failing pgTAP structure tests**

Create `supabase/tests/database/authentication_foundation.test.sql` with the initial assertions:

```sql
begin;
select plan(10);

select has_table('public', 'people');
select has_table('public', 'accounts');
select has_table('public', 'invitations');
select has_table('public', 'claims');
select has_table('public', 'app_policies');
select has_table('public', 'audit_events');
select col_is_pk('public', 'people', 'id');
select col_is_unique('public', 'accounts', 'person_id');
select policies_are('public', 'people', array['approved members read own person only']);
select policies_are('public', 'accounts', array['users read own account']);

select * from finish();
rollback;
```

Run: `npm run db:test`

Expected: FAIL because the tables do not exist.

- [ ] **Step 2: Create enums and identity tables**

Create `supabase/migrations/202607200001_authentication_foundation.sql` beginning with:

```sql
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
  phone_e164 text check (phone_e164 is null or phone_e164 ~ '^\\+[1-9][0-9]{7,14}$'),
  contact_email citext,
  biography text check (biography is null or length(biography) <= 1000),
  photo_path text,
  is_verified boolean not null default false,
  row_version bigint not null default 1,
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
returns trigger language plpgsql security definer set search_path = '' as $$
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
  invited_email citext not null,
  target_person_id uuid not null references public.people(id) on delete restrict,
  invited_by uuid not null references public.accounts(user_id) on delete restrict,
  token_hash text not null unique,
  status public.invitation_status not null default 'pending',
  expires_at timestamptz not null,
  accepted_by uuid references public.accounts(user_id),
  created_at timestamptz not null default now(),
  check (expires_at > created_at)
);

create unique index one_pending_invitation_per_person
on public.invitations(target_person_id) where status = 'pending';

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
  invitation_lifetime_hours integer not null default 72 check (invitation_lifetime_hours between 1 and 720),
  updated_at timestamptz not null default now(),
  check (unlimited_depth or cousin_depth_limit is not null)
);

insert into public.app_policies(singleton, cousin_depth_limit) values (true, 3);

create table public.audit_events (
  id bigint generated always as identity primary key,
  actor_user_id uuid references public.accounts(user_id),
  action text not null,
  target_type text not null,
  target_id uuid,
  outcome text not null check (outcome in ('succeeded', 'denied', 'failed')),
  correlation_id uuid not null default gen_random_uuid(),
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);
```

- [ ] **Step 3: Add fail-closed helpers and policies**

Append to the migration:

```sql
create or replace function public.current_account()
returns public.accounts language sql stable security definer set search_path = '' as $$
  select a from public.accounts a where a.user_id = auth.uid();
$$;

create or replace function public.is_reviewer()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select a.status = 'approved' and a.role in ('trusted_elder', 'admin')
                   from public.accounts a where a.user_id = auth.uid()), false);
$$;

alter table public.people enable row level security;
alter table public.accounts enable row level security;
alter table public.invitations enable row level security;
alter table public.claims enable row level security;
alter table public.app_policies enable row level security;
alter table public.audit_events enable row level security;

create policy "approved members read own person only" on public.people for select to authenticated
using (exists (select 1 from public.accounts a
              where a.user_id = auth.uid() and a.status = 'approved' and a.person_id = people.id));

create policy "users read own account" on public.accounts for select to authenticated
using (user_id = auth.uid());

create policy "users read own invitation" on public.invitations for select to authenticated
using (lower(invited_email::text) = lower(coalesce(auth.jwt() ->> 'email', '')));

create policy "users read own claims" on public.claims for select to authenticated
using (claimant_user_id = auth.uid());

revoke all on public.audit_events from anon, authenticated;
revoke insert, update, delete on public.app_policies from anon, authenticated;
```

Do not add client write policies in this phase; privileged writes belong to Edge Functions.

- [ ] **Step 4: Expand pgTAP tests for denial paths**

Append test setup using `tests.create_supabase_user(...)` or the installed Supabase test-helper equivalent, then assert:

```sql
select is_empty(
  $$ select id from public.people $$,
  'pending authenticated user cannot read people'
);

select throws_ok(
  $$ insert into public.audit_events(action, target_type, outcome)
     values ('forged', 'account', 'succeeded') $$,
  '42501',
  null,
  'authenticated client cannot forge audit events'
);
```

Use distinct fixtures for anonymous, pending, approved-member, trusted-elder, and admin JWT contexts. Test every table with at least one allowed and one denied operation. Update `plan(...)` to the exact assertion count.

- [ ] **Step 5: Reset, lint, and test**

Run: `npm run db:reset`

Run: `npm run supabase -- db lint --local --level warning`

Run: `npm run db:test`

Expected: all commands exit 0 and pgTAP reports all tests passed.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/202607200001_authentication_foundation.sql supabase/tests/database/authentication_foundation.test.sql
git commit -m "feat: add invitation identity schema"
```

### Task 3: Protected Invitation Command

**Files:**
- Create: `supabase/functions/create-invitation/handler.ts`
- Create: `supabase/functions/create-invitation/index.ts`
- Create: `supabase/functions/tests/create-invitation/handler.test.ts`
- Create: `supabase/functions/_shared/errors.ts`

**Interfaces:**
- Consumes: authenticated reviewer JWT, `{ targetPersonId: string, email: string }`, service-role client, `app_policies.invitation_lifetime_hours`.
- Produces: HTTP `201 { invitationId, expiresAt }` or stable `{ code, message }` errors without leaking whether unrelated people/accounts exist.

- [ ] **Step 1: Write failing validation tests**

Create `handler.test.ts` covering normalized email, invalid email, non-reviewer denial, claimed target denial, duplicate pending invitation denial, and successful creation. Use injected dependencies rather than network calls:

```ts
Deno.test('rejects a caller without reviewer role', async () => {
  const response = await createInvitation(
    { targetPersonId: crypto.randomUUID(), email: 'member@example.com' },
    { actor: { userId: crypto.randomUUID(), role: 'member', status: 'approved' }, repository: fakeRepository() },
  )
  assertEquals(response, { ok: false, status: 403, code: 'not_authorized' })
})
```

Run: `npm run functions:test`

Expected: FAIL because `createInvitation` is missing.

- [ ] **Step 2: Implement pure orchestration**

In `handler.ts`, define and implement:

```ts
export type CreateInvitationInput = { targetPersonId: string; email: string }
export type Actor = { userId: string; role: 'member' | 'trusted_elder' | 'admin'; status: string }
export interface InvitationRepository {
  targetIsAvailable(personId: string): Promise<boolean>
  createAndAudit(input: { targetPersonId: string; normalizedEmail: string; actorUserId: string }):
    Promise<{ invitationId: string; expiresAt: string }>
  sendAuthInvitation(email: string, invitationId: string): Promise<void>
  revokeAfterDeliveryFailure(invitationId: string): Promise<void>
}

export async function createInvitation(
  input: CreateInvitationInput,
  dependencies: { actor: Actor; repository: InvitationRepository },
): Promise<{ ok: true; status: 201; invitationId: string; expiresAt: string } |
           { ok: false; status: 400 | 403 | 409; code: string }> {
  const email = input.email.trim().toLocaleLowerCase('en-US')
  if (!/^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$/.test(email)) return { ok: false, status: 400, code: 'invalid_email' }
  if (dependencies.actor.status !== 'approved' || !['trusted_elder', 'admin'].includes(dependencies.actor.role)) {
    return { ok: false, status: 403, code: 'not_authorized' }
  }
  if (!await dependencies.repository.targetIsAvailable(input.targetPersonId)) {
    return { ok: false, status: 409, code: 'target_unavailable' }
  }
  const created = await dependencies.repository.createAndAudit({
    targetPersonId: input.targetPersonId,
    normalizedEmail: email,
    actorUserId: dependencies.actor.userId,
  })
  try {
    await dependencies.repository.sendAuthInvitation(email, created.invitationId)
  } catch {
    await dependencies.repository.revokeAfterDeliveryFailure(created.invitationId)
    return { ok: false, status: 409, code: 'delivery_failed' }
  }
  return { ok: true, status: 201, ...created }
}
```

- [ ] **Step 3: Implement the authenticated Edge entry point**

In `index.ts`, verify the bearer JWT with a user-scoped Supabase client, load the caller account, then construct a service-role repository. Call a transactional database RPC for invitation creation/audit and `auth.admin.inviteUserByEmail` for delivery. If delivery fails, call a second protected RPC that revokes the invitation and appends a `delivery_failed` audit event, allowing a safe retry. Never accept role, expiry, inviter ID, or redirect URL from the request body. Return only stable error codes and attach/generate `x-correlation-id`.

Environment variables are exactly: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, and `INVITATION_REDIRECT_URL`.

- [ ] **Step 4: Run function tests**

Run: `npm run functions:test`

Expected: all handler tests pass.

- [ ] **Step 5: Serve and smoke-test locally**

Run: `npm run supabase -- functions serve create-invitation --env-file supabase/.env.local`

Invoke once with no bearer token.

Expected: HTTP 401 with `{ "code": "authentication_required" }`; no email is sent and no invitation is inserted.

- [ ] **Step 6: Commit**

```bash
git add supabase/functions
git commit -m "feat: protect family invitations"
```

### Task 4: iOS Configuration and Supabase Dependency

**Files:**
- Modify: `BhargavaFamilyApp.xcodeproj/project.pbxproj`
- Create: `BhargavaFamilyApp/Configuration/AppConfiguration.swift`
- Create: `BhargavaFamilyAppTests/Configuration/AppConfigurationTests.swift`
- Modify: `BhargavaFamilyApp/BhargavaFamilyApp.swift`

**Interfaces:**
- Consumes: `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` build settings exposed as generated Info.plist keys.
- Produces: `AppConfiguration.supabaseURL`, `AppConfiguration.supabasePublishableKey`, and an explicit configuration error.

- [ ] **Step 1: Add the test target and failing configuration tests**

Add `BhargavaFamilyAppTests` as an iOS unit-test target in the project and include it in a shared `BhargavaFamilyApp` scheme committed under `BhargavaFamilyApp.xcodeproj/xcshareddata/xcschemes/`. Create tests asserting that a valid HTTPS URL/key succeeds, a missing value fails, and placeholder values fail:

```swift
func testProductionConfigurationRejectsPlaceholders() {
    XCTAssertThrowsError(try AppConfiguration(values: [
        "SUPABASE_URL": "https://example.supabase.co",
        "SUPABASE_PUBLISHABLE_KEY": "replace-me"
    ]))
}
```

Run in Codemagic/macOS: `xcodebuild test -project BhargavaFamilyApp.xcodeproj -scheme BhargavaFamilyApp -destination 'platform=iOS Simulator,name=iPhone 17'`

Expected: FAIL because `AppConfiguration` is undefined.

- [ ] **Step 2: Add supabase-swift through Swift Package Manager**

Add package URL `https://github.com/supabase/supabase-swift.git` with an up-to-next-major requirement starting at `2.0.0`. Link the `Supabase` product to the app target. Commit `Package.resolved` after resolution.

- [ ] **Step 3: Implement fail-closed configuration**

Create:

```swift
import Foundation

struct AppConfiguration: Equatable {
    enum ConfigurationError: LocalizedError, Equatable {
        case missing(String)
        case invalid(String)
    }

    let supabaseURL: URL
    let supabasePublishableKey: String

    init(values: [String: String]) throws {
        guard let rawURL = values["SUPABASE_URL"], !rawURL.isEmpty else { throw ConfigurationError.missing("SUPABASE_URL") }
        guard let url = URL(string: rawURL), url.scheme == "https", url.host != nil else { throw ConfigurationError.invalid("SUPABASE_URL") }
        guard let key = values["SUPABASE_PUBLISHABLE_KEY"], !key.isEmpty, key != "replace-me" else {
            throw ConfigurationError.invalid("SUPABASE_PUBLISHABLE_KEY")
        }
        supabaseURL = url
        supabasePublishableKey = key
    }

    static func bundled(_ bundle: Bundle = .main) throws -> Self {
        try Self(values: [
            "SUPABASE_URL": bundle.object(forInfoDictionaryKey: "SupabaseURL") as? String ?? "",
            "SUPABASE_PUBLISHABLE_KEY": bundle.object(forInfoDictionaryKey: "SupabasePublishableKey") as? String ?? ""
        ])
    }
}
```

Set generated Info.plist keys from build settings; do not commit real production values. Debug may point to localhost via an untracked `.xcconfig`; Release values come from Codemagic environment variables.

- [ ] **Step 4: Make configuration failure visible and safe**

Change the app entry point to build dependencies once. If configuration fails, show a non-sensitive `ConfigurationUnavailableView` with retry/support text. Do not create `FamilyStore()` or display sample data in this path.

- [ ] **Step 5: Run tests and build**

Run the unit-test command and the existing generic simulator build.

Expected: tests pass; Debug without configuration shows the safe configuration screen; Release requires injected values.

- [ ] **Step 6: Commit**

```bash
git add BhargavaFamilyApp.xcodeproj BhargavaFamilyApp BhargavaFamilyAppTests
git commit -m "feat: add fail-closed Supabase configuration"
```

### Task 5: Authentication Repository and Session State Machine

**Files:**
- Create: `BhargavaFamilyApp/Authentication/AuthenticationModels.swift`
- Create: `BhargavaFamilyApp/Authentication/AuthenticationRepository.swift`
- Create: `BhargavaFamilyApp/Authentication/SupabaseAuthenticationRepository.swift`
- Create: `BhargavaFamilyApp/Authentication/InMemoryAuthenticationRepository.swift`
- Create: `BhargavaFamilyApp/Authentication/AppSession.swift`
- Create: `BhargavaFamilyAppTests/Authentication/AppSessionTests.swift`

**Interfaces:**
- Consumes: Supabase Auth session and the caller's `accounts` row.
- Produces: `AppSession.State` and async `requestOTP`, `restore`, `handleCallback`, `refreshAccount`, and `signOut` actions.

- [ ] **Step 1: Write state-machine tests first**

Cover: no restored session → signed out; OTP success → awaiting email; restored pending account → pending claim; approved account → approved; repository 401 → signed out and cleared; sign-out clears repository session before publishing signed-out state; stale restore result cannot overwrite a later sign-out.

```swift
@MainActor
func testPendingAccountRoutesToPendingClaim() async {
    let repository = InMemoryAuthenticationRepository(
        restoredSession: .init(userID: UUID(), email: "invitee@example.com"),
        account: .init(status: .pending, role: .member, personID: nil)
    )
    let session = AppSession(repository: repository)
    await session.restore()
    XCTAssertEqual(session.state, .pendingClaim)
}
```

Run tests.

Expected: FAIL because the authentication types are missing.

- [ ] **Step 2: Define domain types and repository contract**

```swift
struct AuthenticatedUser: Equatable, Sendable { let userID: UUID; let email: String }
enum AccountStatus: String, Decodable, Sendable { case pending, approved, suspended, closed }
enum AccountRole: String, Decodable, Sendable { case member, trustedElder = "trusted_elder", admin }
struct AccountAccess: Equatable, Decodable, Sendable {
    let status: AccountStatus
    let role: AccountRole
    let personID: UUID?
}

protocol AuthenticationRepository: Sendable {
    func restoreSession() async throws -> AuthenticatedUser?
    func requestEmailOTP(_ email: String) async throws
    func handleCallback(_ url: URL) async throws -> AuthenticatedUser
    func fetchAccountAccess() async throws -> AccountAccess
    func signOut() async throws
}
```

- [ ] **Step 3: Implement deterministic in-memory behavior**

The in-memory repository records calls, returns injected results, and never sleeps. It must be safe for `@MainActor` tests and SwiftUI previews.

- [ ] **Step 4: Implement `AppSession`**

Use `@MainActor final class AppSession: ObservableObject`. Define states: `.restoring`, `.signedOut`, `.requestingOTP(email:)`, `.awaitingEmail(email:)`, `.pendingClaim`, `.approved(AccountAccess)`, `.blocked`, and `.failed(SessionError)`. Use a monotonically increasing operation ID so late async results cannot overwrite a newer user action.

- [ ] **Step 5: Implement Supabase repository**

Construct a single `SupabaseClient`. Use `auth.session` for restoration, `auth.signInWithOTP(email:redirectTo:shouldCreateUser: false)` for OTP requests, supported deep-link session exchange for callbacks, a single-row `accounts` select for access, and `auth.signOut()` for sign-out. Map SDK/network errors to stable domain errors without exposing server strings to views.

- [ ] **Step 6: Run tests**

Run the full app unit-test suite.

Expected: all session tests pass, including cancellation/race tests.

- [ ] **Step 7: Commit**

```bash
git add BhargavaFamilyApp/Authentication BhargavaFamilyAppTests/Authentication
git commit -m "feat: add invitation authentication state"
```

### Task 6: Authentication UI Shell

**Files:**
- Create: `BhargavaFamilyApp/Authentication/AuthenticationRootView.swift`
- Create: `BhargavaFamilyApp/Authentication/SignInView.swift`
- Create: `BhargavaFamilyApp/Authentication/CheckEmailView.swift`
- Create: `BhargavaFamilyApp/Authentication/PendingClaimView.swift`
- Modify: `BhargavaFamilyApp/BhargavaFamilyApp.swift`
- Modify: `BhargavaFamilyApp/Views/ContentView.swift`
- Modify: `BhargavaFamilyApp.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `AppSession.State` and session actions.
- Produces: a fail-closed root that renders `ContentView` only for `.approved`.

- [ ] **Step 1: Add UI tests for routing and validation**

Add tests or ViewInspector-free state assertions proving that whitespace-only/invalid email does not call the repository, valid email does, pending state cannot instantiate family content, and sign-out returns to sign-in.

Expected: tests fail before UI/presentation validation is implemented.

- [ ] **Step 2: Implement sign-in and check-email screens**

`SignInView` explains that membership is invitation-only, accepts an email address with `.textContentType(.emailAddress)`, normalizes surrounding whitespace, disables submission when invalid or busy, and uses generic failure copy that does not reveal whether an email is invited.

`CheckEmailView` displays the normalized destination, resend cooldown, change-email action, and accessibility announcements for success/failure.

- [ ] **Step 3: Implement pending and blocked screens**

`PendingClaimView` displays pending/rejected status, refresh, sign-out, and administrator-contact guidance without showing any family record. `BlockedView` handles suspended/closed accounts similarly.

- [ ] **Step 4: Implement root routing and deep-link handling**

`AuthenticationRootView` switches exhaustively over `AppSession.State`. Only `.approved` constructs `ContentView`. Wire `.onOpenURL` to `AppSession.handleCallback(_:)`. Cover content during restore and immediately when session revocation is detected.

- [ ] **Step 5: Remove production sample fallback**

Keep `SampleFamily` only for explicit previews/tests. Do not initialize `FamilyStore` until the approved path; mark its current implementation as preview-only pending the family-graph plan. App Intents must route to sign-in when no approved session exists.

- [ ] **Step 6: Run accessibility and smoke tests**

Build at default and accessibility-extra-extra-extra-large Dynamic Type. Verify VoiceOver labels for email, submit, resend, refresh, and sign-out. Verify no family names appear in app-switcher snapshots while signed out/pending by covering sensitive content on inactive scene phase.

- [ ] **Step 7: Commit**

```bash
git add BhargavaFamilyApp BhargavaFamilyAppTests BhargavaFamilyApp.xcodeproj
git commit -m "feat: gate the app behind invited membership"
```

### Task 7: CI and TestFlight Release Guardrails

**Files:**
- Modify: `codemagic.yaml`
- Modify: `.github/workflows/ios-build.yml`
- Create: `docs/operations/supabase-environments.md`

**Interfaces:**
- Consumes: Codemagic environment group values `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, Supabase deployment secrets, and existing iOS signing integration.
- Produces: repeatable database/function tests, iOS unit tests, incrementing TestFlight builds, and an explicit production deployment runbook.

- [ ] **Step 1: Add backend verification before iOS builds**

Add scripts that install Node dependencies, start the local Supabase stack, run `supabase db reset`, `supabase db lint --local --level warning`, `supabase test db`, and Deno function tests. Always stop the local stack in cleanup.

Expected: intentionally breaking an RLS test makes the workflow fail before archive/signing.

- [ ] **Step 2: Add iOS unit tests**

Before the generic simulator build, run:

```bash
xcodebuild test \
  -project BhargavaFamilyApp.xcodeproj \
  -scheme BhargavaFamilyApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

Resolve the simulator name dynamically from `simctl list` if the selected Xcode image uses a different current iPhone runtime.

- [ ] **Step 3: Fix release numbering and TestFlight upload**

Before archive, set `CURRENT_PROJECT_VERSION=$CM_BUILD_NUMBER` through `xcode-project build-ipa` arguments or `agvtool`. Set:

```yaml
publishing:
  app_store_connect:
    auth: integration
    submit_to_testflight: true
    submit_to_app_store: false
```

Keep simulator and release workflows separate. Do not auto-trigger the signed release workflow on every pull request.

- [ ] **Step 4: Document environment creation and deployment**

In `docs/operations/supabase-environments.md`, document:

1. Create development and production projects; production region is Mumbai and plan is Pro.
2. Configure custom SMTP, SPF, DKIM, DMARC, redirect URL, email templates, resend cooldowns, and CAPTCHA/rate limits.
3. Store project references and deployment tokens only in protected Codemagic groups.
4. Validate locally with `npm run db:reset`, lint, pgTAP, and Deno tests.
5. Link/deploy to development first; run integration smoke tests.
6. Verify the latest production backup and migration list.
7. Require explicit human approval before `supabase db push --linked` or function deployment to production.
8. Seed the first admin through a one-time reviewed SQL operation; record the action and remove the bootstrap mechanism afterward.
9. Run the signed Codemagic workflow and confirm TestFlight processing.

- [ ] **Step 5: Run full verification**

Run backend tests locally and trigger the Codemagic simulator workflow. Then trigger the release workflow against development configuration only.

Expected: backend tests pass, iOS tests pass, simulator build passes, and the signed build uploads to TestFlight with a unique build number. No production database mutation occurs from a pull-request workflow.

- [ ] **Step 6: Commit**

```bash
git add codemagic.yaml .github/workflows/ios-build.yml docs/operations/supabase-environments.md
git commit -m "ci: verify auth foundation and publish beta"
```

## Phase 1 Completion Gate

Before beginning the family-graph plan, demonstrate all of the following against the development Supabase project:

1. An uninvited email receives generic denial and no usable account.
2. An admin/trusted elder server command can invite an existing unclaimed synthetic person.
3. The invited person completes email authentication and lands in pending claim state.
4. Pending, suspended, and closed accounts cannot construct or display family content.
5. An approved synthetic account reaches the existing prototype content through the repository boundary.
6. Sign-out and revoked-session handling clear/cover sensitive state.
7. pgTAP proves table, RLS, self-approval, and audit-event denial paths.
8. Deno tests prove invitation validation and role checks.
9. Swift tests prove session routing and async race handling.
10. Codemagic uploads a uniquely numbered TestFlight build without submitting it for App Store review.
