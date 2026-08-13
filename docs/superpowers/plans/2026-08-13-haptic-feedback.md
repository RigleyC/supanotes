# Haptic Feedback Defaults Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add consistent, short haptic feedback to the app's shared controls and to every actionable control inside the task metadata and emoji/icon sheets.

**Architecture:** Keep one small `AppHaptics` boundary over Flutter's standard feedback APIs. Shared controls own feedback for their callbacks. Feature-local controls own feedback when they are not represented by a shared control. The sheet route itself does not emit feedback because its opener may be a tap, a long press, or a programmatic action.

**Tech Stack:** Flutter 3.44.1, Dart 3.12.1, `flutter/services.dart`, `flutter/widgets.dart`, existing `AppButton`, `AppSelectionTile`, `AppIconButton`, `GlobalSheetPage`, and `family_bottom_sheet`. No new package.

## Global Constraints

- Use the existing Flutter haptic APIs. Do not add a haptic plugin or a native channel.
- Use `lightImpact` for an action/control tap, `selectionClick` for a changed discrete value, and `Feedback.forLongPress` for an accepted long press.
- Emit at most one app haptic for one user action.
- Do not add feedback to typing, scrolling, sheet route creation, sheet drag, snackbar dismissal, or native picker wheel changes.
- Keep all visible state and `Semantics` labels independent from haptics.
- Do not add an app setting in this slice. Standard Flutter and platform settings remain the authority for haptic availability.
- Do not change task persistence, editor synchronization, modal navigation, or picker scrolling.
- Preserve the current unrelated worktree changes.

---

## Product decisions

| Interaction | Feedback | Owner |
| --- | --- | --- |
| Enabled `AppButton` (including its FAB variant), icon action, clear/remove action, sheet page navigation, dialog action | `AppHaptics.controlTap()` | Shared control or local action row |
| New task metadata option, quick date, emoji, icon, or color | `AppHaptics.selectionChange()` | Selection tile or picker cell |
| Task checkbox state change | `AppHaptics.selectionChange()` | Task completion handler |
| Accepted task long press | `AppHaptics.longPress(context)` | `CustomTaskComponent` gesture owner |
| `CalendarDatePicker` and `CupertinoDatePicker` wheel change | Native framework feedback only | Flutter picker |
| Search input, scroll, modal opening, modal drag, snackbar dismissal | None | No haptic owner |

`showGlobalSheet` remains feedback-free. The control that calls it owns the
feedback. This prevents a button or long press from producing a pulse at both
the gesture and sheet layers.

## Current component map

The implementation must cover these controls, including the controls inside
the sheets:

- Shared shell: `GlobalSheetHeader` close button in
  `lib/shared/widgets/global_sheet_header.dart`.
- Task root sheet: `_DateTile`, `_TimeTile`, `_RecurrenceTile`, and
  `_ReminderTile` in `lib/features/tasks/presentation/widgets/task_metadata_sheet.dart`.
  Each row opens a child page. Each populated row has a clear icon action.
- Task selection page: `AppSelectionTile` in
  `task_metadata_selection_page.dart`.
- Task date page: quick-date `AppSelectionTile` plus the framework-owned
  `CalendarDatePicker` in `task_metadata_date_page.dart`.
- Task time page: framework-owned `CupertinoDatePicker` plus the `Confirmar`
  `AppButton` in `task_metadata_time_page.dart`.
- Emoji/icon root page: `_PickerAction` in
  `note_icon_picker_components.dart` for “Usar emoji”, “Usar ícone”, and
  “Remover ícone”.
- Emoji page: the `InkWell` cell in the emoji grid in
  `note_icon_picker.dart`.
- Catalog icon page: color `InkWell` controls and catalog icon `InkWell`
  cells in `note_icon_picker.dart`.
- Existing editor feedback: direct calls in
  `custom_task_component.dart` and `note_toolbar.dart`.

The search `AppInput` widgets remain without haptic feedback while the user
types. The fixed header and color/search controls keep the current scrolling
boundary: only the picker grid scrolls.

## File map

Create:

- `lib/core/utils/app_haptics.dart` — semantic wrapper for the three standard
  feedback patterns used by this feature.
- `test/helpers/haptic_test_helper.dart` — platform-channel recorder used by
  widget tests.
- `test/core/utils/app_haptics_test.dart` — mapping tests for the wrapper.
- `test/shared/widgets/app_icon_button_test.dart` — default icon-action test.
- `test/shared/widgets/confirm_dialog_test.dart` — dialog action test.

Modify:

- `implementation_plan.md` — link this approved project plan.
- `lib/shared/widgets/app_button.dart` — default control-tap feedback.
- `lib/shared/widgets/app_icon_button.dart` — default control-tap feedback.
- `lib/shared/widgets/app_selection_tile.dart` — selection feedback only when
  the tile is not already selected.
- `lib/shared/widgets/confirm_dialog.dart` — feedback for cancel and confirm
  actions.
- `lib/shared/widgets/global_sheet_header.dart` — use the shared icon control.
- `lib/features/tasks/presentation/widgets/task_metadata_sheet.dart` — feedback
  for root-row navigation and shared clear actions.
- `lib/features/notes/catalog/presentation/widgets/note_icon_picker.dart` —
  feedback for emoji, color, and icon selection.
- `lib/features/notes/catalog/presentation/widgets/note_icon_picker_components.dart` —
  feedback for root picker actions.
- `lib/features/notes/editor/presentation/widgets/custom_task_component.dart` —
  centralize checkbox and long-press feedback with one owner.
- `lib/features/notes/editor/presentation/widgets/note_toolbar.dart` — route
  existing selection feedback through `AppHaptics`.
- `test/shared/widgets/app_button_test.dart` — enabled and disabled button
  feedback coverage.
- `test/shared/widgets/app_selection_tile_test.dart` — changed and unchanged
  selection coverage.
- `test/shared/widgets/global_sheet_test.dart` — sheet header feedback.
- `test/features/tasks/presentation/widgets/task_metadata_sheet_test.dart` —
  root navigation, clear, and option feedback.
- `test/features/tasks/presentation/widgets/task_metadata_date_page_test.dart` —
  quick-date selection coverage.
- `test/features/notes/catalog/presentation/widgets/note_icon_picker_test.dart` —
  root action, emoji, color, and icon feedback coverage.
- `test/features/notes/presentation/widgets/note_toolbar_test.dart` — one
  toolbar command feedback regression.

Do not modify `pubspec.yaml`.

## Implementation tasks

### Task 1: Create the shared haptic boundary

**Files:**

- Create: `lib/core/utils/app_haptics.dart`
- Create: `test/helpers/haptic_test_helper.dart`
- Create: `test/core/utils/app_haptics_test.dart`

**Interfaces:**

- Produces `AppHaptics.controlTap()`, `AppHaptics.selectionChange()`, and
  `AppHaptics.longPress(BuildContext context)`.
- Produces `HapticTestRecorder.install()`, `HapticTestRecorder.dispose()`,
  and `HapticTestRecorder.saw(String argument)` for widget tests.

- [ ] **Step 1: Add the failing mapping tests and recorder**

  Use the platform channel that Flutter's `HapticFeedback` already uses. The
  recorder must collect calls and reset the mock handler after every test:

  ```dart
  class HapticTestRecorder {
    final calls = <MethodCall>[];

    void install() {
      TestDefaultBinaryMessengerBinding
          .instance
          .defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            calls.add(call);
            return null;
          });
    }

    void dispose() {
      TestDefaultBinaryMessengerBinding
          .instance
          .defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    }

    bool saw(String argument) {
      return calls.any(
        (call) =>
            call.method == 'HapticFeedback.vibrate' &&
            call.arguments == argument,
      );
    }
  }
  ```

  Add tests named `sends light impact for a control tap` and `sends a
  selection click for a changed selection`. Each test awaits the matching
  `AppHaptics` method and asserts the corresponding platform argument:
  `HapticFeedbackType.lightImpact` and
  `HapticFeedbackType.selectionClick`.

- [ ] **Step 2: Run the new test to verify it fails**

  Run:

  ```powershell
  flutter test test/core/utils/app_haptics_test.dart
  ```

  Expected: FAIL because `app_haptics.dart` and its API do not exist yet.

- [ ] **Step 3: Add the minimal production wrapper**

  Implement exactly this boundary:

  ```dart
  import 'package:flutter/services.dart';
  import 'package:flutter/widgets.dart';

  abstract final class AppHaptics {
    static Future<void> controlTap() => HapticFeedback.lightImpact();

    static Future<void> selectionChange() =>
        HapticFeedback.selectionClick();

    static void longPress(BuildContext context) {
      Feedback.forLongPress(context);
    }
  }
  ```

  Do not add success, error, warning, intensity configuration, or an app
  preference in this first boundary.

- [ ] **Step 4: Run the mapping tests to verify they pass**

  Run:

  ```powershell
  flutter test test/core/utils/app_haptics_test.dart
  ```

  Expected: PASS.

- [ ] **Step 5: Commit the isolated boundary**

  ```powershell
  git add lib/core/utils/app_haptics.dart test/helpers/haptic_test_helper.dart test/core/utils/app_haptics_test.dart
  git commit -m "feat(haptics): add shared feedback policy"
  ```

### Task 2: Add defaults to shared controls

**Files:**

- Modify: `lib/shared/widgets/app_button.dart`
- Modify: `lib/shared/widgets/app_icon_button.dart`
- Modify: `lib/shared/widgets/app_selection_tile.dart`
- Modify: `lib/shared/widgets/confirm_dialog.dart`
- Modify: `test/shared/widgets/app_button_test.dart`
- Modify: `test/shared/widgets/app_selection_tile_test.dart`
- Create: `test/shared/widgets/app_icon_button_test.dart`
- Create: `test/shared/widgets/confirm_dialog_test.dart`

**Interfaces:**

- Consumes the `AppHaptics` methods from Task 1.
- Keeps every existing callback signature unchanged.
- Produces default feedback for shared controls without requiring feature
  code to call haptics manually.

- [ ] **Step 1: Add failing widget tests**

  Add these concrete cases:

  - `AppButton` emits `HapticFeedbackType.lightImpact` when an enabled primary
    button is tapped.
  - `AppButton` emits no haptic when `isLoading` is true.
  - `AppSelectionTile` emits
    `HapticFeedbackType.selectionClick` when an unselected tile is tapped.
  - `AppSelectionTile` emits no selection haptic when `isSelected` is true,
    while still calling `onTap`.
  - `AppIconButton` emits `HapticFeedbackType.lightImpact` when its callback
    is enabled.
  - `showConfirmDialog` emits a control tap for both Cancelar and Confirmar.

  Install `HapticTestRecorder` in `setUp`, call `dispose` in `tearDown`, and
  clear `recorder.calls` between separate action assertions.

- [ ] **Step 2: Run the shared-control tests to verify they fail**

  ```powershell
  flutter test test/shared/widgets/app_button_test.dart test/shared/widgets/app_selection_tile_test.dart test/shared/widgets/app_icon_button_test.dart test/shared/widgets/confirm_dialog_test.dart
  ```

  Expected: the existing callback tests pass, and the new haptic assertions
  fail because the wrappers do not emit app haptics yet.

- [ ] **Step 3: Wrap callbacks at the shared-control boundary**

  In `AppButton`, replace the direct callback passed to the Material control
  with this enabled-only wrapper:

  ```dart
  final callback = isLoading || onPressed == null
      ? null
      : () {
          AppHaptics.controlTap();
          onPressed!();
        };
  ```

  In `AppIconButton`, use the same wrapper without the loading condition.
  In `AppSelectionTile`, emit `selectionChange` only when `isSelected` is
  false, then call the original callback. In `confirm_dialog.dart`, emit
  `controlTap` at the start of both `AlertAction` callbacks.

  Do not disable the Material feedback already provided by the platform. The
  Android click sound and the app haptic are separate feedback channels.

- [ ] **Step 4: Run the shared-control tests to verify they pass**

  ```powershell
  flutter test test/shared/widgets/app_button_test.dart test/shared/widgets/app_selection_tile_test.dart test/shared/widgets/app_icon_button_test.dart test/shared/widgets/confirm_dialog_test.dart
  ```

  Expected: PASS with no callback regressions.

- [ ] **Step 5: Commit the shared defaults**

  ```powershell
  git add lib/shared/widgets/app_button.dart lib/shared/widgets/app_icon_button.dart lib/shared/widgets/app_selection_tile.dart lib/shared/widgets/confirm_dialog.dart test/shared/widgets/app_button_test.dart test/shared/widgets/app_selection_tile_test.dart test/shared/widgets/app_icon_button_test.dart test/shared/widgets/confirm_dialog_test.dart
  git commit -m "feat(haptics): add defaults to shared controls"
  ```

### Task 3: Add feedback to the sheet shell and task metadata controls

**Files:**

- Modify: `lib/shared/widgets/global_sheet_header.dart`
- Modify: `lib/features/tasks/presentation/widgets/task_metadata_sheet.dart`
- Modify: `test/shared/widgets/global_sheet_test.dart`
- Modify: `test/features/tasks/presentation/widgets/task_metadata_sheet_test.dart`
- Modify: `test/features/tasks/presentation/widgets/task_metadata_date_page_test.dart`

**Interfaces:**

- Consumes the shared control defaults from Task 2.
- Keeps `FamilyModalSheet` navigation and `TaskMetadataDraft` persistence
  unchanged.
- Produces one control haptic for root-row navigation, clear actions, and
  sheet-page close; selection haptics come from `AppSelectionTile`.

- [ ] **Step 1: Add failing sheet interaction assertions**

  Extend the existing sheet tests with these flows:

  1. Open task metadata, clear the recorder, tap `Adicionar data`, and assert
     one `HapticFeedbackType.lightImpact` call.
  2. On the date page, tap `Hoje` and assert one
     `HapticFeedbackType.selectionClick` call.
  3. Open an existing task with a date, tap the date clear action, and assert
     one `HapticFeedbackType.lightImpact` call.
  4. Open a global sheet, tap the `Fechar` button, and assert one control-tap
     call while preserving the existing navigation assertions.

  The date-calendar test must continue to assert state and page dismissal;
  it must not assert a second custom haptic for `CalendarDatePicker`.

- [ ] **Step 2: Run the focused sheet tests to verify they fail**

  ```powershell
  flutter test test/shared/widgets/global_sheet_test.dart test/features/tasks/presentation/widgets/task_metadata_sheet_test.dart test/features/tasks/presentation/widgets/task_metadata_date_page_test.dart
  ```

  Expected: existing functional assertions pass and the new haptic
  assertions fail.

- [ ] **Step 3: Implement the task and shell ownership rules**

  In `GlobalSheetHeader`, replace the raw close `IconButton` with
  `AppIconButton`, preserving the `Fechar` tooltip, icon, and callback to
  `FamilyModalSheet.of(context).popPage()`.

  In `_DateTile`, `_TimeTile`, `_RecurrenceTile`, and `_ReminderTile`:

  - Wrap each `ListTile.onTap` with `AppHaptics.controlTap()` before pushing
    its child page.
  - Replace each populated-row clear `IconButton` with `AppIconButton`.
  - Give the clear actions the tooltips `Remover data`, `Remover horário`,
    `Remover recorrência`, and `Remover lembrete`.

  Do not add haptics to `showGlobalSheet`, `GlobalSheetPage`,
  `CalendarDatePicker`, or `CupertinoDatePicker`. The `Confirmar` button in
  `TaskMetadataTimePage` receives its control haptic from `AppButton`.

- [ ] **Step 4: Run the focused sheet tests to verify they pass**

  ```powershell
  flutter test test/shared/widgets/global_sheet_test.dart test/features/tasks/presentation/widgets/task_metadata_sheet_test.dart test/features/tasks/presentation/widgets/task_metadata_date_page_test.dart
  ```

  Expected: PASS. Internal page close must return to the root page, and root
  close must still resolve the sheet future.

- [ ] **Step 5: Commit the sheet changes**

  ```powershell
  git add lib/shared/widgets/global_sheet_header.dart lib/features/tasks/presentation/widgets/task_metadata_sheet.dart test/shared/widgets/global_sheet_test.dart test/features/tasks/presentation/widgets/task_metadata_sheet_test.dart test/features/tasks/presentation/widgets/task_metadata_date_page_test.dart
  git commit -m "feat(haptics): cover task metadata sheets"
  ```

### Task 4: Add feedback to the emoji and icon sheets

**Files:**

- Modify: `lib/features/notes/catalog/presentation/widgets/note_icon_picker.dart`
- Modify: `lib/features/notes/catalog/presentation/widgets/note_icon_picker_components.dart`
- Modify: `test/features/notes/catalog/presentation/widgets/note_icon_picker_test.dart`

**Interfaces:**

- Consumes `AppHaptics` from Task 1 and the shared sheet header from Task 2.
- Keeps `NoteIcon` creation, `onSelected`, and `FamilyModalSheet` page
  navigation unchanged.
- Produces one haptic only for the action or value selected by the user.

- [ ] **Step 1: Add failing picker interaction assertions**

  Extend `note_icon_picker_test.dart` with these cases:

  - Tapping `Usar emoji` emits one control-tap haptic and opens
    `Escolher emoji`.
  - Tapping an emoji semantics target emits one selection haptic and calls
    `onSelected` with an emoji icon.
  - Tapping a different color emits one selection haptic and changes the
    selected color.
  - Tapping the already selected color emits no additional selection haptic.
  - Tapping a catalog icon emits one selection haptic and calls `onSelected`.

  Keep the existing fixed-header and grid-only-scroll assertions.

- [ ] **Step 2: Run the picker tests to verify they fail**

  ```powershell
  flutter test test/features/notes/catalog/presentation/widgets/note_icon_picker_test.dart
  ```

  Expected: existing layout assertions pass and the new haptic assertions
  fail.

- [ ] **Step 3: Implement feedback at each picker control**

  In `_PickerAction`, emit `AppHaptics.controlTap()` before the supplied
  callback. This covers page navigation and `Remover ícone`.

  In the emoji grid and catalog icon grid, emit
  `AppHaptics.selectionChange()` immediately before calling `onSelected`.
  In the color row, emit it only when `key != _colorKey`, then update state.

  Keep `AppInput.onChanged` and `CustomScrollView` without haptics. Do not
  add a second pulse in `_select`, `showNoteIconPicker`, or
  `GlobalSheetPage`.

- [ ] **Step 4: Run the picker tests to verify they pass**

  ```powershell
  flutter test test/features/notes/catalog/presentation/widgets/note_icon_picker_test.dart
  ```

  Expected: PASS, including callback results, selected color state, and
  scroll-boundary tests.

- [ ] **Step 5: Commit the picker changes**

  ```powershell
  git add lib/features/notes/catalog/presentation/widgets/note_icon_picker.dart lib/features/notes/catalog/presentation/widgets/note_icon_picker_components.dart test/features/notes/catalog/presentation/widgets/note_icon_picker_test.dart
  git commit -m "feat(haptics): cover emoji and icon pickers"
  ```

### Task 5: Normalize existing editor feedback and long press ownership

**Files:**

- Modify: `lib/features/notes/editor/presentation/widgets/custom_task_component.dart`
- Modify: `lib/features/notes/editor/presentation/widgets/note_toolbar.dart`
- Modify: `test/features/notes/presentation/widgets/note_toolbar_test.dart`

**Interfaces:**

- Replaces direct platform calls with `AppHaptics`.
- Keeps editor operations, completion persistence, and toolbar commands
  unchanged.
- Makes `CustomTaskComponent` the only owner of the accepted touch long-press
  feedback.

- [ ] **Step 1: Add regression assertions for existing editor actions**

  In the existing editor harness, add these cases:

  - Tap one formatting/list command and assert the recorder sees one
    `HapticFeedbackType.selectionClick` call.
  - Tap the task checkbox semantics action `Concluir tarefa` and assert one
    selection haptic while the task state changes as before.
  - Long-press the task checkbox and assert the task metadata callback is
    invoked once. On a physical device, verify that exactly one long-press
    pulse is perceptible.

- [ ] **Step 2: Run the editor tests to verify the new feedback assertions fail**

  ```powershell
  flutter test test/features/notes/presentation/widgets/note_toolbar_test.dart
  ```

  Expected: existing editor behavior passes and the new channel assertions
  fail until the direct calls are routed through the shared boundary.

- [ ] **Step 3: Replace direct calls and move long-press ownership**

  In `custom_task_component.dart`:

  - Replace completion/reopen `HapticFeedback.lightImpact()` with
    `AppHaptics.selectionChange()`.
  - Remove the builder-level `HapticFeedback.mediumImpact()` call.
  - Add a `CustomTaskComponent` state callback that calls
    `AppHaptics.longPress(context)` once, then invokes `widget.onLongPress`.
  - Use that callback for the touch `GestureDetector.onLongPress`. Keep the
    desktop `onSecondaryTap` callback without mobile haptic feedback.

  In `note_toolbar.dart`, replace every direct
  `HapticFeedback.selectionClick()` call with `AppHaptics.selectionChange()`.
  Remove the now-unused `flutter/services.dart` import if no other symbol
  from that library remains in the file.

- [ ] **Step 4: Run the editor tests to verify they pass**

  ```powershell
  flutter test test/features/notes/presentation/widgets/note_toolbar_test.dart
  ```

  Expected: PASS with one feedback owner per editor gesture.

- [ ] **Step 5: Commit the editor normalization**

  ```powershell
  git add lib/features/notes/editor/presentation/widgets/custom_task_component.dart lib/features/notes/editor/presentation/widgets/note_toolbar.dart test/features/notes/presentation/widgets/note_toolbar_test.dart
  git commit -m "refactor(haptics): centralize editor feedback"
  ```

### Task 6: Run full verification and physical-device checks

**Files:**

- Modify: `walkthrough.md` after implementation with the final behavior and
  validation evidence.

- [ ] **Step 1: Format all changed Dart files**

  ```powershell
  dart format lib/core/utils/app_haptics.dart lib/shared/widgets/app_button.dart lib/shared/widgets/app_icon_button.dart lib/shared/widgets/app_selection_tile.dart lib/shared/widgets/confirm_dialog.dart lib/shared/widgets/global_sheet_header.dart lib/features/tasks/presentation/widgets/task_metadata_sheet.dart lib/features/notes/catalog/presentation/widgets/note_icon_picker.dart lib/features/notes/catalog/presentation/widgets/note_icon_picker_components.dart lib/features/notes/editor/presentation/widgets/custom_task_component.dart lib/features/notes/editor/presentation/widgets/note_toolbar.dart test/helpers/haptic_test_helper.dart test/core/utils/app_haptics_test.dart test/shared/widgets/app_button_test.dart test/shared/widgets/app_icon_button_test.dart test/shared/widgets/app_selection_tile_test.dart test/shared/widgets/confirm_dialog_test.dart test/shared/widgets/global_sheet_test.dart test/features/tasks/presentation/widgets/task_metadata_sheet_test.dart test/features/tasks/presentation/widgets/task_metadata_date_page_test.dart test/features/notes/catalog/presentation/widgets/note_icon_picker_test.dart test/features/notes/presentation/widgets/note_toolbar_test.dart
  ```

- [ ] **Step 2: Run focused and project checks**

  ```powershell
  flutter test test/core/utils/app_haptics_test.dart test/shared/widgets/app_button_test.dart test/shared/widgets/app_icon_button_test.dart test/shared/widgets/app_selection_tile_test.dart test/shared/widgets/confirm_dialog_test.dart test/shared/widgets/global_sheet_test.dart test/features/tasks/presentation/widgets/task_metadata_sheet_test.dart test/features/tasks/presentation/widgets/task_metadata_date_page_test.dart test/features/notes/catalog/presentation/widgets/note_icon_picker_test.dart test/features/notes/presentation/widgets/note_toolbar_test.dart
  flutter analyze
  rg -n "HapticFeedback|Feedback\.forLongPress" lib
  ```

  Expected: focused tests and analyzer pass. The search must show direct
  platform calls only in `lib/core/utils/app_haptics.dart` and no remaining
  editor-level direct calls.

- [ ] **Step 3: Verify on a physical iPhone and Android device**

  Check this matrix manually:

  - Task sheet: open row, clear row, select quick date, select recurrence,
    confirm time, close child page, close root page.
  - Emoji/icon sheet: open action, select emoji, change color, tap the same
    color, select icon, remove icon, close child/root page.
  - Editor: complete/reopen task, long-press task checkbox, use one toolbar
    command.
  - Negative cases: type in search, scroll the picker grid, scroll the time
    wheel, drag/dismiss the sheet, and tap a disabled/loading button.

  Expected: one short pulse for each positive action, no pulse for negative
  cases, no duplicate pulse from the calendar/time wheels, and all behavior
  remains usable with system haptics disabled.

- [ ] **Step 4: Record the final verification**

  Update `walkthrough.md` with the focused test command, analyzer result,
  physical-device matrix, and any platform difference observed. Do not record
  a device result that was not tested.

- [ ] **Step 5: Run the final diff review**

  ```powershell
  git diff --check
  git status --short
  ```

  Confirm that only the haptic implementation, its tests, and the requested
  documentation changed. Do not commit unrelated existing worktree changes.

## Acceptance criteria

- `AppButton`, `AppIconButton`, and task selection controls provide default
  feedback without feature-level haptic code for their normal paths.
- Every actionable control listed in the task and emoji/icon sheet inventory
  has the intended feedback owner.
- The root sheet route, sheet drag, search, scroll, and native picker wheels do
  not receive custom haptics.
- A selection that is already active does not produce a new selection pulse.
- Long press has one owner and does not combine the old medium impact with the
  new platform gesture feedback.
- Existing haptic calls are centralized in `AppHaptics`.
- No dependency, persistence, synchronization, or modal navigation change is
  required.
- Focused tests, `flutter analyze`, `git diff --check`, and the physical-device
  checks pass before implementation is reported complete.

## References

- [Apple HIG — Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)
- [Apple UIFeedbackGenerator](https://developer.apple.com/documentation/uikit/uifeedbackgenerator)
- [Flutter HapticFeedback](https://api.flutter.dev/flutter/services/HapticFeedback-class.html)
- [Flutter Feedback.forLongPress](https://api.flutter.dev/flutter/widgets/Feedback/forLongPress.html)
- [Android haptics design principles](https://developer.android.com/develop/ui/views/haptics/haptics-principles)
- [Android event haptic feedback](https://developer.android.com/develop/ui/views/haptics/haptic-feedback)
