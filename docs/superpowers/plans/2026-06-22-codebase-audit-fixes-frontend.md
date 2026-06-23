# Codebase Audit Fixes (Frontend) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve technical debt, Riverpod violations, visual structure violations, and synchronization issues in the Flutter frontend as reported in the codebase audit.

**Architecture:** 
- Shared components (`AppMessenger`, `AppButton`) will be unified and extended.
- Native buttons and local dialogs will be replaced with global application components.
- Screens will be migrated to the standard `CustomScrollView` + `SliverAppBar` structure.
- State management will strictly follow `AsyncValue.when` and `.autoDispose`.

**Tech Stack:** Flutter, Dart, Riverpod.

---

### Task 1: Unify Snackbars (AppMessenger)

**Files:**
- Modify: `lib/features/routines/presentation/widgets/brief_schedule_card.dart`
- Delete: `lib/shared/widgets/error_snackbar.dart`

- [ ] **Step 1: Update brief_schedule_card.dart imports and usage**

Modify `lib/features/routines/presentation/widgets/brief_schedule_card.dart`. Replace the `error_snackbar.dart` import with `app_snackbar.dart` and replace `showErrorSnackBar` with `AppMessenger.showError`:

```dart
// Remove this line:
// import '../../../../shared/widgets/error_snackbar.dart';
// Add this line:
import '../../../../shared/widgets/app_snackbar.dart';

// Find the call to showErrorSnackBar and replace it with AppMessenger.showError:
/*
      if (mounted) {
        AppMessenger.showError(
          context,
          'Falha ao gerar rotina.',
          onRetry: _testRoutine,
        );
      }
*/
```

- [ ] **Step 2: Delete error_snackbar.dart**

Run: `rm lib/shared/widgets/error_snackbar.dart`
Expected: File deleted.

- [ ] **Step 3: Commit**

```bash
git add lib/features/routines/presentation/widgets/brief_schedule_card.dart lib/shared/widgets/error_snackbar.dart
git commit -m "refactor(ui): unify error snackbars using AppMessenger and delete error_snackbar"
```

---

### Task 4: Fix Note Editor Sync Local Leak

**Files:**
- Modify: `lib/features/notes/presentation/widgets/note_editor.dart`

- [ ] **Step 1: Add didUpdateWidget to NoteEditor state**

Modify `lib/features/notes/presentation/widgets/note_editor.dart`. When a background sync happens, the parent passes a new `content` string, but the `_NoteEditorState` currently ignores it if already initialized.

```dart
  @override
  void didUpdateWidget(NoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.content != oldWidget.content && widget.content != _editor.document.text) {
      // Create a new document with the updated text from the server/sync
      _editor = MutableDocument.empty(); // Wait, using super_editor, you must replace the document nodes.
      // Alternatively, re-initialize the document
      _initializeDocument(widget.content);
    }
  }
```
*(Agent Note: check `note_editor.dart` for the exact `super_editor` document initialization logic and apply it).*

- [ ] **Step 2: Commit**

```bash
git add lib/features/notes/presentation/widgets/note_editor.dart
git commit -m "fix(sync): update note editor document when widget content changes from background sync"
```

---

### Task 5: Riverpod Compliance (AutoDispose & AsyncValue.when)

**Files:**
- Modify: `lib/features/settings/presentation/controllers/contexts_controller.dart`
- Modify: `lib/features/notes/presentation/inbox_screen.dart`
- Modify: `lib/features/notes/presentation/note_editor_screen.dart`

- [ ] **Step 1: Add autoDispose to contextsProvider**

Modify `lib/features/settings/presentation/controllers/contexts_controller.dart`:
```dart
// Change:
final contextsProvider = FutureProvider<List<ContextModel>>((ref) async {
// To:
final contextsProvider = FutureProvider.autoDispose<List<ContextModel>>((ref) async {
```

- [ ] **Step 2: Fix inbox_screen.dart AsyncValue.when**

Modify `lib/features/notes/presentation/inbox_screen.dart`. Find the `build` method where it manually checks `if (asyncValue.isLoading)`. Replace with:

```dart
    return asyncValue.when(
      data: (data) => _InboxBody(data: data),
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stack) => Scaffold(body: Center(child: Text('Erro: $error'))),
    );
```
*(Create the `_InboxBody` stateless widget if needed to extract the body).*

- [ ] **Step 3: Fix note_editor_screen.dart AsyncValue.when**

Modify `lib/features/notes/presentation/note_editor_screen.dart`. Similarly, replace `asData?.value` with proper `.when` usage.

- [ ] **Step 4: Commit**

```bash
git add lib/features/settings/presentation/controllers/contexts_controller.dart lib/features/notes/presentation/inbox_screen.dart lib/features/notes/presentation/note_editor_screen.dart
git commit -m "fix(riverpod): enforce autoDispose and AsyncValue.when usage"
```

---

### Task 6: Visual Layout Compliance (CustomScrollView)

**Files:**
- Modify: `lib/features/routines/presentation/routines_screen.dart`
- Modify: `lib/features/settings/presentation/soul_editor_screen.dart`

- [ ] **Step 1: Restructure routines_screen.dart**

Modify `lib/features/routines/presentation/routines_screen.dart` to use `CustomScrollView`:
```dart
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar.medium(title: Text('Rotinas')),
          SliverPadding(
            padding: const EdgeInsets.all(16.0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Existing body content
              ]),
            ),
          ),
        ],
      ),
    );
```

- [ ] **Step 2: Restructure soul_editor_screen.dart and remove Visual Mode**

Modify `lib/features/settings/presentation/soul_editor_screen.dart`.
- Remove the toggle for visual mode vs editing mode (force editing mode).
- Extract `_buildBody`, `_buildHeader`, etc., into private `StatelessWidget` classes (`_SoulHeader`, `_SoulForm`).
- Change the `Scaffold` to use `CustomScrollView` + `SliverAppBar.medium`.
- Move the footer actions to the `bottomNavigationBar` of the `Scaffold`.

- [ ] **Step 3: Commit**

```bash
git add lib/features/routines/presentation/routines_screen.dart lib/features/settings/presentation/soul_editor_screen.dart
git commit -m "refactor(ui): update screens to use CustomScrollView and extract private widgets"
```
