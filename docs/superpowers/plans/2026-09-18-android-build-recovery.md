# Android Build Recovery Implementation Plan

> **For agentic workers:** Execute this plan task-by-task in the current checkout while preserving unrelated dirty-worktree changes.

**Goal:** Make the SupaNotes Android release build run again on this machine without requiring Java 25 or a production keystore to be committed.

**Architecture:** Keep the project on the currently compatible Gradle/AGP/Kotlin line while pinning the local build to the JDK selected by Flutter. Keep release signing production-safe when a complete `key.properties` exists, while allowing a clearly marked local debug-keystore fallback so `assembleRelease` can produce an installable local APK.

**Tech Stack:** Flutter 3.47.2, Gradle, Android Gradle Plugin, Kotlin Gradle Plugin, Kotlin DSL, PowerShell.

**Spec:** User request on 2026-09-18 to resolve the Android build failure and build the app again.

## Global Constraints

- Preserve all unrelated existing Flutter and Windows changes in the dirty worktree.
- Never commit `android/key.properties`, keystores, or production credentials.
- A local fallback-signed APK must be reported as not suitable for Play Store upload.
- Do not add visual-behavior tests; verify only build/toolchain outcomes.

---

### Task 1: Align the Android toolchain

**Files:**
- Modify: `android/gradle/wrapper/gradle-wrapper.properties`
- Modify: `android/settings.gradle.kts`
- Review: `android/gradle.properties`

- [x] Keep the wrapper on Gradle 8.14, AGP on 8.12.1, and KGP on 2.2.20 because the current Cargokit dependency is not compatible with Gradle 9.
- [x] Keep the Flutter 3.47 built-in Kotlin/new DSL flags enabled on the compatible AGP line.
- [x] Verify the wrapper reports Gradle 8.14 on the JDK selected by Flutter.

### Task 2: Make release signing buildable locally

**Files:**
- Modify: `android/app/build.gradle.kts`
- Create locally, ignored: `android/key.properties` when the production key is unavailable

- [x] Load production signing values only when all four required properties exist.
- [x] Use the machine's standard debug keystore as a local fallback for `assembleRelease` when no complete production signing configuration exists.
- [x] Emit an explicit warning that the fallback APK is not publishable.
- [x] Keep the existing production signing path unchanged when `key.properties` is complete.

### Task 3: Verify the build

**Files:**
- No test files; build artifacts remain ignored/generated.

- [x] Verify Gradle version and JVM version.
- [x] Run `flutter build apk --release`.
- [x] Confirm the APK output exists and inspect the final diff so unrelated changes remain untouched.
