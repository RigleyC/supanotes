# Settings Screen Simplification Design

## Goal

Simplify the settings screen so it has a centered page title and one flat list
with only the user's name, email, MCP configuration, and account logout action.

## Approved design

- Set the settings `AppBar` title to `centerTitle: true`.
- Remove the `Conta` and `Avançado` section headers.
- Remove the unused `SettingsSectionHeader` widget and its file.
- Keep the existing `AppTile` shared component for all four rows.
- Render the account name and email as the tile titles, without subtitles.
- Keep the MCP tile title-only, with its existing navigation and chevron.
- Keep the logout tile title-only, with its existing confirmation dialog and
  logout behavior.
- Keep the current account fallback (`—`) and iOS 26 toolbar spacing.

## Acceptance criteria

1. The `Configurações` title is centered.
2. `Conta` and `Avançado` are not rendered.
3. No settings tile uses a subtitle.
4. The authenticated user's name and email appear as tile titles.
5. MCP navigation still pushes `AppRoutes.mcp`.
6. Logout still opens the confirmation dialog and calls the auth controller
   only after confirmation.

## Verification

- Add focused widget coverage for the settings layout and account values.
- Run the focused settings test.
- Run `flutter analyze`.
