# Automatic TestFlight Releases After Main Merges

## Goal

Publish one signed iOS build to TestFlight after an approved pull request is merged into `main`, without releasing pull-request commits, feature branches, or direct local experiments.

## Chosen approach

Use Codemagic's native GitHub webhook and a `push` trigger scoped to `main`. GitHub must protect `main` with a rule requiring pull requests, so a normal push event on `main` represents an approved merge. This avoids a separate GitHub Actions dispatcher and an additional Codemagic API token.

Codemagic cannot distinguish a pull-request merge from an unrestricted direct push using its `push` event alone. The GitHub rule and Codemagic trigger therefore form one release control and must be maintained together.

## Codemagic configuration

Add the following trigger only to the `ios-release-archive` workflow:

```yaml
triggering:
  events:
    - push
  branch_patterns:
    - pattern: main
      include: true
      source: true
  cancel_previous_builds: true
```

The simulator workflow remains manually runnable. Pull-request validation remains in GitHub Actions. The release workflow continues to:

1. import the protected `supabase_production` variable group;
2. validate the client-safe Supabase configuration;
3. require the GitHub `Backend Tests` workflow to have passed for the exact commit;
4. run Swift package tests;
5. create a uniquely numbered, signed IPA; and
6. upload it to TestFlight without submitting it to App Store review.

`cancel_previous_builds: true` cancels an older webhook-triggered release when a newer `main` commit arrives before it finishes. Manual builds remain available for recovery and do not change the trigger policy.

## GitHub main-branch policy

Configure a branch rule or ruleset targeting `main` with:

- require a pull request before merging;
- require `Backend Tests` and `iOS Build` to pass;
- require conversations to be resolved;
- block force pushes and branch deletion; and
- do not allow bypassing the pull-request requirement during normal development.

The repository owner retains account-recovery authority, but routine releases must not use a direct push bypass. If an emergency bypass is ever required, its resulting `main` push will release automatically and must be treated as a production deployment.

## Webhook and data flow

The Codemagic application must have an active GitHub webhook. On merge:

1. GitHub updates `main` and sends a push event.
2. Codemagic reads `codemagic.yaml` from the resulting `main` commit.
3. Only `ios-release-archive` matches the event and branch.
4. The release workflow validates, tests, signs, and uploads.
5. Apple processes the build in App Store Connect.
6. Operators deliberately assign the processed build to TestFlight tester groups.

No workflow submits the build for public App Store review.

## Apple export-compliance prerequisite

The first production-configured archive uploaded and processed successfully, but App Store Connect rejected its automatic TestFlight beta-review submission because the build did not declare export compliance.

Before enabling unattended releases, review the app and every linked library against Apple's export-compliance questionnaire. If the app uses no encryption or only exempt encryption, declare `ITSAppUsesNonExemptEncryption` as `NO` in the generated iOS Info.plist configuration. If any dependency uses non-exempt encryption, complete Apple's required documentation instead and add the issued `ITSEncryptionExportComplianceCode`. The implementation must not claim an exemption without completing this review.

## Failure behavior

- Failed GitHub checks prevent the pull request from merging.
- Missing or invalid Supabase variables stop the release before compilation.
- Failed tests, signing, or archiving prevent upload.
- Missing export-compliance metadata can allow upload and processing but block TestFlight beta-review submission.
- Publishing failures remain visible in the Codemagic build log and require a manual rerun after the cause is corrected.
- A failed release does not roll back the merged source. The prior TestFlight build remains available while a reviewed forward fix is prepared.

## Verification

Before enabling the automatic trigger, validate the YAML, confirm both protected Codemagic variables exist, complete the export-compliance determination, and confirm or update the GitHub webhook in Codemagic.

Use a small pull request to verify:

1. no release archive starts while the pull request is open;
2. required GitHub checks pass;
3. direct push to `main` is rejected for the normal development path;
4. merging the pull request starts exactly one `ios-release-archive` build;
5. the build uses the merge commit and passes release configuration validation; and
6. the resulting IPA clears export compliance and appears in TestFlight after Apple processing.

## Rollback

If automatic releases are noisy or unsafe, remove the `triggering` block in a reviewed pull request or temporarily disable the Codemagic webhook. Keep manual `ios-release-archive` execution available. Do not weaken the GitHub `main` protection merely to stop releases.
