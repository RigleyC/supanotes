# Plan 062: Implement Local Push Notifications for Tasks

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report — do not improvise. When done, update the status row for this plan in `plans/README.md` — unless a reviewer dispatched you and told you they maintain the index.
>
> **Drift check (run first)**: `git diff --stat a2a0ead..HEAD -- pubspec.yaml lib/main.dart lib/features/notes/presentation/note_editor_screen.dart`
> If any in-scope file changed since this plan was written, compare the "Current state" excerpts against the live code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
- **Category**: direction
- **Planned at**: commit `a2a0ead`, 2026-07-15

## Why this matters

We are pivoting from server-side FCM push notifications to client-side local push notifications for task due dates. This ensures true offline support—users will be notified of tasks even if their device hasn't synced with the server. Dropping Firebase also reduces the app's footprint and simplifies the backend.

## Current state

- `pubspec.yaml` contains `firebase_core` and `firebase_messaging`.
- `lib/main.dart` initializes Firebase:
```dart
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
```
- The editor UI doesn't pipe the `onRecurringTaskComplete` callback to the `NoteEditorController`. `NoteEditorDelegate` instantiation in `lib/features/notes/presentation/note_editor_screen.dart` (lines 193-237) lacks the `onRecurringTaskComplete` argument.
- `lib/features/notes/presentation/controllers/note_editor_controller.dart` has `completeRecurringTask(String nodeId, DateTime nextDue)` which we will call.

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Check     | `flutter pub get`        | exit 0              |
| Typecheck | `flutter analyze`        | exit 0, no errors   |

## Scope

**In scope**:
- `pubspec.yaml`
- `lib/main.dart`
- `firebase_options.dart` (DELETE)
- `lib/core/notifications/fcm_message_listeners.dart` (DELETE)
- `lib/core/notifications/local_notification_service.dart` (NEW)
- `lib/features/tasks/domain/task_notification_scheduler.dart` (NEW)
- `lib/features/notes/presentation/note_editor_screen.dart`
- `android/app/build.gradle`, `android/build.gradle`, `ios/Podfile` (remove Firebase)

## Git workflow

- Branch: `advisor/062-local-task-notifications`
- Commit per step; message style: `feat(notifications): add local task scheduler`

## Steps

### Step 1: Clean up Firebase dependencies

1. Remove `firebase_core` and `firebase_messaging` from `pubspec.yaml`.
2. Delete `lib/firebase_options.dart` and `lib/core/notifications/fcm_message_listeners.dart`.
3. In `lib/main.dart`, remove all Firebase imports, `_firebaseMessagingBackgroundHandler`, `Firebase.initializeApp`, and `_setupFcmListeners` logic.
4. Remove the `com.google.gms.google-services` plugin from `android/app/build.gradle`.
5. Remove the Firebase pod from `ios/Podfile` if it's there.

**Verify**: `flutter analyze` exits 0 (after you remove the Firebase imports).

### Step 2: Add flutter_local_notifications

1. Run `flutter pub add flutter_local_notifications timezone`.
2. Create `lib/core/notifications/local_notification_service.dart`. It should initialize `FlutterLocalNotificationsPlugin`, configure Android/iOS init settings, and expose a method `scheduleTaskNotification(String id, String title, DateTime scheduledDate)`.
   *Note: Use timezone `tz.local` and `tz.TZDateTime.from(scheduledDate, tz.local)` for scheduling.*
3. Create `lib/features/tasks/domain/task_notification_scheduler.dart` as an `@Riverpod(keepAlive: true)` class. It should `ref.listen` to `tasksLocalRepositoryProvider`'s `watchOpenTasks()`, filtering for tasks with `dueDate != null`. For each task, calculate the notification time:
   - If `hasTime` is true, schedule exactly at `dueDate`.
   - If `hasTime` is false, schedule at 09:00 AM on the day of the `dueDate`.
   - Only schedule if the calculated time is > `DateTime.now()`.
   Call `scheduleTaskNotification` on the service for these tasks. Maintain a set of currently scheduled IDs so you know which ones to cancel when a task is completed/deleted.

**Verify**: `flutter analyze` exits 0.

### Step 3: Wire Recurring Tasks to the Controller

1. In `lib/features/notes/presentation/note_editor_screen.dart`, locate where `NoteEditorDelegate` is constructed.
2. Add the `onRecurringTaskComplete` argument:
```dart
                onRecurringTaskComplete: (taskId, nextDue) {
                  ref.read(noteEditorControllerProvider(widget.noteId))
                      .completeRecurringTask(taskId, nextDue);
                },
```
This correctly delegates the UI recurrence logic back to the YDoc bridge, keeping the document clean.

**Verify**: `flutter analyze` exits 0.

### Step 4: Initialize Notifications in main

1. In `lib/main.dart`, before `runApp`, ensure timezone data is initialized (`tz.initializeTimeZones()`).
2. Inside `SupaNotesApp.build`, add a `ref.listen` or just read the `taskNotificationSchedulerProvider` so that it stays alive and observes the tasks stream:
```dart
    ref.read(taskNotificationSchedulerProvider);
```

**Verify**: `flutter build apk` succeeds (to ensure Android gradle builds without Firebase).

## Test plan

- Create a manual smoke test: open the app, create a task due in 2 minutes, and put the app in the background. Ensure the notification arrives.
- Verification: `flutter analyze` and `flutter test` pass.

## Done criteria

- [ ] `flutter analyze` exits 0
- [ ] Firebase is fully removed from `pubspec.yaml` and platform config files.
- [ ] `NoteEditorDelegate` maps `onRecurringTaskComplete` to the controller.
- [ ] `plans/README.md` status row updated

## STOP conditions

- The code at the locations in "Current state" doesn't match the excerpts.
- You encounter issues initializing timezones or `flutter_local_notifications` that require a major architecture shift.
- The `flutter build apk` fails due to lingering Firebase cache. (Try `flutter clean` first, but stop if it persists).
