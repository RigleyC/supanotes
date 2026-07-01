# User Settings UI Preferences

## Context
Currently, some UI toggles (like the List vs Grid view for the notes screen) are stored as local state or not persisted across app sessions globally. We want to persist these choices so that the user's preferred layout is remembered. 

Instead of adding a new database column for every single UI toggle we invent, we will leverage a flexible JSONB column.

## Architecture

We will add a `preferences` JSONB column to the `user_settings` table. This allows the frontend to store arbitrary key-value pairs for UI configurations without requiring backend migrations for each new setting.

### 1. Database
- **Migration**: Add `preferences JSONB NOT NULL DEFAULT '{}'::jsonb` to the `user_settings` table.
- **Data Shape**: `{"notes_view_mode": "grid", ...}`.

### 2. Backend (Go)
- Update SQLC schema for `user_settings` to include `preferences`.
- Regenerate SQLC models.
- Update `/api/v1/settings` DTOs (`dto.SettingsResponse`, `dto.UpdateSettingsRequest`) to accept and return a `preferences` map (e.g., `map[string]any`).
- Update `internal/settings/service.go` and `mapper.go` to handle the JSONB field.

### 3. Frontend (Flutter)
- **Domain Model**: Update `UserSettings` in `lib/features/settings/data/settings_models.dart` to include `final Map<String, dynamic> preferences;`.
- **State Management**: 
  - The UI (e.g., `NotesListScreen`) will read `notes_view_mode` from the persisted session state (`ref.watch(authControllerProvider).value?.session.settings['preferences']['notes_view_mode']`).
  - When the user toggles the view, it will call the repository to update the settings (`updateSettings(..., preferences: newPrefs)`), and the updated session will reflect the change.
- **UI Elements**: The toggle button remains in the `NotesListScreen` (or `NotesMoreMenu`), but its state is driven by the global preferences rather than local state.

## Trade-offs & Decisions
- **Why JSONB?** It prevents migration churn for purely cosmetic or client-specific UI preferences.
- **Validation**: The backend will treat `preferences` as an opaque JSON blob. The frontend is responsible for ensuring type safety when reading from the map (e.g., falling back to default values if a key is missing or of the wrong type).
