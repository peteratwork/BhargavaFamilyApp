# Automatic TestFlight Releases Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically build and upload one signed iOS archive after an approved pull request is merged into `main`, with export-compliance metadata and protected release inputs in place.

**Architecture:** GitHub protects `main` and remains the pull-request validation surface. A Codemagic webhook observes the resulting push to `main`; only `ios-release-archive` matches it, waits for the exact backend CI commit, builds the signed IPA, and submits it to TestFlight. The iOS bundle explicitly records the reviewed exempt-encryption determination so App Store Connect can process unattended beta submissions.

**Tech Stack:** Codemagic YAML, GitHub Actions and branch rules, Xcode project with an explicit Info.plist, Python `unittest`, App Store Connect/TestFlight.

## Global Constraints

- Automatic release archives run only for `push` events on `main`.
- Normal changes reach `main` through pull requests with `Backend Tests` and `iOS Build` passing.
- `ios-simulator-build` remains manually runnable and does not publish.
- `cancel_previous_builds` is enabled for webhook-triggered release archives.
- Codemagic imports only the protected `supabase_production` client configuration; no service-role or `sb_secret_...` key enters the app.
- TestFlight upload stays enabled and public App Store submission stays disabled.
- Export-compliance metadata may declare `NO` only while the app and linked iOS libraries use no encryption or exempt encryption; re-audit when cryptography dependencies or usage change.
- Operators continue assigning processed builds to tester groups deliberately.

## File Structure

- Create `scripts/tests/test_release_configuration.py` to lock down export-compliance metadata and Codemagic trigger scope without adding third-party test dependencies.
- Modify `BhargavaFamilyApp/Info.plist` to declare the reviewed exempt-encryption status in the shipped bundle.
- Modify `codemagic.yaml` to trigger only `ios-release-archive` for pushes to `main` and cancel obsolete webhook builds.
- Modify `docs/operations/supabase-environments.md` to record the technical export-compliance basis, GitHub protection, webhook setup, and release verification procedure.

---

### Task 1: Declare and test iOS export compliance

**Files:**
- Create: `scripts/tests/test_release_configuration.py`
- Modify: `BhargavaFamilyApp/Info.plist`
- Modify: `docs/operations/supabase-environments.md`

**Interfaces:**
- Consumes: the explicit plist at `BhargavaFamilyApp/Info.plist` and the pinned iOS dependencies in `BhargavaFamilyApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
- Produces: Boolean plist key `ITSAppUsesNonExemptEncryption = false` and an executable regression test used by the existing `Backend Tests` workflow.

- [ ] **Step 1: Write the failing plist test**

Create `scripts/tests/test_release_configuration.py`:

```python
import pathlib
import plistlib
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).parents[2]


class ReleaseConfigurationTests(unittest.TestCase):
    def test_ios_bundle_declares_only_exempt_encryption(self):
        with (REPOSITORY_ROOT / "BhargavaFamilyApp" / "Info.plist").open("rb") as plist_file:
            info = plistlib.load(plist_file)

        self.assertIs(info.get("ITSAppUsesNonExemptEncryption"), False)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```powershell
python -m unittest scripts.tests.test_release_configuration.ReleaseConfigurationTests.test_ios_bundle_declares_only_exempt_encryption -v
```

Expected: `FAIL` because `ITSAppUsesNonExemptEncryption` is absent and `info.get(...)` returns `None`.

- [ ] **Step 3: Confirm the technical basis for the exempt declaration**

Run:

```powershell
rg -n "import (Crypto|CryptoKit|Security)|CryptoExtras|CCCrypto|SecKey|CommonCrypto|encrypt|decrypt|cipher" BhargavaFamilyApp Packages BhargavaFamilyApp.xcodeproj -g '*.swift' -g '*.pbxproj' -g 'Package.resolved'
```

Expected: no application crypto imports, `CryptoExtras` product, or custom encryption implementation. Review `Package.resolved` and confirm that the iOS dependency is `swift-crypto` through Supabase; Apple's Swift Crypto documentation states that on Apple platforms it re-exports and delegates to the operating-system CryptoKit implementation. Supabase network calls use the platform URL loading stack. If this evidence changes, stop and complete Apple's export-compliance questionnaire instead of adding the `false` value.

- [ ] **Step 4: Add the exempt-encryption declaration to the shipped plist**

Insert after `LSRequiresIPhoneOS` in `BhargavaFamilyApp/Info.plist`:

```xml
	<key>ITSAppUsesNonExemptEncryption</key>
	<false/>
```

- [ ] **Step 5: Document the determination and re-audit rule**

Add this section after `## Release workflow` in `docs/operations/supabase-environments.md`:

```markdown
## Apple export compliance

The iOS app declares `ITSAppUsesNonExemptEncryption` as `NO`. At the 2026-07-20 review, application sources contained no custom cryptography, Supabase networking used the Apple URL loading stack, and the pinned `swift-crypto` dependency delegated to CryptoKit on Apple platforms rather than bundling its non-Apple BoringSSL implementation. This supports the exempt-encryption answer for the current iOS binary; the repository record is technical evidence, not legal advice.

Repeat the App Store Connect export-compliance determination before release if app code begins importing cryptography APIs, a package adds `CryptoExtras` or another bundled implementation, distribution countries change, or Apple changes its questionnaire. If Apple requires documentation, set `ITSAppUsesNonExemptEncryption` to `YES` and add the approved `ITSEncryptionExportComplianceCode`; never leave an inaccurate `NO` declaration merely to keep automation green.
```

- [ ] **Step 6: Run the focused and full Python guardrail tests**

Run:

```powershell
python -m unittest scripts.tests.test_release_configuration -v
python -m unittest discover -s scripts/tests -v
```

Expected: the focused test passes and the full suite reports all tests `OK`.

- [ ] **Step 7: Commit the export-compliance guardrail**

```powershell
git add -- BhargavaFamilyApp/Info.plist scripts/tests/test_release_configuration.py docs/operations/supabase-environments.md
git commit -m "fix: declare exempt iOS encryption usage"
```

### Task 2: Trigger only release archives after main updates

**Files:**
- Modify: `scripts/tests/test_release_configuration.py`
- Modify: `codemagic.yaml`
- Modify: `docs/operations/supabase-environments.md`

**Interfaces:**
- Consumes: Codemagic workflow IDs `ios-simulator-build` and `ios-release-archive`.
- Produces: a `push` trigger restricted to `main` on `ios-release-archive`, with `cancel_previous_builds: true`; no automatic simulator trigger.

- [ ] **Step 1: Add failing tests for trigger scope**

Add below `REPOSITORY_ROOT` in `scripts/tests/test_release_configuration.py`:

```python
CODEMAGIC_YAML = REPOSITORY_ROOT / "codemagic.yaml"


def workflow_block(workflow_id):
    lines = CODEMAGIC_YAML.read_text(encoding="utf-8").splitlines()
    start = lines.index(f"  {workflow_id}:")
    end = next(
        (
            index
            for index in range(start + 1, len(lines))
            if lines[index].startswith("  ")
            and not lines[index].startswith("    ")
            and lines[index].endswith(":")
        ),
        len(lines),
    )
    return "\n".join(lines[start:end])
```

Add these methods to `ReleaseConfigurationTests`:

```python
    def test_release_archive_runs_only_for_pushes_to_main(self):
        release = workflow_block("ios-release-archive")
        expected_trigger = """    triggering:
      events:
        - push
      branch_patterns:
        - pattern: main
          include: true
          source: true
      cancel_previous_builds: true"""

        self.assertIn(expected_trigger, release)

    def test_simulator_workflow_does_not_publish_automatically(self):
        simulator = workflow_block("ios-simulator-build")

        self.assertNotIn("    triggering:", simulator)
        self.assertNotIn("    publishing:", simulator)
```

- [ ] **Step 2: Run the focused trigger tests and verify they fail**

Run:

```powershell
python -m unittest scripts.tests.test_release_configuration.ReleaseConfigurationTests.test_release_archive_runs_only_for_pushes_to_main scripts.tests.test_release_configuration.ReleaseConfigurationTests.test_simulator_workflow_does_not_publish_automatically -v
```

Expected: the release-trigger test fails because the `triggering` block is absent; the simulator safety test passes.

- [ ] **Step 3: Add the Codemagic release trigger**

Insert after `max_build_duration: 60` inside `ios-release-archive` in `codemagic.yaml`:

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

Do not add a `triggering` or `publishing` section to `ios-simulator-build`.

- [ ] **Step 4: Document GitHub and webhook prerequisites**

Add this section after the release-workflow numbered list in `docs/operations/supabase-environments.md`:

```markdown
### Automatic post-merge releases

`ios-release-archive` watches only push events on `main`. GitHub must require pull requests for `main`; otherwise a direct push is also a production release. Require the check contexts `Backend Tests / Supabase database and functions` and `iOS Build / Build for iOS Simulator`, require resolved conversations, and block force pushes and branch deletion. Do not use an administrator bypass during normal development.

In Codemagic, keep the GitHub webhook active under **BhargavaFamilyApp → Webhooks**. If deliveries are missing, use **Update webhook**, then inspect **Recent deliveries** before retrying a merge. Rapid successive merges cancel older webhook-triggered archives so only the newest `main` commit continues.
```

- [ ] **Step 5: Run all release guardrails**

Run:

```powershell
python -m unittest scripts.tests.test_release_configuration -v
python -m unittest discover -s scripts/tests -v
git diff --check
```

Expected: all tests pass, `git diff --check` emits no output, and the release workflow test confirms the exact `main` trigger.

- [ ] **Step 6: Run the application and backend tests available on Windows**

Run:

```powershell
swift test --package-path Packages/BhargavaCore
npm ci
npm run functions:test
```

Expected: Swift package tests pass, npm reports no install failure, and all Deno Edge Function tests pass.

- [ ] **Step 7: Commit the automatic trigger**

```powershell
git add -- codemagic.yaml scripts/tests/test_release_configuration.py docs/operations/supabase-environments.md
git commit -m "ci: release iOS builds after main merges"
```

### Task 3: Enforce the merge boundary and verify end to end

**Files:**
- No repository files should change during this operational task.

**Interfaces:**
- Consumes: the committed `ios-release-archive` trigger, GitHub checks, Codemagic GitHub integration, `supabase_production`, App Store Connect integration, and iOS signing assets.
- Produces: protected `main`, an active Codemagic webhook, one automatic release for the merged commit, and a processed TestFlight build that is not submitted to the public App Store.

- [ ] **Step 1: Push the implementation branch and open a pull request**

Run:

```powershell
git status --short --branch
git push -u origin codex/automatic-testflight-releases
```

Expected: the working tree is clean and GitHub receives the branch. Open a pull request targeting `main` titled `Automate TestFlight releases after main merges`, summarizing the trigger boundary, export-compliance declaration, and rollback.

- [ ] **Step 2: Configure the GitHub `main` rule before merging**

In **GitHub → peteratwork/BhargavaFamilyApp → Settings → Rules → Rulesets** (or **Branches** if rulesets are unavailable), create an active rule targeting `main` with:

```text
Require a pull request before merging: enabled
Required approvals: 0
Require status checks to pass: enabled
  Backend Tests / Supabase database and functions
  iOS Build / Build for iOS Simulator
Require conversation resolution: enabled
Block force pushes: enabled
Block branch deletion: enabled
Bypass during normal development: none
```

Expected: the rule is active and GitHub shows both checks as required on the pull request. Zero approvals preserves the single-owner workflow while still enforcing the pull-request boundary and automated checks.

- [ ] **Step 3: Confirm the Codemagic webhook**

Open **Codemagic → BhargavaFamilyApp → Webhooks**. Confirm the GitHub webhook is active; click **Update webhook** if Codemagic reports it missing or outdated. Inspect **Recent deliveries** and confirm GitHub events are arriving without authentication errors.

Expected: webhook status is active and no repository URL or permission error is shown.

- [ ] **Step 4: Wait for required pull-request checks**

Verify the pull request reports:

```text
Backend Tests / Supabase database and functions: success
iOS Build / Build for iOS Simulator: success
```

Expected: both required checks pass at the pull request head commit. Do not merge on a failed or pending check.

- [ ] **Step 5: Merge the pull request through GitHub**

Use **Squash and merge** or the repository's established merge method. Do not push the commits directly to `main`.

Expected: GitHub updates `main`, closes the pull request, and emits one push webhook for the resulting commit.

- [ ] **Step 6: Verify exactly one automatic Codemagic release**

Open **Codemagic → BhargavaFamilyApp → Builds** and locate the build whose commit equals the new `main` HEAD.

Expected:

```text
Workflow: iOS release archive
Branch: main
Trigger: webhook/push
SUPABASE_URL: HIDDEN
SUPABASE_PUBLISHABLE_KEY: HIDDEN
Validate release configuration: passed
Verify backend CI for this commit: passed
Test app core: passed
Build signed IPA for distribution: passed
```

Confirm that no `iOS simulator build` was started by the same webhook.

- [ ] **Step 7: Verify App Store Connect and TestFlight completion**

In the Codemagic publishing log, confirm the uploaded build is found and App Store Connect finishes processing it without `Build is missing export compliance`. Then open **App Store Connect → Bhargava Family Connect → TestFlight → iOS**.

Expected: the build appears with export compliance cleared and is eligible for internal testing or TestFlight beta review. `submit_to_app_store: false` remains in effect, so no public App Store review submission exists.

- [ ] **Step 8: Assign testers deliberately and record rollback readiness**

Add the processed build to the intended internal or external TestFlight group only after the release smoke test. Keep the previous TestFlight build available. If automatic triggering is incorrect, open a corrective pull request that removes the `triggering` block; do not weaken the GitHub `main` rule.

Expected: approved testers can install the new build, the previous build remains recoverable, and the GitHub/Codemagic controls remain enabled.
