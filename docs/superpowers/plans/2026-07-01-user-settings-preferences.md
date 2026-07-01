# User Settings UI Preferences Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the notes list/grid toggle from local UI state to a global `preferences` JSONB column in the `user_settings` table.

**Architecture:** We will add a JSONB `preferences` column to `user_settings`, expose it through the `/api/v1/settings` endpoint, parse it into the `UserSettings` Dart model, and read/update it directly from `notes_list_screen.dart`.

**Tech Stack:** Go (SQLC, Echo), PostgreSQL (JSONB), Flutter (Riverpod).

---

### Task 1: Database Migration & Queries

**Files:**
- Create: `backend/db/migrations/000026_user_settings_preferences.up.sql`
- Create: `backend/db/migrations/000026_user_settings_preferences.down.sql`
- Modify: `backend/db/queries/auth.sql`

- [ ] **Step 1: Write UP migration**

Create `backend/db/migrations/000026_user_settings_preferences.up.sql`:
```sql
BEGIN;
ALTER TABLE user_settings ADD COLUMN preferences JSONB NOT NULL DEFAULT '{}'::jsonb;
COMMIT;
```

- [ ] **Step 2: Write DOWN migration**

Create `backend/db/migrations/000026_user_settings_preferences.down.sql`:
```sql
BEGIN;
ALTER TABLE user_settings DROP COLUMN IF EXISTS preferences;
COMMIT;
```

- [ ] **Step 3: Update SQL queries**

In `backend/db/queries/auth.sql`, modify `UpdateUserSettings`:
```sql
-- name: UpdateUserSettings :one
UPDATE user_settings
SET
    timezone = COALESCE(NULLIF(@timezone::text, ''), timezone),
    preferences = COALESCE(sqlc.narg('preferences')::jsonb, preferences),
    updated_at = NOW()
WHERE user_id = @user_id
RETURNING *;
```
*(Make sure to use `sqlc.narg` for preferences so we can optionally update it if needed, or we can just require it. Let's just use `@preferences::jsonb` to be safe if we want to overwrite it fully every time, but `sqlc.narg` is safer for partial updates in Go. Actually, let's just make it required or `sqlc.narg('preferences')`.)*

Wait, let's look at `backend/db/queries/auth.sql` how it's currently written. Let's just update `UpdateUserSettings` to:
```sql
-- name: UpdateUserSettings :one
UPDATE user_settings
SET
    timezone = COALESCE(NULLIF(@timezone::text, ''), timezone),
    preferences = COALESCE(sqlc.narg('preferences')::jsonb, preferences),
    updated_at = NOW()
WHERE user_id = @user_id
RETURNING *;
```

- [ ] **Step 4: Generate SQLC models**

Run: `cd backend && make sqlc`
Expected: Succeeds and updates `backend/internal/db/sqlcgen/models.go` and `auth.sql.go`.

- [ ] **Step 5: Commit**

```bash
git add backend/db/migrations/ backend/db/queries/ backend/internal/db/sqlcgen/
git commit -m "db: add preferences jsonb column to user_settings"
```

### Task 2: Backend API (Settings)

**Files:**
- Modify: `backend/internal/dto/settings.go`
- Modify: `backend/internal/mapper/from_sqlc.go`
- Modify: `backend/internal/settings/handler.go`
- Modify: `backend/internal/settings/service.go`

- [ ] **Step 1: Update DTO**

In `backend/internal/dto/settings.go`:
```go
package dto

type SettingsResponse struct {
	Timezone    string         `json:"timezone"`
	Preferences map[string]any `json:"preferences"`
	CreatedAt   string         `json:"created_at"`
	UpdatedAt   string         `json:"updated_at"`
}
```

- [ ] **Step 2: Update Mapper**

In `backend/internal/mapper/from_sqlc.go`, modify `SettingsFromSQLC`:
```go
import "encoding/json"
// ...
func SettingsFromSQLC(s sqlcgen.UserSetting) dto.SettingsResponse {
	var prefs map[string]any
	if len(s.Preferences) > 0 {
		_ = json.Unmarshal(s.Preferences, &prefs)
	}
	if prefs == nil {
		prefs = make(map[string]any)
	}

	return dto.SettingsResponse{
		Timezone:    s.Timezone,
		Preferences: prefs,
		CreatedAt:   FormatTime(s.CreatedAt),
		UpdatedAt:   FormatTime(s.UpdatedAt),
	}
}
```

- [ ] **Step 3: Update Handler**

In `backend/internal/settings/handler.go`, update `UpdateSettingsRequest`:
```go
type UpdateSettingsRequest struct {
	Timezone    string         `json:"timezone"`
	Preferences map[string]any `json:"preferences"`
}
```
*(Remove the `validate:"required"` on timezone if we are allowing partial updates, or keep it but also add Preferences)*

Update the `Update` method:
```go
	var req UpdateSettingsRequest
	if err := web.BindAndValidate(c, &req); err != nil {
		return err
	}

	settings, err := h.svc.Update(c.Request().Context(), userID, req)
```

- [ ] **Step 4: Update Service**

In `backend/internal/settings/service.go`, change `Update` signature and implementation:
```go
import "encoding/json"
// ...
func (s *Service) Update(ctx context.Context, userID pgtype.UUID, req UpdateSettingsRequest) (dto.SettingsResponse, error) {
	tz := strings.TrimSpace(req.Timezone)
	if tz != "" {
		if _, err := time.LoadLocation(tz); err != nil {
			return dto.SettingsResponse{}, ErrInvalidTimezone
		}
	}

	var prefsBytes []byte
	if req.Preferences != nil {
		prefsBytes, _ = json.Marshal(req.Preferences)
	}

	settings, err := s.q.UpdateUserSettings(ctx, sqlcgen.UpdateUserSettingsParams{
		UserID:      userID,
		Timezone:    tz,
		Preferences: prefsBytes,
	})
	if err != nil {
		return dto.SettingsResponse{}, err
	}
	return mapper.SettingsFromSQLC(settings), nil
}
```
*(Ensure to update the import in `handler.go` if `UpdateSettingsRequest` was moved to `dto`, but here it's defined in `handler.go`. Since it's in `handler.go`, you may need to move it to `dto` so `service.go` can import it without circular dependencies. Let's move `UpdateSettingsRequest` to `backend/internal/dto/settings.go`)*

**Self-Correction for Step 3 & 4**: Move `UpdateSettingsRequest` to `dto/settings.go` and update `handler.go` to use `dto.UpdateSettingsRequest`.

- [ ] **Step 5: Verify build**

Run: `cd backend && go build ./...`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add backend/
git commit -m "feat(backend): expose preferences in settings api"
```

### Task 3: Frontend Data Layer

**Files:**
- Modify: `lib/features/settings/data/settings_models.dart`
- Modify: `lib/features/settings/data/settings_repository.dart`
- Modify: `lib/features/auth/presentation/controllers/auth_controller.dart`

- [ ] **Step 1: Update UserSettings model**

In `lib/features/settings/data/settings_models.dart`:
```dart
class UserSettings {
  const UserSettings({
    required this.timezone,
    required this.preferences,
    required this.createdAt,
    required this.updatedAt,
  });

  final String timezone;
  final Map<String, dynamic> preferences;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory UserSettings.fromJson(Map<String, dynamic> json) {
    return UserSettings(
      timezone: json['timezone'] as String,
      preferences: json['preferences'] as Map<String, dynamic>? ?? {},
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
    );
  }
}
```

- [ ] **Step 2: Update SettingsRepository**

In `lib/features/settings/data/settings_repository.dart`, modify `updateSettings`:
```dart
  Future<UserSettings> updateSettings({
    String? timezone,
    Map<String, dynamic>? preferences,
  }) async {
    final response = await _apiClient.put(
      _SettingsRoutes.settings,
      data: {
        if (timezone != null) 'timezone': timezone,
        if (preferences != null) 'preferences': preferences,
      },
    );
    return UserSettings.fromJson(response.data as Map<String, dynamic>);
  }
```

- [ ] **Step 3: Update AuthController**

In `lib/features/auth/presentation/controllers/auth_controller.dart` (or wherever the logic is to update settings):
Add a method to easily update preferences:
```dart
  Future<void> updatePreference(String key, dynamic value) async {
    final currentSettings = state.value?.session.settings;
    if (currentSettings == null) return;
    
    final currentPrefs = Map<String, dynamic>.from(currentSettings['preferences'] ?? {});
    currentPrefs[key] = value;
    
    // Call repository to update settings
    final repo = ref.read(settingsRepositoryProvider);
    final updatedSettings = await repo.updateSettings(preferences: currentPrefs);
    
    // Update local state with the new session
    final session = state.value!.session;
    // Replace settings inside the raw JSON session data.
    // ... we need to ensure the updated settings JSON is correctly put back into the session cache.
  }
```
*(Alternatively, in `NotesListScreen`, we can just call `settingsRepository.updateSettings` and then `ref.read(authControllerProvider.notifier).refresh()` to reload the session. Let's use the simplest approach.)*

- [ ] **Step 4: Commit**

```bash
git add lib/features/settings/ lib/features/auth/
git commit -m "feat(frontend): add preferences to UserSettings model"
```

### Task 4: UI Toggle in Notes List

**Files:**
- Modify: `lib/features/notes/presentation/notes_list_screen.dart`
- Modify: `lib/features/notes/presentation/widgets/notes_more_menu.dart`

- [ ] **Step 1: Use Preferences in NotesListScreen**

In `lib/features/notes/presentation/notes_list_screen.dart`, remove the `_viewMode` enum and state.
Use the value from `ref.watch(authControllerProvider)`:

```dart
// Inside build()
final session = ref.watch(authControllerProvider).value?.session;
final settingsJson = session?.settings ?? {};
final prefs = settingsJson['preferences'] as Map<String, dynamic>? ?? {};
final isGridView = prefs['notes_view_mode'] == 'grid';

// Replace `_viewMode == _NotesViewMode.grid` with `isGridView`.
```

- [ ] **Step 2: Update the Toggle logic**

When toggling:
```dart
onToggleView: () async {
  final newMode = isGridView ? 'list' : 'grid';
  
  // Optimistic UI could be done via a local StateProvider if we wanted, 
  // but let's just make the API call and refresh the auth controller.
  final repo = ref.read(settingsRepositoryProvider);
  
  final currentPrefs = Map<String, dynamic>.from(prefs);
  currentPrefs['notes_view_mode'] = newMode;
  
  await repo.updateSettings(preferences: currentPrefs);
  ref.read(authControllerProvider.notifier).checkSession(); // or whatever reloads the session
}
```
*(Wait, `authController.checkSession()` might trigger a full reload. Another way is to keep a local `ValueNotifier` or `StateProvider` for the optimistic state, and when it changes, push to API. Let's just use `ref.invalidate(authControllerProvider)` or if there's a specific refresh method).*

- [ ] **Step 3: Fix NotesMoreMenu**

In `lib/features/notes/presentation/widgets/notes_more_menu.dart`, it passes `isListView` to determine the icon.
```dart
final bool isListView = !isGridView;
```
Ensure it's using the provided `isListView` correctly.

- [ ] **Step 4: Verify build**

Run: `cd lib && flutter analyze`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/notes/
git commit -m "feat(ui): migrate notes view mode to global preferences"
```
