# Root Navigator Navigation Design

## Goal

Make SupaNotes hide the shared adaptive bottom navigation automatically when opening completed tasks, task editors, or a note editor, using GoRouter's navigator hierarchy instead of a route-path visibility flag.

## Current problem

`AppNavigationShell` places the adaptive bottom navigation above `StatefulNavigationShell`. Child routes remain inside the shell navigator, so the parent scaffold and its navbar stay mounted. `app_router.dart` currently compensates with `showNavigationBar` checks against exact paths.

The Julius Flutter app uses the canonical alternative: the shared shell remains mounted, while detail routes that must cover it specify the root navigator with `parentNavigatorKey`.

## Chosen design

1. Add one `rootNavigatorKey` to the SupaNotes `GoRouter`.
2. Keep `AppNavigationShell` as the single owner of the shared adaptive bottom navigation.
3. Remove `showNavigationBar` and the exact-path checks.
4. Set `parentNavigatorKey: rootNavigatorKey` on:
   - `/tasks/completed`
   - `/tasks/standalone`
   - `/tasks/standalone/:id`
   - `/notes/:id`
5. Leave the root `/tasks` and `/notes` routes in their existing stateful branches, preserving tab and branch state.
6. Add focused router assertions for the route hierarchy/visibility behavior without visual tests.

## Files

- Modify `lib/core/router/app_router.dart` to create the root key, pass it to `GoRouter`, remove the visibility flag, and assign it to detail routes.
- Modify `lib/shared/widgets/app_navigation_shell.dart` to remove `showNavigationBar` and always render the shared bar.
- Modify `test/core/router/app_router_test.dart` only where focused route coverage is needed.

## Non-goals

- Do not move the navbar into each root page.
- Do not duplicate adaptive scaffolds or navigation state.
- Do not change task/note ownership, data loading, editor behavior, or app-bar implementation in this change.

## Validation

- Run the focused router tests.
- Run the affected Flutter analyzer/test checks.
- Run `git diff --check`.
- Preserve the existing unrelated `.tmp/` worktree change.
