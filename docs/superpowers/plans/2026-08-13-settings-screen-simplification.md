# Settings Screen Simplification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Simplify the settings screen to a centered title and one flat list containing only the user's name, email, MCP configuration, and logout action.

**Architecture:** Keep `SettingsScreen` responsible for reading the authenticated user and invoking existing navigation/logout behavior. Reuse `AppTile` for all four rows, remove the now-unused section-header widget, and add focused widget coverage with a stubbed `AuthController` and local `GoRouter`.

**Tech Stack:** Flutter, Riverpod, GoRouter, Flutter widget tests, Dart.

## Global Constraints

- Use shared `AppTile`; do not introduce a new settings-row component.
- Do not change authentication, MCP, or route contracts.
- Preserve iOS 26 toolbar spacing and the existing logout confirmation dialog.
- Preserve unrelated worktree changes.

---

### Task 1: Add failing settings-screen coverage

**Files:**
- Create: `test/features/settings/presentation/settings_screen_test.dart`

**Interfaces:**
- Consumes: `SettingsScreen`, `authControllerProvider`, `AppTile`, and `AppRoutes`.
- Produces: Layout, navigation, and logout acceptance coverage for Task 2.

- [x] **Step 1: Write the failing widget tests**

Create a stub `AuthController` whose `build()` returns `User(id: 'u-1', name: 'Alice', email: 'alice@example.com')` and whose `logout()` increments a counter. Pump `SettingsScreen` inside a local `GoRouter` with `/settings` and `/settings/mcp` routes.

Cover these behaviors:

```dart
expect(tester.widget<AppBar>(find.byType(AppBar)).centerTitle, isTrue);
expect(find.text('Alice'), findsOneWidget);
expect(find.text('alice@example.com'), findsOneWidget);
expect(find.text('Nome'), findsNothing);
expect(find.text('Email'), findsNothing);
expect(find.text('Conta'), findsNothing);
expect(find.text('Avançado'), findsNothing);

final tiles = tester.widgetList<AppTile>(find.byType(AppTile));
expect(tiles, hasLength(4));
expect(tiles.every((tile) => tile.subtitle == null), isTrue);
```

Also tap `Protocolo de Contexto (MCP)` and assert the MCP stub route is visible. Tap `Sair da conta`, confirm with `Sair`, and assert the stub controller's logout count is one.

- [x] **Step 2: Run the focused test and verify the expected failure**

Run:

```powershell
flutter test test/features/settings/presentation/settings_screen_test.dart
```

Expected: FAIL because the current screen centers no title, renders section headers, and uses labels/subtitles instead of value titles.

### Task 2: Implement the flat settings layout

**Files:**
- Modify: `lib/features/settings/presentation/settings_screen.dart`
- Delete: `lib/features/settings/presentation/widgets/settings_section_header.dart`

**Interfaces:**
- Consumes: `authControllerProvider`, `AppRoutes.mcp`, and existing `_confirmLogout`.
- Produces: A centered `Configurações` `AppBar` and four title-only `AppTile`s.

- [x] **Step 1: Replace the settings children**

Set `centerTitle: true` on the existing `AppBar`. Remove the section-header import and both section-header children. Use these four tiles in one list:

```dart
AppTile(
  leading: const Icon(Icons.person_outline),
  title: account?.name ?? '—',
),
AppTile(
  leading: const Icon(Icons.alternate_email),
  title: account?.email ?? '—',
),
AppTile(
  leading: const Icon(Icons.developer_mode_outlined),
  title: 'Protocolo de Contexto (MCP)',
  onTap: () => context.push(AppRoutes.mcp),
  trailing: const Icon(Icons.chevron_right),
),
AppTile(
  leading: const Icon(Icons.logout),
  title: 'Sair da conta',
  onTap: () => _confirmLogout(context, ref),
  enabled: account != null,
),
```

Keep the current list padding and `_confirmLogout` method unchanged.

- [x] **Step 2: Run the focused test and verify it passes**

Run:

```powershell
flutter test test/features/settings/presentation/settings_screen_test.dart
```

Expected: PASS with the centered title, four title-only tiles, MCP navigation, and confirmed logout behavior.

### Task 3: Verify the scoped change

**Files:**
- Modify: none.

- [x] **Step 1: Format changed Dart files**

Run:

```powershell
dart format lib/features/settings/presentation/settings_screen.dart test/features/settings/presentation/settings_screen_test.dart
```

- [x] **Step 2: Run static analysis**

Run:

```powershell
flutter analyze
```

Expected: `No issues found!`.

- [x] **Step 3: Check the diff**

Run:

```powershell
git diff --check
git status --short
```

Expected: no whitespace errors; unrelated existing worktree changes remain untouched.
