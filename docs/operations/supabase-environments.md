# Supabase and Codemagic Environments

## Environment model

Phase 1 uses two isolated environments:

- Local/CI development: synthetic data only. GitHub Actions creates a fresh local Supabase stack on Ubuntu for every backend run.
- Production beta: one Supabase Pro project in Mumbai (`ap-south-1`) for invited members in India and the USA. Do not load synthetic seed data into this project.

A separate hosted staging project is intentionally deferred for the first private beta. Every migration must pass the fresh-database GitHub workflow before a separately approved production deployment.

## Production Supabase project

Before inviting real users:

1. Create the project in Mumbai and record its project reference in the restricted operator password manager.
2. Enable backups appropriate to the Pro plan and verify that an operator can locate the latest backup.
3. Configure the iOS redirect URL `bhargavafamily://auth-callback`.
4. Keep public sign-up disabled. Invitations must be created by the protected server function.
5. Configure production SMTP with SPF, DKIM, and DMARC. Disable link tracking that rewrites authentication links.
6. Under **Authentication → Sign In / Providers → Email**, set Email OTP expiration to `3600` seconds and the resend cooldown to `60` seconds. Keep `app_policies.invitation_lifetime_hours` at `1`; invite links use the same Auth expiry clock.
7. Customize the Invite template with `{{ .ConfirmationURL }}` and the Magic Link template with `{{ .Token }}` so normal sign-in sends the six-digit OTP expected by the app. Send test messages through the production SMTP route before inviting users.
8. Start with 30 email/OTP sends per hour and the 60-second per-address cooldown, then tune only from sanitized `429` telemetry. Record every dashboard change in the deployment record.
9. Do not enable CAPTCHA until the native sign-in client supplies a valid Turnstile or hCaptcha token. CAPTCHA client support and a successful device test are release blockers before onboarding real users; a dashboard-only toggle would make every current OTP request fail.
10. Apply migrations only from a reviewed commit and never run `supabase/seed.sql` against production.
11. Store the service-role key, SMTP password, and deployment token only in protected server/deployment settings. They must never appear in Codemagic client configuration or an app binary.

## Codemagic variable group

In Codemagic, open the BhargavaFamilyApp application, then **Environment variables**. Create a group named `supabase_production` with:

| Variable | Value | Handling |
|---|---|---|
| `SUPABASE_URL` | Production project HTTPS URL | Restricted group |
| `SUPABASE_PUBLISHABLE_KEY` | Publishable key (or legacy anonymous client key) | Restricted group |

Do not add an `sb_secret_...` key or legacy service-role JWT. The release workflow and the app both reject these server credentials and obvious unexpanded values.

Limit the group to this Codemagic application and to release operators. The existing App Store Connect integration and iOS signing assets remain separate.

## Release workflow

Run `ios-release-archive` only from a reviewed commit. It:

1. Imports `supabase_production` without printing values.
2. validates the HTTPS URL and client-key class;
3. runs all Swift package tests;
4. sets a unique Codemagic build number;
5. creates a signed IPA; and
6. uploads to TestFlight without submitting to App Store review.

If validation, tests, signing, or archive fails, no TestFlight upload occurs. Confirm the build in App Store Connect and assign beta testers deliberately after smoke testing.

Both Codemagic workflows wait for the GitHub **Backend Tests** workflow to pass at the exact `CM_COMMIT` SHA before starting an iOS test or build. The repository is public, so this gate needs no additional GitHub credential; if the repository becomes private, add a read-only `GITHUB_TOKEN` to Codemagic.

## Operational checks

- Use synthetic accounts for the first signed smoke test.
- Verify OTP delivery once from India and once from the USA before broader invitations.
- Record sanitized p50/p95 request latency by broad region; never log email, names, tokens, claim notes, or relationships.
- Review backup status before each production migration.
- Keep a rollback-compatible prior TestFlight build available until the new build passes authentication and access-control smoke tests.

## Approval-gated deployment checklist

Run these commands from the reviewed commit. Use a shell session whose history is disabled or protected; never paste access tokens, database passwords, SMTP credentials, or service-role keys into a shared log.

### 1. Local and CI preflight

```bash
npm ci
npx supabase start --exclude edge-runtime,imgproxy,logflare,postgres-meta,realtime,storage-api,studio,supavisor,vector
npx supabase db reset
npx supabase db lint --local --level warning
npx supabase test db
npm run functions:test
npx deno check supabase/functions/create-invitation/index.ts
python3 -m unittest discover -s scripts/tests -v
npx supabase stop --no-backup
```

Confirm the GitHub **Backend Tests** and **iOS Build** checks succeeded for the same full commit SHA. A success on another commit is not evidence for deployment.

### 2. Development deployment and integration smoke test

```bash
npx supabase login
npx supabase link --project-ref "$DEV_PROJECT_REF"
npx supabase migration list --linked
npx supabase db push --linked --dry-run
npx supabase db push --linked
npx supabase secrets set INVITATION_REDIRECT_URL=bhargavafamily://auth-callback --project-ref "$DEV_PROJECT_REF"
npx supabase functions deploy create-invitation --project-ref "$DEV_PROJECT_REF"
```

Use synthetic identities only. Record pass/fail evidence for all of these cases:

1. no token → `401`; approved member → `403`; trusted elder/admin → `201`;
2. invalid JSON and invalid target UUID → `400 invalid_request`;
3. unavailable person → `409`, with no email and no new pending invitation;
4. email-delivery failure → revoked invitation plus audit event;
5. valid invite → callback → pending routing, followed by sign-out;
6. OTP/invite link immediately before and after the one-hour expiry boundary;
7. pending, suspended, and closed accounts cannot read family data.

Do not proceed if the development migration list diverges, any smoke test fails, or logs contain personal data or credentials.

### 3. Production preflight and approval stop

1. Confirm the reviewed commit SHA, successful exact-SHA checks, change ticket, operator, and independent reviewer.
2. Confirm the latest production backup timestamp and document who can initiate restore.
3. Link production, run `npx supabase migration list --linked`, and compare every local and remote migration timestamp.
4. Run `npx supabase db push --linked --dry-run` and attach the output to the change record.
5. Verify SMTP, redirect allowlist, one-hour OTP expiration, 60-second resend cooldown, rate limits, email templates, and CAPTCHA release condition.
6. **Stop here. Obtain explicit written approval immediately before either production mutation below.** Approval of the pull request or Codemagic build is not deployment approval.

### 4. Production mutation after approval

```bash
npx supabase db push --linked
npx supabase secrets set INVITATION_REDIRECT_URL=bhargavafamily://auth-callback --project-ref "$PROD_PROJECT_REF"
npx supabase functions deploy create-invitation --project-ref "$PROD_PROJECT_REF"
npx supabase migration list --linked
```

Do not use `--include-seed`. After deployment, repeat the synthetic integration smoke test, preserve sanitized evidence, run `ios-release-archive`, confirm TestFlight processing, and assign testers manually. If verification fails, stop invitations, retain evidence, and choose a reviewed forward migration or backup restore; never edit an already-applied migration in place.

## First administrator bootstrap

The invitation function requires an existing approved administrator and an existing verified person. Bootstrap the first administrator as a one-time, peer-reviewed operator action:

1. Create or import the administrator's verified `people` record.
2. Use **Authentication → Users → Send invitation** in the Supabase dashboard for that administrator's email.
3. Have the administrator authenticate once so the database trigger creates their pending `accounts` row.
4. In one reviewed SQL transaction, link that account to the verified person, change status to `approved`, set role to `admin`, and append an `administrator.bootstrap` audit event.
5. Verify that the administrator can create a synthetic invitation through the protected function before importing or inviting real family members.

Record the operator, reviewer, commit, and timestamp outside the database. Do not create additional administrators through direct SQL; later role management must use a protected audited server operation.

## Current Phase 1 boundary

Authentication, invitation isolation, and pending/blocked routing are implemented. Approved accounts intentionally receive a safe placeholder rather than `SampleFamily`; verified family-graph reads, claim submission/review, role management, and invitation/Auth-user revocation are the next production phase. Until those operations exist, do not onboard real family data or treat the build as a complete member experience.
