# Global Family Sheet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a shared Family-based sheet API and migrate `TaskMetadataSheet` and the note icon picker to a fixed-header, page-aware layout with consistent closing behavior.

**Architecture:** Add a thin shared presentation layer with `showGlobalSheet`, `GlobalSheetPage`, and `GlobalSheetHeader`. `showGlobalSheet` owns only Family modal configuration; `GlobalSheetPage` owns the fixed header and bounded content area; feature widgets keep their state, navigation targets, scrolling, and persistence rules. The close button always calls `FamilyModalSheet.of(context).popPage()`, so internal pages return and the root page dismisses the modal; callers persist state after awaiting the root sheet.

**Tech Stack:** Flutter/Dart, `family_bottom_sheet`, Flutter widget tests, Riverpod task metadata provider.

## Global Constraints

- Use `FamilyModalSheet`; do not modify the external `family_bottom_sheet` package.
- The shared entry point must have a maximum height of 50% of the viewport and no height override in this implementation.
- The shared layer must not own feature persistence, business callbacks, or global sheet state.
- Use separate widgets/files for shared header and page layout; do not add private builder methods or large private component trees inside existing feature widgets.
- Internal-page close means `popPage()`; root-page close resolves the sheet future.
- The caller remains the authority for the final action after `await showGlobalSheet(...)`.
- Keep `showAppBottomSheet` and its consumers unchanged in this implementation.
- Do not touch unrelated working-tree changes, including `lib/features/notes/editor/document/note_document_codec.dart`.
- Preserve existing strings and feature behavior unless the shared header requires a title or tooltip change.
- Run Flutter checks sequentially to avoid stale Flutter processes.

## Current File Map

- Create `lib/shared/widgets/global_sheet.dart`: public `showGlobalSheet` entry point and exports for the shared sheet widgets.
- Create `lib/shared/widgets/global_sheet_page.dart`: `GlobalSheetPage` layout with a fixed header and bounded content slot.
- Create `lib/shared/widgets/global_sheet_header.dart`: title and top-right close button; close delegates to `FamilyModalSheet.popPage()`.
- Modify `lib/features/tasks/presentation/widgets/task_metadata_sheet.dart`: open through `showGlobalSheet`, wrap the root body in `GlobalSheetPage`, remove the duplicated root title, preserve post-await save and cleanup.
- Modify `lib/features/tasks/presentation/widgets/task_metadata_page_header.dart`: replace the feature-specific header with `GlobalSheetHeader` usage or remove the file after all internal pages use the shared page wrapper; no duplicate close logic remains.
- Modify `lib/features/tasks/presentation/widgets/task_metadata_date_page.dart`: wrap the page in `GlobalSheetPage` and keep date selection behavior; make the long content fit the bounded content slot.
- Modify `lib/features/tasks/presentation/widgets/task_metadata_time_page.dart`: wrap the page in `GlobalSheetPage` and keep the existing picker/confirm behavior.
- Modify `lib/features/tasks/presentation/widgets/task_metadata_selection_page.dart`: wrap the selection page in `GlobalSheetPage`; keep selection then `popPage()` behavior.
- Modify `lib/features/notes/catalog/presentation/widgets/note_icon_picker.dart`: open through `showGlobalSheet`, wrap root and picker pages with `GlobalSheetPage`, and remove Family/header presentation duplication.
- Modify `lib/features/notes/catalog/presentation/widgets/note_icon_picker_components.dart`: remove `_PickerHeader`, use the shared header/page wrapper, and keep the grid as the only vertical scrollable region.
- Create or modify `test/shared/widgets/global_sheet_test.dart`: test root/internal close semantics, page titles, and fixed-header scrolling.
- Modify `test/features/tasks/presentation/widgets/task_metadata_sheet_test.dart`: preserve existing persistence coverage and add root/header assertions.
- Modify `test/features/notes/catalog/presentation/widgets/note_icon_picker_test.dart`: assert fixed search/color controls while the icon grid scrolls.

## Task 1: Add the shared Family sheet API and page widgets

**Files:**
- Create: `lib/shared/widgets/global_sheet.dart`
- Create: `lib/shared/widgets/global_sheet_page.dart`
- Create: `lib/shared/widgets/global_sheet_header.dart`
- Test: `test/shared/widgets/global_sheet_test.dart`

**Interfaces:**
- Produces `Future<T?> showGlobalSheet<T>({required BuildContext context, required WidgetBuilder builder})`.
- Produces `GlobalSheetPage({Key? key, required String title, required Widget child})`.
- Produces `GlobalSheetHeader({Key? key, required String title})`.
- `GlobalSheetHeader` depends on `FamilyModalSheet.of(context).popPage()` and does not accept an `onClose` callback.

- [ ] **Step 1: Write failing tests for the shared contract.**

  Build a `MaterialApp` test harness that opens `showGlobalSheet` from a button. The root builder returns `GlobalSheetPage(title: 'Página principal', child: const SizedBox(height: 40))`. Add a test that taps the header close button, pumps until settled, and verifies the future completed and a caller-side `closed` flag became true.

  Add an internal-page test whose root content has a button that calls:

  ```dart
  FamilyModalSheet.of(context).pushPage(
    const GlobalSheetPage(
      title: 'Página interna',
      child: SizedBox(height: 40),
    ),
  );
  ```

  Tap the root button, verify both titles are not present at the same time after navigation, tap the internal close button, and verify the root title returns while the outer future remains unresolved. Then tap the root close button and verify the future completes.

  Add a scroll test with a long `ListView` inside `GlobalSheetPage`; after scrolling the list, verify the page title and close button remain visible.

- [ ] **Step 2: Run the new tests and confirm they fail for missing shared widgets.**

  Run:

  ```text
  flutter test test/shared/widgets/global_sheet_test.dart
  ```

  Expected result: compile failure because the shared API and widgets do not exist yet.

- [ ] **Step 3: Implement `showGlobalSheet` with one Family configuration.**

  Implement the exact public signature:

  ```dart
  Future<T?> showGlobalSheet<T>({
    required BuildContext context,
    required WidgetBuilder builder,
  }) {
    return FamilyModalSheet.show<T>(
      context: context,
      isDismissible: true,
      enableDrag: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.5,
      ),
      contentBackgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      builder: builder,
    );
  }
  ```

  Do not add `onClose`, `maxHeightFactor`, `isDismissible`, or other options in this first API. The approved design has one boring default configuration.

- [ ] **Step 4: Implement `GlobalSheetHeader` as a standalone widget.**

  Use a `Padding` and `Row`, with the title in `Expanded` using `titleMedium`. Put an `IconButton` on the right with `Icons.close_rounded`, tooltip `Fechar`, and this exact close behavior:

  ```dart
  onPressed: () => FamilyModalSheet.of(context).popPage(),
  ```

  Do not inspect page count or call `Navigator.pop` directly. `FamilyModalSheet.popPage()` already handles root dismissal and internal navigation.

- [ ] **Step 5: Implement `GlobalSheetPage` with a fixed header and bounded child.**

  Use a transparent `Material` and a `Column` with the header outside the content slot. The content slot must be `Expanded(child: child)` so a feature-owned `ListView` or `CustomScrollView` receives a bounded viewport. Apply the approved 24 px horizontal/top spacing in the page/header boundary. Do not wrap the entire page in a scroll view.

- [ ] **Step 6: Run the shared tests and analyzer.**

  Run:

  ```text
  flutter test test/shared/widgets/global_sheet_test.dart
  flutter analyze lib/shared/widgets/global_sheet.dart lib/shared/widgets/global_sheet_page.dart lib/shared/widgets/global_sheet_header.dart
  ```

  Expected result: all shared widget tests pass and the analyzer reports no issues.

- [ ] **Step 7: Commit the shared component.**

  ```text
  git add lib/shared/widgets/global_sheet.dart lib/shared/widgets/global_sheet_page.dart lib/shared/widgets/global_sheet_header.dart test/shared/widgets/global_sheet_test.dart
  git commit -m "feat(ui): add global family sheet components"
  ```

## Task 2: Migrate `TaskMetadataSheet` without changing persistence semantics

**Files:**
- Modify: `lib/features/tasks/presentation/widgets/task_metadata_sheet.dart`
- Delete: `lib/features/tasks/presentation/widgets/task_metadata_page_header.dart`
- Modify: `lib/features/tasks/presentation/widgets/task_metadata_date_page.dart`
- Modify: `lib/features/tasks/presentation/widgets/task_metadata_time_page.dart`
- Modify: `lib/features/tasks/presentation/widgets/task_metadata_selection_page.dart`
- Test: `test/features/tasks/presentation/widgets/task_metadata_sheet_test.dart`

**Interfaces:**
- Consumes `showGlobalSheet` and `GlobalSheetPage` from `lib/shared/widgets`.
- Keeps `showTaskMetadataSheet` signature and `onSave` signature unchanged.
- Keeps `TaskMetadataSheetBody` as the provider-backed content widget.

- [ ] **Step 1: Add regression assertions before changing the task sheet.**

  Extend the existing task sheet widget tests to verify the root page renders the title `Editar horário e frequência` and a close button with tooltip `Fechar` when opened through `showTaskMetadataSheet`. Keep the existing test that selects date, time, and recurrence, then dismisses the root sheet and asserts `onSave` receives the final values.

- [ ] **Step 2: Run the task sheet tests to establish the current baseline.**

  Run:

  ```text
  flutter test test/features/tasks/presentation/widgets/task_metadata_sheet_test.dart
  ```

  Expected result: the existing suite passes; the new tooltip assertion may fail until migration because the root page has no shared close button.

- [ ] **Step 3: Migrate the root opening path.**

  In `showTaskMetadataSheet`, replace only the `FamilyModalSheet.show<void>` call with `showGlobalSheet<void>`. Preserve the surrounding `try/finally`, `controller.releaseSheet()`, provider invalidation, logging, reminder permission handling, and post-await `onSave` call exactly.

  Change the builder to return:

  ```dart
  GlobalSheetPage(
    title: 'Editar horário e frequência',
    child: TaskMetadataSheetBody(taskId: taskId),
  )
  ```

  Remove the root title and its title spacing from `TaskMetadataSheetBody`; keep the provider watch and all metadata tiles unchanged.

- [ ] **Step 4: Migrate task internal pages to the shared page wrapper.**

  Replace each `TaskMetadataPageHeader` with `GlobalSheetPage` at the page root and delete the old header file after all imports are removed:

  - `TaskMetadataDatePage`: title `Escolher data`; pass a `SingleChildScrollView` containing the quick-date list, bottom spacing, and `CalendarDatePicker`; preserve selection callbacks and `popPage()` calls.
  - `TaskMetadataTimePage`: title `Escolher horário`; pass the existing picker and confirm button as the child; preserve selected-time state, confirmation callback, and `popPage()` after confirmation.
  - `TaskMetadataSelectionPage<T>`: use its existing `title`; pass a `SingleChildScrollView` containing all `AppSelectionTile` rows; preserve selection and `popPage()` after selection.

  Remove the feature-specific close header once no task page uses it. Do not change selection callbacks or controller mutations.

- [ ] **Step 5: Verify root and internal close behavior.**

  Update the task test flow so it opens a metadata subpage, taps the shared `Fechar` button, verifies the root title returns, and only then dismisses the root sheet. Assert that the save callback runs once after root dismissal, not when the internal page closes.

- [ ] **Step 6: Run focused task checks.**

  Run:

  ```text
  dart format lib/shared/widgets/global_sheet.dart lib/shared/widgets/global_sheet_page.dart lib/shared/widgets/global_sheet_header.dart lib/features/tasks/presentation/widgets/task_metadata_sheet.dart lib/features/tasks/presentation/widgets/task_metadata_date_page.dart lib/features/tasks/presentation/widgets/task_metadata_time_page.dart lib/features/tasks/presentation/widgets/task_metadata_selection_page.dart
  flutter test test/features/tasks/presentation/widgets/task_metadata_sheet_test.dart
  flutter analyze lib/shared/widgets lib/features/tasks/presentation/widgets
  ```

  Expected result: task metadata tests pass, including save-after-root-dismissal, and analyzer reports no issues in the checked paths.

- [ ] **Step 7: Commit the task migration.**

  ```text
  git add lib/features/tasks/presentation/widgets/task_metadata_sheet.dart lib/features/tasks/presentation/widgets/task_metadata_date_page.dart lib/features/tasks/presentation/widgets/task_metadata_time_page.dart lib/features/tasks/presentation/widgets/task_metadata_selection_page.dart lib/features/tasks/presentation/widgets/task_metadata_page_header.dart test/features/tasks/presentation/widgets/task_metadata_sheet_test.dart
  git commit -m "refactor(tasks): use global family sheet layout"
  ```

## Task 3: Migrate the note icon picker and preserve fixed controls

**Files:**
- Modify: `lib/features/notes/catalog/presentation/widgets/note_icon_picker.dart`
- Modify: `lib/features/notes/catalog/presentation/widgets/note_icon_picker_components.dart`
- Test: `test/features/notes/catalog/presentation/widgets/note_icon_picker_test.dart`

**Interfaces:**
- Consumes `showGlobalSheet` and `GlobalSheetPage`.
- Keeps `showNoteIconPicker` signature and immediate-save `onSelected` behavior unchanged.
- Keeps emoji/catalog selection callbacks and the current icon catalog model unchanged.

- [ ] **Step 1: Add picker layout regression tests.**

  Keep the existing 48 px color and icon hit-target assertions. Add a test that pumps `NoteEmojiPickerPage` on a 360×800 surface, finds the title and search field, scrolls the grid using the `CustomScrollView`/grid finder, and verifies the title and search field remain visible. Add the equivalent catalog assertion for the search field and `Cor red` color target.

- [ ] **Step 2: Run the picker tests before migration.**

  ```text
  flutter test test/features/notes/catalog/presentation/widgets/note_icon_picker_test.dart
  ```

  Expected result: the existing hit-target test passes; the new fixed-control assertions describe the required layout and must be retained during migration.

- [ ] **Step 3: Migrate the root picker page.**

  Replace `FamilyModalSheet.show<void>` with `showGlobalSheet<void>` in `showNoteIconPicker`. Preserve the read-only early return, immediate `onSelected` await, and root dismissal after selection.

  Make `NoteIconPickerRootPage` return `GlobalSheetPage(title: 'Selecionar ícone', child: ...)`. Keep the three action rows and their internal page pushes unchanged.

- [ ] **Step 4: Migrate emoji and catalog pages to fixed shared headers.**

  Wrap each page in `GlobalSheetPage` with its existing title:

  - Emoji page: `Escolher emoji`; content below the header contains the search field and the emoji grid.
  - Catalog page: `Escolher ícone`; content below the header contains the search field, horizontal color selector, and icon grid.

  Remove `_PickerHeader` and the `onBack` parameter from `_PickerScrollPage`. The shared `GlobalSheetHeader` supplies the close button. Keep the existing `Expanded(CustomScrollView(...))` structure so only the grid scrolls; do not put the search field or color selector inside the vertical scroll view. Keep horizontal color scrolling unchanged.

- [ ] **Step 5: Remove duplicated picker page wrappers only after migration.**

  Replace `_PickerScrollPage` with one standalone `_PickerGridContent` widget. It receives `headerChildren`, `itemCount`, and `itemBuilder`; it renders the fixed `headerChildren` in a `Column` followed by `Expanded(child: CustomScrollView(...))`. Keep `_PickerAction` as a standalone widget. Do not create builder methods inside the state classes. Preserve `TextEditingController` disposal and query filtering.

- [ ] **Step 6: Run focused picker checks.**

  ```text
  dart format lib/features/notes/catalog/presentation/widgets/note_icon_picker.dart lib/features/notes/catalog/presentation/widgets/note_icon_picker_components.dart
  flutter test test/features/notes/catalog/presentation/widgets/note_icon_picker_test.dart
  flutter analyze lib/features/notes/catalog/presentation/widgets/note_icon_picker.dart lib/features/notes/catalog/presentation/widgets/note_icon_picker_components.dart
  ```

  Expected result: hit targets, fixed header/search/color controls, selection callbacks, and analyzer checks pass.

- [ ] **Step 7: Commit the picker migration.**

  ```text
  git add lib/features/notes/catalog/presentation/widgets/note_icon_picker.dart lib/features/notes/catalog/presentation/widgets/note_icon_picker_components.dart test/features/notes/catalog/presentation/widgets/note_icon_picker_test.dart
  git commit -m "refactor(notes): use global family sheet layout"
  ```

## Task 4: Full verification and scope review

**Files:**
- Verify only: all files changed by Tasks 1–3.
- Do not stage or modify: `lib/features/notes/editor/document/note_document_codec.dart` and any other pre-existing working-tree change.

**Interfaces:**
- Consumes the completed shared sheet, task migration, and icon picker migration.
- Produces verified tests and a clean, scope-limited diff for this feature.

- [ ] **Step 1: Inspect the final scope.**

  Before implementation, record the current commit with `git rev-parse HEAD`; use that SHA to inspect the feature diff in this task. Run:

  ```text
  git status --short --branch
  git diff --check
  git diff --name-only
  git log --oneline -5
  ```

  Confirm the commits created from the recorded base SHA contain only the shared sheet files, the two migrated feature areas, and their tests. Confirm the pre-existing `note_document_codec.dart` change remains unstaged and uncommitted by this work.

- [ ] **Step 2: Run the combined focused test set.**

  Run sequentially:

  ```text
  flutter test test/shared/widgets/global_sheet_test.dart
  flutter test test/features/tasks/presentation/widgets/task_metadata_sheet_test.dart
  flutter test test/features/notes/catalog/presentation/widgets/note_icon_picker_test.dart
  ```

  Expected result: all three commands exit successfully.

- [ ] **Step 3: Run analyzer on all migrated Dart paths.**

  ```text
  flutter analyze lib/shared/widgets/global_sheet.dart lib/shared/widgets/global_sheet_page.dart lib/shared/widgets/global_sheet_header.dart lib/features/tasks/presentation/widgets/task_metadata_sheet.dart lib/features/tasks/presentation/widgets/task_metadata_date_page.dart lib/features/tasks/presentation/widgets/task_metadata_time_page.dart lib/features/tasks/presentation/widgets/task_metadata_selection_page.dart lib/features/notes/catalog/presentation/widgets/note_icon_picker.dart lib/features/notes/catalog/presentation/widgets/note_icon_picker_components.dart
  ```

  Expected result: `No issues found`.

- [ ] **Step 4: Run the full Flutter suite once.**

  ```text
  flutter test
  ```

  Record the completed result. If the suite times out, report the timeout and the focused checks separately; do not claim a full-suite pass.

- [ ] **Step 5: Perform a final code-quality review.**

  Check that:

  - no shared widget contains feature persistence or provider access;
  - no migrated page duplicates the title/close header;
  - the close icon calls only `popPage()`;
  - the root task save still occurs only after the sheet future resolves;
  - picker search and color controls are outside the vertical grid scroll view;
  - no new configurable parameters or compatibility fallbacks were added;
  - all modified widgets are standalone classes with one responsibility.

- [ ] **Step 6: Commit verification-only fixes, if needed.**

  If the review finds a real issue, fix it in a focused commit with the affected test. If no issue is found, do not create an empty commit.
