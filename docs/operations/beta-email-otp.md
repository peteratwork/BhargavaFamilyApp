# Private-beta email OTP operations

## Boundary

The private beta uses the dedicated `bhargavafamilyapp@gmail.com` account as a temporary SMTP sender. Do not use this configuration for a broad production rollout. Never record the Google app password in this repository, Codemagic, terminal history, screenshots, logs, or chat.

## Supabase custom SMTP

Under **Authentication → Email → SMTP Settings**, enable custom SMTP and enter:

| Field | Value |
|---|---|
| Sender email | `bhargavafamilyapp@gmail.com` |
| Sender name | `Bhargava Family App` |
| Host | `smtp.gmail.com` |
| Port | `587` |
| Username | `bhargavafamilyapp@gmail.com` |
| Password | Enter the Google app password directly from the operator's private copy |

Save once. Do not reveal the password by inspecting, copying, logging, or taking a screenshot after entry. Keep Google 2-Step Verification enabled. If the app password is exposed, revoke it in Google Account Security, generate a replacement, and update Supabase immediately.

## OTP controls

Under **Authentication → Sign In / Providers → Email**, keep public sign-up disabled and set:

- OTP expiry: `3600` seconds
- Minimum resend interval: `60` seconds

Under **Authentication → Rate Limits**, start with `30` email sends per hour. Do not enable CAPTCHA until the iOS client sends a supported CAPTCHA token.

## Magic Link template used for email OTP

Under **Authentication → Email → Templates → Magic Link**, set the subject to:

`Your Bhargava Family App sign-in code`

Set the body to:

```html
<h2>Your Bhargava Family App sign-in code</h2>
<p>Enter this six-digit code in the app:</p>
<p style="font-size: 28px; font-weight: 700; letter-spacing: 6px;">{{ .Token }}</p>
<p>This code expires in one hour.</p>
<p>If you did not request this code, you can ignore this email.</p>
```

Do not replace the separate Invite template's `{{ .ConfirmationURL }}` value.

## Smoke test

1. Verify the intended email already exists under **Authentication → Users**; an arbitrary address must not be auto-created.
2. In the latest TestFlight build, request a code for that exact invited address.
3. Confirm one email arrives, the sender and subject are correct, and the body contains a six-digit token rather than a link.
4. Enter an incorrect code and confirm the app stays on code entry with a neutral invalid-or-expired message.
5. Enter the current code and confirm authentication advances to the account's permitted state.
6. Sign out, request again, confirm the 60-second resend lock, and redeem the new code.
7. Request a code for an unknown synthetic address. Confirm the app shows the same neutral next screen, no Auth user is created, and no email is delivered.
8. Review Supabase Auth logs for the test interval. Record only timestamp, broad region, outcome, and sanitized error class—never email addresses or tokens.

## Rollback and migration

If SMTP delivery fails repeatedly, stop beta invitations, disable custom SMTP, revoke the Gmail app password if compromise is possible, and retain sanitized Auth-log evidence. Do not relax invitation-only account creation to work around delivery.

Before expanding beyond the private beta, purchase a project domain and migrate to a transactional provider with SPF, DKIM, and DMARC. Keep the client OTP repository interface and `shouldCreateUser: false` behavior unchanged.
