# Root Navigator Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make SupaNotes hide the shared adaptive bottom navigation through GoRouter's navigator hierarchy instead of a route-path visibility flag.

**Architecture:** Keep `AppNavigationShell` as the single owner of the adaptive bottom navigation. Add a root navigator key to `GoRouter` and render task completion, standalone task editor, task editor detail, and note editor routes on that root navigator so they cover the shell automatically.

**Tech Stack:** Flutter, Dart, GoRouter, Riverpod, adaptive_platform_ui.

**Spec:** `docs/superpowers/specs/2026-09-16-root-navigator-navigation-design.md`

## Global Constraints

- Preserve `StatefulShellRoute.indexedStack` branch state.
- Do not add route-path visibility flags or duplicate navigation bars.
- Do not add visual behavior tests; test route/configuration outcomes only.
- Preserve the unrelated untracked `.tmp/` directory.

---

### Task 1: Move detail routes to the root navigator

**Files:**
- Modify: `lib/core/router/app_router.dart`

**Interfaces:**
- Consumes: existing `GoRouter`, `StatefulShellRoute`, `AppRoutes`, and detail route builders.
- Produces: `rootNavigatorKey` passed to `GoRouter` and assigned to detail routes through `parentNavigatorKey`.

- [x] Add a module-level `GlobalKey<NavigatorState>` and pass it through `GoRouter(navigatorKey: ...)`.
- [x] Remove `showNavigationBar` from the shell builder.
- [x] Add `parentNavigatorKey: rootNavigatorKey` to `tasks/completed`, `tasks/standalone`, `tasks/standalone/:id`, and `notes/:id`.
- [x] Keep `/tasks` and `/notes` as the stateful branch root routes.

### Task 2: Simplify the navigation shell

**Files:**
- Modify: `lib/shared/widgets/app_navigation_shell.dart`
- Modify: `lib/shared/widgets/app_button.dart`
- Modify: `lib/features/tasks/presentation/tasks_screen.dart`
- Modify: `lib/features/notes/catalog/presentation/notes_list_screen.dart`

**Interfaces:**
- Consumes: `StatefulNavigationShell`.
- Produces: an `AdaptiveScaffold` that always renders the shared adaptive bottom navigation.

- [x] Remove the `showNavigationBar` constructor argument and field.
- [x] Remove the conditional around `AdaptiveBottomNavigationBar`.
- [x] Keep branch selection and initial-location behavior unchanged.
- [x] Add an optional `heroTag` to `AppButton` and assign distinct tags to the Tasks and Notes root FABs to prevent Hero collisions during root-navigator transitions.

### Task 3: Add focused route coverage

**Files:**
- Modify: `test/core/router/app_router_test.dart`
- Modify: `test/shared/widgets/app_button_test.dart`

**Interfaces:**
- Consumes: existing router test harness and `AppRoutes`.
- Produces: assertions that root detail routes cover the shell while root task/note routes retain the shell.

- [x] Inspect existing router tests and extend only the relevant route assertions.
- [x] Verify navigation to `/tasks/completed`, `/tasks/standalone`, `/tasks/standalone/:id`, and `/notes/:id` resolves successfully.
- [x] Verify navigation back to `/tasks` and `/notes` remains successful.
- [x] Verify `AppButton` forwards a custom FAB Hero tag.

### Task 4: Validate and review the diff

**Files:**
- Check: changed Dart files and focused tests.

- [x] Run the focused router test file with Flutter.
- [x] Run `flutter analyze` for the affected project.
- [x] Run `git diff --check`.
- [x] Confirm only intended files changed and `.tmp/` remains untracked.
