# Android Build Recovery Walkthrough

## Result

`flutter build apk --release` completed successfully and generated:

`build/app/outputs/flutter-apk/app-release.apk` — 84,252,782 bytes.

## Changes

- Kept the currently compatible Gradle 8.14, AGP 8.12.1, and Kotlin 2.2.20 line because the current `irondash_engine_context` Cargokit is not compatible with Gradle 9.
- Configured Flutter to use JDK 21 instead of Android Studio's JDK 25.
- Added the Java native-access flag to Gradle JVM arguments.
- Normalized doubled Windows plugin paths before Flutter's Gradle plugin loader runs.
- Made release signing use production `key.properties` when complete and the local debug keystore otherwise.

The generated APK is installable locally but is not suitable for Play Store upload unless a complete production `android/key.properties` is supplied.

## Verification

- Gradle wrapper: 8.14.
- Gradle daemon JVM: Eclipse Temurin 21.0.12.1.
- `flutter pub get`: passed.
- `flutter build apk --release`: passed.
- `git diff --check`: passed.
