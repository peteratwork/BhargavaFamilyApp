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
6. Apply migrations only from a reviewed commit and never run `supabase/seed.sql` against production.
7. Store the service-role key, SMTP password, and deployment token only in protected server/deployment settings. They must never appear in Codemagic client configuration or an app binary.

## Codemagic variable group

In Codemagic, open the BhargavaFamilyApp application, then **Environment variables**. Create a group named `supabase_production` with:

| Variable | Value | Handling |
|---|---|---|
| `SUPABASE_URL` | Production project HTTPS URL | Restricted group |
| `SUPABASE_PUBLISHABLE_KEY` | Publishable key (or legacy anonymous client key) | Restricted group |

Do not add an `sb_secret_...` key or service-role JWT. The release workflow and the app both reject obvious secret/unexpanded values.

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

## Operational checks

- Use synthetic accounts for the first signed smoke test.
- Verify OTP delivery once from India and once from the USA before broader invitations.
- Record sanitized p50/p95 request latency by broad region; never log email, names, tokens, claim notes, or relationships.
- Review backup status before each production migration.
- Keep a rollback-compatible prior TestFlight build available until the new build passes authentication and access-control smoke tests.
