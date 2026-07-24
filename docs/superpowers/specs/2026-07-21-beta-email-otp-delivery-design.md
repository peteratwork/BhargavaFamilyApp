# Beta Email OTP Delivery Design

## Objective

Restore reliable six-digit email OTP delivery for invited iOS beta users without purchasing a domain or adding SMS costs. Preserve the existing invitation-only and account-enumeration protections.

## Scope

This design covers the small private beta only. Supabase Auth remains the identity system and a dedicated Gmail account provides SMTP delivery. A domain-authenticated transactional email provider remains a prerequisite for a broader production rollout.

## Authentication and invitation flow

1. An administrator or trusted elder creates the invited Supabase Auth identity before the person attempts to sign in.
2. The user enters the same email address in the app.
3. The iOS client calls Supabase email OTP with automatic user creation disabled.
4. Supabase sends a six-digit OTP only when the invited identity exists.
5. The public app response remains neutral for both invited and unknown addresses so membership cannot be enumerated.
6. The user verifies the code and proceeds to the existing-record claim flow and relationship-based authorization.

Unknown or mistyped addresses do not receive an email. The app must not claim unconditionally that a message was delivered; its wording should explain that invited users will receive a code while retaining a neutral security response.

## SMTP configuration

Supabase custom SMTP will use:

- Host: `smtp.gmail.com`
- Port: `587`
- Username and sender address: `bhargavafamilyapp@gmail.com`
- Sender name: `Bhargava Family App`
- Authentication secret: a Google-generated app password entered only in Supabase
- Transport: TLS through SMTP submission

The Google account must keep 2-Step Verification enabled. The app password must never be placed in source control, Codemagic variables, documentation, logs, screenshots, or chat. If it is exposed, it must be revoked and regenerated.

## Email template

The Supabase Magic Link template will be converted to a six-digit OTP message using `{{ .Token }}`. The message will identify the Bhargava Family App, state that the code expires, and advise recipients to ignore an unexpected request. It will not disclose invitation or family-record details.

## Rate limits and abuse controls

Supabase's OTP cooldown and rate limits remain enabled. The initial configuration should allow normal retries without enabling rapid repeated sends. Gmail's personal-account delivery limits are sufficient for the private beta but are not a production service-level commitment.

## Failure handling and observability

- The client continues returning a neutral response for unknown and invited emails.
- Supabase Auth logs are the operational source for rejected OTP requests and SMTP delivery failures.
- TestFlight validation covers one invited address, one unknown address, an incorrect/expired code, resend behavior, and successful session restoration.
- Administrators verify the exact invited email before diagnosing delivery.

## Production migration

Before expanding beyond the private beta, purchase a project domain and move SMTP delivery to a transactional provider such as Resend with SPF, DKIM, and DMARC configured. The application-facing OTP flow and repository interfaces should remain unchanged during that migration.

## Out of scope

- SMS or WhatsApp OTP
- Google or Apple social login
- Passkeys
- Automatic invitation administration
- A general notification-email system
