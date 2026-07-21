# Bhargava Family App Production Foundation Design

## Purpose

Transform the validated SwiftUI prototype into a secure, persistent, invitation-only private beta for up to 100 family members. Ship the iOS client first while keeping the backend platform-neutral for a future Android client.

This foundation preserves the current product areas—Home, Family Tree, Discover, Meetups, Profile, and App Intents—while replacing sample-only state with authenticated, authorized production data.

## Product Decisions

- Use Supabase for PostgreSQL, authentication, storage, Edge Functions, and database APIs.
- Authenticate with passwordless email OTP.
- Permit account creation only through invitations.
- Allow admins and trusted elders to invite people and review claims.
- Allow only admins to assign or remove the trusted-elder role.
- Invite a person to claim an existing family-tree record in the first release.
- Keep invitations and claims separate so a future workflow can propose a new person without redesigning the schema.
- Ship native iOS first. Keep all schema, policies, and server operations independent of Apple-only services.
- Manage invitations and reviews inside role-gated iOS screens.
- Permit browsing through third cousins by default.
- Store relationship visibility depth as a server-controlled policy supporting second, third, fourth, fifth, or unlimited depth.
- Initially expose contact details to relatives within the permitted relationship range.
- Represent contact visibility as a server policy so per-field consent or connection-request modes can be introduced later.
- Allow members to directly edit city, phone, photo, and biography.
- Require review for legal name, birth date, parents, spouse, other family links, and account-to-person claims.
- Target a private beta of no more than 100 members.

## Architecture

Use a Supabase-native architecture with protected server functions. The iOS client reads permitted data through the Supabase Swift SDK and PostgreSQL row-level security. Sensitive operations—sending invitations, approving claims, changing roles, changing protected identity fields, and modifying family links—must go through Supabase Edge Functions with server-side validation and audit logging.

The iOS app is divided into focused modules:

- **Authentication:** Email OTP, invitation validation, session restoration, and sign-out.
- **Member Profile:** Current profile display and permitted direct edits.
- **Family Graph:** Incremental loading of relatives within the configured visibility policy.
- **Claims and Reviews:** Ownership claims and proposed protected changes.
- **Administration:** Invitations, approvals, rejections, and trusted-elder management.
- **Meetups:** Persistent events, audiences, attendance, and host operations.
- **Shared Infrastructure:** Supabase client, repository interfaces, network state, error mapping, secure session storage, structured logging, and runtime configuration.

Views depend on repository interfaces rather than treating `FamilyStore` as the source of truth. Production uses Supabase-backed repositories. Previews and deterministic tests use in-memory implementations. The future Android client consumes the same database functions and protected server operations.

## Region and International Use

Create the production Supabase project in South Asia (Mumbai), AWS region `ap-south-1`. This supports the expected long-term concentration in India while remaining adequate for the evenly split India/USA private beta.

- Execute database-intensive Edge Functions in Mumbai.
- Store event timestamps in UTC.
- Store each meetup's IANA time-zone identifier, such as `Asia/Kolkata` or `America/Los_Angeles`.
- Display times in the viewer's local zone while also identifying the meetup's time zone.
- Store birth dates as date-only values.
- Store phone numbers in international E.164 form.
- Model city, administrative region, and country separately; do not store exact location for discovery.
- Support Unicode names and do not require a Western first-name/last-name structure.
- Use locale-aware date, time, address, and sorting presentation.
- Paginate and cache family and discovery results; never download the entire graph.
- Measure sanitized p50 and p95 request latency by broad region before considering a read replica.
- Do not add a US read replica during the private beta.

## Data Model

The verified family tree is independent of user accounts. A `people` row represents a family member whether or not that person uses the app. An authenticated account can claim exactly one person.

Core records:

- `people`: display name, date of birth, city, administrative region, country, phone, email, biography, photo reference, verification state, and row version.
- `family_relationships`: two person IDs, normalized relationship type, verification state, effective dates when applicable, creator, and reviewer.
- `accounts`: Supabase Auth user ID, claimed person ID, status, and role (`member`, `trusted_elder`, or `admin`).
- `invitations`: normalized invited email, target person, inviter, expiration, state, and hashed single-use token metadata.
- `claims`: requested account-to-person association, private evidence note, review state, reviewer, and decision timestamp.
- `change_requests`: proposed protected identity or relationship changes, before/after values, state, reviewer, and decision timestamp.
- `meetups`: title, description, location fields, UTC start/end, IANA time zone, host, status, and row version.
- `meetup_audiences`: meetup visibility constraints expressed through permitted relationship ranges or explicit subgroups.
- `meetup_attendance`: meetup, person, RSVP state, and timestamps.
- `app_policies`: relationship-depth limit, contact-visibility mode, invitation lifetime, and other server-controlled settings.
- `audit_events`: append-only privileged-action records with actor, action, target type and ID, outcome, correlation ID, timestamp, and sanitized metadata.

Database constraints and protected operations reject self-links, duplicate active relationships, circular parentage, conflicting active claims, invalid role transitions, and approval of one's own request.

## Authorization and Privacy

Row-level security denies access by default on every exposed table. Database functions determine whether two verified people are connected within the active relationship-depth policy. Queries return only permitted rows and fields; unauthorized data is never downloaded for client-side hiding.

- Uninvited users cannot establish membership or read family records.
- Pending claimants can read only their own invitation/claim status and support content.
- Approved members can read verified relatives permitted by the configured graph depth.
- Contact details are initially readable by permitted relatives.
- Admins and trusted elders can create invitations and review claims or protected changes.
- Reviewers cannot approve requests they created or requests concerning their own protected data.
- Only admins can assign or revoke `trusted_elder` and `admin` roles.
- Privileged mutations validate authority, lock affected rows, apply changes, update graph versions, and append an audit event in one transaction.

Contact visibility uses a policy enum from the outset. The first active mode is `permitted_relatives`; reserved future modes are `per_field_consent` and `approved_connection`.

## Invitation and Claim Flow

1. An admin or trusted elder selects an unclaimed person and enters an email address.
2. A protected Edge Function validates the inviter and target, creates an expiring single-use invitation, and sends a branded invitation/OTP email.
3. The invitee authenticates from the invitation link and sees only the selected existing profile plus the claim flow.
4. The invitee confirms basic details and may submit a private note for reviewers.
5. A different admin or trusted elder approves or rejects the claim.
6. Approval atomically links the authenticated account to the person, consumes the invitation, updates status, and writes an audit event.
7. The approved member receives access to permitted relatives and features.

Expired, replaced, used, or revoked invitations cannot be replayed. Resend actions have cooldowns and attempt limits.

## Feature Behavior

### Home

Show server-derived family score, nearby permitted relatives, permitted cousin counts, and upcoming meetups. Quick actions navigate to Discover and Meetups. Loading, stale, empty, and failure states are explicit.

### Family Tree

Load the nearest generations first and expand on demand up to the active relationship-depth policy. The server returns verified permitted nodes and edges only. Large branches use pagination or bounded expansion.

### Discover

Search only verified permitted relatives. Support country, administrative-region, and city filters. Do not expose coordinates or exact addresses. Relationship labels and shared ancestors are server-derived or verified against server-returned paths.

### Meetups

Persist meetup creation, editing, cancellation, audience, and RSVP state. Hosts manage their events. Admins retain moderation authority. Dates retain their source time zone. Mutations use idempotency keys to avoid duplicates after retries.

### Profile

Separate directly editable fields from protected fields. Direct edits use optimistic concurrency with row versions. Protected edits create review requests and leave verified values unchanged until approval.

### Administration

Provide role-gated lists and detail views for invitations, claims, protected changes, and role management. Trusted elders cannot manage roles. Review decisions show the proposed changes and record a sanitized reason.

### App Intents

Keep navigation intents, but do not expose family names or results while signed out, pending, or unauthorized. Intents route through the same session and authorization state as the app.

## Client State, Offline Behavior, and Errors

Each network-backed screen distinguishes initial loading, refreshing, empty, offline/stale, permission denied, recoverable failure, and service unavailable.

- Restore sessions from Keychain-backed secure storage.
- Cache only the minimum permitted profile, graph, and meetup data using iOS data protection.
- Display cached data offline with a visible last-updated indicator.
- Require a live connection for invitations, approvals, role changes, relationship changes, and other privileged mutations.
- Map server errors to stable client error codes and user-safe messages.
- Retry safe reads with bounded exponential backoff.
- Retry mutations only with idempotency keys.
- On session expiration or revocation, cover sensitive content before returning to sign-in.
- On sign-out, clear sensitive caches and in-memory state.

## Telemetry and Auditability

Keep three data categories separate:

1. **Security audit events:** Mandatory server-side records for invitations, approvals, role changes, protected edits, relationship mutations, and policy changes.
2. **Operational telemetry:** Sanitized error codes, request duration, app version, OS version, platform, broad region, and random correlation IDs.
3. **Optional product analytics:** A vendor-neutral client interface exists, but product event collection is disabled during the initial beta.

Telemetry and logs must not contain names, email addresses, phone numbers, birth dates, family relationships, invitation tokens, claim evidence, profile notes, or other free-form text. Apply short documented retention to operational telemetry and role-restricted access to audit records. TestFlight crash reporting and sanitized backend telemetry are sufficient for the initial beta; no additional analytics vendor is required.

## Environments and Configuration

Maintain two Supabase projects:

- **Development:** Synthetic family data for development, previews, and automated integration tests.
- **Production beta:** Real invited-member data on Supabase Pro in Mumbai with backups and no inactivity pausing.

A separate staging project is out of scope for the first 100 members. Store schema, database functions, row-level policies, Edge Functions, and synthetic seeds in version control. Validate every migration against a fresh development database before production.

Store production secrets in Codemagic environment groups. The public Supabase URL and publishable/anonymous client key may be present in client configuration because row-level security is the authorization boundary. Service-role keys and SMTP credentials must exist only in protected server configuration.

Configure a production SMTP provider with SPF, DKIM, and DMARC before inviting real beta users. Disable email-link tracking that can rewrite single-use authentication links. Use branded, locale-neutral email templates and monitor delivery in India and the USA.

## Testing

- Swift unit tests cover view state, input validation, relationship presentation, caching, localization, time zones, and error mapping.
- Repository contract tests run against in-memory and Supabase-backed implementations.
- Database tests cover every allow and deny path in row-level security.
- Graph tests cover duplicate edges, self-links, circular parentage, relationship depth, and runtime policy changes.
- Edge Function tests cover invitation expiry/replay, claim decisions, self-approval denial, role enforcement, idempotency, and audit records.
- SwiftUI smoke tests cover invitation authentication, pending access, approval, profile edits, discovery, meetup creation/RSVP, and sign-out cache clearing.
- Accessibility checks cover Dynamic Type, VoiceOver labels, contrast, touch targets, and reduced-motion behavior.
- International tests cover India/USA locales, time zones, Unicode names, E.164 numbers, date-only birthdays, and daylight-saving transitions.

Codemagic runs compile checks and automated tests for pull requests. Signed release builds increment build numbers automatically and upload successful builds to TestFlight. No workflow submits directly to App Store review.

## Migration and Release Safety

Replace prototype features incrementally behind repository interfaces. Synthetic preview data remains available only in development and previews. Production never silently falls back to sample family data.

Database migrations are a separate explicitly approved production operation. Verify the latest backup before applying a production migration. Prefer additive, backward-compatible schema changes so the prior TestFlight build remains functional during rollout. Failed app builds can be withheld or expired in TestFlight. Destructive schema changes require a later cleanup release after active clients have migrated.

## Security and Member Rights

- Store sessions in Keychain and use iOS data protection for local caches.
- Do not place family data in logs, notification text, widgets, or analytics without an explicit future design review.
- Provide sign-out, profile review, incorrect-record reporting, account-closure requests, and administrator contact paths.
- Account closure unlinks authentication from the historical family person rather than deleting the verified person automatically.
- Define retention and deletion behavior for contact fields, user-created meetup content, operational telemetry, and audit records before real-user onboarding.
- Publish an understandable privacy notice before beta invitations.
- Obtain focused privacy/legal review for India/USA personal-data handling before expanding beyond the private beta.

## Explicitly Out of Scope

- Android client implementation.
- Public registration.
- Phone OTP or phone-ownership verification.
- Inviting a person who has no existing family-tree record.
- Per-field consent and connection-request contact sharing.
- Real-time chat, social feeds, payments, or public posts.
- Automated genealogy imports.
- Separate web administration portal.
- Multi-region database replicas.
- App Store production submission.
- Third-party product analytics.

These capabilities may be added later through the defined platform-neutral backend, policy records, repository interfaces, and separate invitation/claim model.

## Acceptance Criteria

The production foundation is ready for private beta when:

1. An uninvited email cannot create an approved account or read family data.
2. An admin or trusted elder can invite an existing unclaimed person by email.
3. The invitee can authenticate by email OTP, submit a claim, and remain isolated while pending.
4. A different authorized reviewer can approve the claim, after which the member sees only relatives within the configured third-cousin policy.
5. Changing the server policy changes the permitted relationship depth without an app release.
6. Contact fields are visible only to currently permitted relatives.
7. Direct and protected profile edits follow their respective immediate-update and review workflows.
8. Family graph, discovery, meetups, RSVP state, profiles, invitations, and reviews persist across devices and launches.
9. Role, invitation, claim, protected-edit, relationship, and policy actions produce audit events.
10. Sign-out and session revocation prevent access to cached sensitive content.
11. Automated tests prove row-level denial cases and graph-integrity constraints.
12. Codemagic produces an automatically versioned TestFlight build from the reviewed source.
13. India/USA locale, time-zone, Unicode-name, and latency smoke tests pass.
14. Production SMTP, backups, privacy notice, retention rules, and beta support contact are configured before invitations are sent.
