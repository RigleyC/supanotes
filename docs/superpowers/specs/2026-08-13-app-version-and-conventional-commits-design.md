# App Versioning and Conventional Commits Design

## Goal

Show the version of every Codemagic build in the app and make Conventional Commits the default commit policy for the repository.

## Decisions

- Use Semantic Versioning in the form `MAJOR.MINOR.PATCH+BUILD`.
- Use Git tags as the release-version source of truth, starting with `v1.0.0`.
- Calculate the version during each Codemagic build. Do not create automatic version-bump commits.
- Use the Codemagic build number as the Flutter build number.
- Show the version at the bottom of the Settings screen.
- Validate commit messages with a local `commit-msg` hook and again in CI.
- Keep the commit policy documented in `agents.md`.
- Do not add a Node-based commit tool when the existing Dart and Flutter toolchain can provide the validator.

## Version calculation

The build script fetches Git tags and reads commits after the latest version tag. The highest required increment wins:

- `BREAKING CHANGE` or a breaking `!` scope: increment MAJOR.
- `feat`: increment MINOR.
- `fix`: increment PATCH.
- `refactor`, `docs`, `test`, `chore`, and other non-release types: do not change SemVer.

If no version tag exists, use `v1.0.0` as the baseline. If no release commit exists after the tag, keep the tag version. The build number is always the current Codemagic build number, so every build remains identifiable even when its SemVer value does not change.

The calculated values are passed to Flutter with `--build-name` and `--build-number`. Signed and unsigned Codemagic workflows must use the same calculation. The generated platform metadata remains a build artifact; the repository `pubspec.yaml` is not rewritten by CI.

## Runtime display

Add the smallest existing Flutter package that reads the platform version embedded by the build. A settings row displays the public version and build number in the existing settings layout. The row is read-only and has no network or persistence dependency.

The display must use the value compiled into the running app. It must not derive a version from the current Git checkout at runtime.

## Commit validation

Add one repository-owned validator for the Conventional Commits grammar and reuse it in both places:

1. A `commit-msg` hook reads Git's temporary commit-message file. It exits successfully for valid messages and blocks invalid messages with a short example.
2. A CI step validates the commits in the change range. This protects the repository when a contributor has not installed local hooks.

The minimum accepted subject format is:

```text
type(optional-scope): description
```

Allowed types are `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `build`, `ci`, `perf`, `revert`, and `style`. Breaking changes use `!` or a `BREAKING CHANGE:` footer. Merge commits and the repository's existing merge strategy must not be rejected by the validator.

The repository must provide a documented setup command for installing or activating the hook. The hook must be usable on the Windows development environment and in Codemagic's macOS environment.

## Verification

- Unit-test the version parser with no tag, patch, minor, major, and mixed commit histories.
- Unit-test the commit validator with valid types, scopes, breaking changes, malformed subjects, and merge commits.
- Run the hook against representative commit-message files.
- Verify Codemagic receives the calculated `--build-name` and `--build-number` in every workflow.
- Verify the settings screen displays the exact runtime version in a release build.
- Run Flutter analysis and focused tests for the settings/version surface.
- Keep all pre-existing unrelated worktree changes out of the implementation commits.

## Non-goals

- No automatic release creation or tag pushing.
- No changelog screen.
- No version stored in the backend or synchronized between devices.
- No compatibility layer for older version formats.
