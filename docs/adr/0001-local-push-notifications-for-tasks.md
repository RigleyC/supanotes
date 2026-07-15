# 1. Local Push Notifications for Tasks

Date: 2026-07-15

## Status

Accepted

## Context

We need to notify users of tasks based on their due date and recurrence. SupaNotes is designed as an offline-first application where the `YDoc` is the source of truth and is stored locally before synchronizing. We needed to choose between a server-side push notification architecture (using Firebase Cloud Messaging) and a client-side local notification scheduling architecture.

## Decision

We will use **Local Push Notifications** scheduled directly on the device using a library like `flutter_local_notifications`, driven by a service that watches the local SQLite (`drift`) `tasks` table for changes. We will also remove the existing Firebase messaging dependencies (`firebase_core`, `firebase_messaging`) since they are no longer needed.

## Consequences

* **Pros:**
    * **True Offline Support:** If a user creates a task for tomorrow while offline, the device will still notify them.
    * **Simpler Backend:** The backend does not need a worker or cron job to calculate due dates, handle timezones per user, or manage FCM tokens.
    * **No Firebase Dependency:** Removes heavy external dependencies, reducing app size and build times.
* **Cons:**
    * **Multi-device Synchronization Lag:** If a user marks a task complete on their phone, their offline desktop might still show the notification until it comes online and syncs the YDoc.
    * **Device Constraints:** OS-level limits on the number of scheduled local notifications (e.g., iOS limits to 64 future notifications) mean the app must proactively reschedule upcoming notifications on startup and on database changes.
