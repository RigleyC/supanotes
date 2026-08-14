# App Version and Conventional Commits Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Calculate a SemVer app version for every Codemagic build, display it in Settings, and enforce Conventional Commits locally and in CI.

**Architecture:** Keep version calculation in a repository-owned Dart CLI that reads Git tags and commit messages. Codemagic passes the CLI result to Flutter with `--build-name` and `--build-number`; the running app reads the embedded platform metadata through `package_info_plus`. Keep commit validation in a second Dart CLI reused by a Git `commit-msg` hook and GitHub Actions.

**Tech Stack:** Flutter/Dart, `package_info_plus`, Git tags, Codemagic YAML, GitHub Actions, Git hooks.

## Global Constraints

- Use `MAJOR.MINOR.PATCH+BUILD`.
- Use Git tags as the release-version source of truth, starting with `v1.0.0`.
- Calculate the version during every Codemagic build; never create automatic version-bump commits.
- Use the Codemagic `BUILD_NUMBER` as the Flutter build number.
- Display the version at the bottom of the existing Settings list.
- Validate commits with a local `commit-msg` hook and again in CI.
- Keep the commit policy in `agents.md`.
- Do not add a Node-based commit tool.
- Preserve all unrelated existing worktree changes, including the current Settings edits and tests.

---

### Task 1: Build and test the version calculator

**Files:**
- Create: `scripts/app_version.dart`
- Test: `test/scripts/app_version_test.dart`

**Interfaces:**
- Produces `AppVersion.parse(String)`, `AppVersion.bump(VersionBump)`, `AppVersion.toBuildName()`, and `VersionCalculator.fromCommitMessages({required AppVersion baseVersion, required Iterable<String> messages})`.
- `VersionBump` has `none`, `patch`, `minor`, and `major` values.
- The CLI accepts `--build-number <positive integer>` and prints shell assignments `APP_VERSION=<major.minor.patch>` and `APP_BUILD_NUMBER=<number>`.

- [ ] **Step 1: Write failing parser tests**

  Cover `1.0.0`, `1.2.3`, malformed versions, and each bump operation. Use `flutter test test/scripts/app_version_test.dart`.

- [ ] **Step 2: Write failing commit classification tests**

  Cover `fix(scope): ...` → PATCH, `feat(scope): ...` → MINOR, `feat!: ...` → MAJOR, a `BREAKING CHANGE:` footer → MAJOR, and `refactor`, `docs`, `test`, and `chore` → NONE. Confirm the highest bump wins.

- [ ] **Step 3: Implement the pure calculator**

  Parse only Conventional Commit subjects and footers. Use the latest tag value as the base; do not mutate `pubspec.yaml`.

- [ ] **Step 4: Run the focused tests**

  Run:

  ```text
  flutter test test/scripts/app_version_test.dart
  ```

  Expected: all parser and classification tests pass.

- [ ] **Step 5: Add the CLI Git integration**

  The CLI must run `git tag --list 'v[0-9]*' --sort=-version:refname` and `git log <tag>..HEAD --format=%B`. Use `v1.0.0` when no matching tag exists. Use the `BUILD_NUMBER` argument for `APP_BUILD_NUMBER`; reject a missing, non-numeric, or non-positive value.

- [ ] **Step 6: Test CLI output**

  Run:

  ```text
  dart run scripts/app_version.dart --build-number 248
  ```

  Expected output contains `APP_VERSION=` with a SemVer value and `APP_BUILD_NUMBER=248`.

- [ ] **Step 7: Commit the version calculator**

  ```text
  git add scripts/app_version.dart test/scripts/app_version_test.dart
  git commit -m "feat(build): calculate app version from commits"
  ```

### Task 2: Add runtime version display

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/features/settings/presentation/settings_screen.dart`
- Create: `lib/core/app_version/app_version_provider.dart`
- Test: `test/features/settings/presentation/settings_screen_test.dart`

**Interfaces:**
- `appPackageInfoProvider` is an auto-dispose `FutureProvider<PackageInfo>` that calls `PackageInfo.fromPlatform()`.
- Settings renders a read-only `AppTile` with title `Versão` and subtitle `<version>+<buildNumber>` after the existing account/MCP items and before logout.

- [ ] **Step 1: Add the dependency and provider test seam**

  Add `package_info_plus` to `pubspec.yaml`, run `flutter pub get`, and expose the provider so widget tests can override it with a deterministic `PackageInfo`.

- [ ] **Step 2: Write the failing Settings test**

  Override `appPackageInfoProvider` with version `1.3.0` and build number `248`. Assert one `AppTile` titled `Versão`, subtitle `1.3.0+248`, no tap callback, and placement before `Sair da conta`.

- [ ] **Step 3: Implement the provider and Settings row**

  Watch the provider with `AsyncValue.when`. Render the normal version row for data, a non-interactive loading row while metadata loads, and an explicit error row if platform metadata fails. Do not add a loading boolean or network dependency.

- [ ] **Step 4: Run focused Settings tests and analysis**

  ```text
  flutter test test/features/settings/presentation/settings_screen_test.dart
  flutter analyze --no-pub
  ```

- [ ] **Step 5: Commit the runtime display**

  ```text
  git add pubspec.yaml pubspec.lock lib/core/app_version/app_version_provider.dart lib/features/settings/presentation/settings_screen.dart test/features/settings/presentation/settings_screen_test.dart
  git commit -m "feat(settings): show app version"
  ```

### Task 3: Wire automatic versioning into Codemagic

**Files:**
- Modify: `codemagic.yaml`
- Modify: `scripts/app_version.dart`

**Interfaces:**
- Both `ios-unsigned` and `ios-signed` run the same version-resolution command before building:

  ```bash
  eval "$(dart run scripts/app_version.dart --build-number \"$BUILD_NUMBER\")"
  echo "Building SupaNotes $APP_VERSION+$APP_BUILD_NUMBER"
  ```

- Every Flutter build uses `--build-name="$APP_VERSION" --build-number="$APP_BUILD_NUMBER"`.

- [ ] **Step 1: Add version resolution after dependencies are installed**

  In both workflows, run `git fetch --tags --force` and then the CLI after `flutter pub get` so the Dart script can execute with the resolved package graph and see the version tags. Keep the existing API and signing setup unchanged.

- [ ] **Step 2: Pass version flags to the unsigned workflow**

  Add the flags to `flutter build ios --config-only`. This writes the calculated `FLUTTER_BUILD_NAME` and `FLUTTER_BUILD_NUMBER` values consumed by the later `xcodebuild` invocation.

- [ ] **Step 3: Pass version flags to the signed workflow**

  Add the flags to `flutter build ipa --release` before the existing export-options argument.

- [ ] **Step 4: Validate the YAML and shell behavior locally**

  Run the CLI with a fixed build number and inspect the generated assignments. Use a temporary Git tag/commit fixture only in a temporary repository; do not create tags in SupaNotes. Confirm the two Codemagic workflows contain the same version flags.

- [ ] **Step 5: Commit Codemagic wiring**

  ```text
  git add codemagic.yaml scripts/app_version.dart
  git commit -m "ci(codemagic): inject calculated app version"
  ```

### Task 4: Add Conventional Commit validation and hook setup

**Files:**
- Create: `scripts/commit_message_validator.dart`
- Create: `.githooks/commit-msg`
- Test: `test/scripts/commit_message_validator_test.dart`
- Modify: `agents.md`

**Interfaces:**
- `CommitMessageValidator.validate(String)` returns a structured result with `isValid` and a user-facing error message.
- The CLI command is `dart run scripts/commit_message_validator.dart <commit-message-file>`.
- The hook invokes the same CLI and exits with status 1 for invalid messages.

- [ ] **Step 1: Write failing validator tests**

  Accept `feat(editor): add task block`, `fix: preserve selection`, `revert: ...`, and breaking `feat!: ...`. Reject missing type, missing colon, empty description, and unknown type. Ignore merge commits whose first line starts with `Merge `.

- [ ] **Step 2: Implement the validator**

  Allow exactly `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `build`, `ci`, `perf`, `revert`, and `style`. Ignore comment lines when reading the message file. Require a non-empty description after `: `.

- [ ] **Step 3: Add the portable hook**

  `.githooks/commit-msg` must use the repository root from `git rev-parse --show-toplevel`, invoke `dart run scripts/commit_message_validator.dart "$1"`, and preserve the validator exit code.

- [ ] **Step 4: Document activation and policy**

  Add to `agents.md`:

  ```text
  git config core.hooksPath .githooks
  ```

  Document the accepted types, breaking-change syntax, and valid examples. State that CI remains authoritative when the hook is not installed.

- [ ] **Step 5: Run hook tests**

  ```text
  flutter test test/scripts/commit_message_validator_test.dart
  git config core.hooksPath .githooks
  git commit --allow-empty -m "invalid message"
  ```

  Expected: the test passes and the invalid commit is rejected. Reset only the temporary empty-commit attempt; do not reset or discard existing worktree changes.

- [ ] **Step 6: Commit hook and documentation**

  ```text
  git add scripts/commit_message_validator.dart .githooks/commit-msg test/scripts/commit_message_validator_test.dart agents.md
  git commit -m "ci(commits): enforce conventional commit messages"
  ```

### Task 5: Enforce the same rule in GitHub Actions and verify end to end

**Files:**
- Create: `.github/workflows/conventional-commits.yml`

**Interfaces:**
- The workflow runs on pull requests and pushes to `master`.
- It checks the commit range with the repository validator and fails on the first invalid commit.

- [ ] **Step 1: Add the CI workflow**

  Check out full history, install Flutter `3.44.1`, run `flutter pub get`, determine the push/PR commit range, and invoke the validator for each commit message. Use the same Dart validator as the hook; do not duplicate its grammar in YAML.

- [ ] **Step 2: Test the workflow's range logic locally**

  Run the validator against the current branch's recent commits and confirm existing merge commits are accepted while malformed subjects are rejected in a temporary fixture.

- [ ] **Step 3: Document first-time setup**

  Keep the one-line `git config core.hooksPath .githooks` command in `agents.md` with the policy documentation; do not add a second source of truth.

- [ ] **Step 4: Run final verification**

  ```text
  flutter analyze --no-pub
  flutter test
  git diff --check
  git status --short
  ```

  Confirm only the intended files are staged in each implementation commit and all pre-existing unrelated changes remain untouched.

- [ ] **Step 5: Commit CI enforcement**

  ```text
  git add .github/workflows/conventional-commits.yml
  git commit -m "ci(commits): validate commit history in GitHub Actions"
  ```

## Final acceptance checklist

- A Codemagic build after `v1.0.0` with `feat` and `fix` commits displays the calculated SemVer plus its build number.
- A build containing only `refactor`, `docs`, `test`, or `chore` keeps the SemVer base and still receives a new build number.
- The version row appears at the bottom of Settings before logout and is read-only.
- A valid Conventional Commit succeeds locally and in CI.
- An invalid Conventional Commit is rejected locally when hooks are activated and rejected by CI.
- No automatic version-bump commit, release tag, backend value, migration, or compatibility path is added.
