# Plan 021: Extract shared NoteEditor widget and deduplicate screens

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 4639d85..HEAD -- lib/features/notes/presentation/note_editor_screen.dart lib/features/notes/presentation/inbox_screen.dart lib/features/notes/presentation/controllers/note_editor_controller.dart test/features/notes/presentation/note_editor_screen_test.dart`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: 019, 020
- **Category**: tech-debt
- **Planned at**: commit `4639d85`, 2026-06-15
- **Issue**: (none)

## Why this matters

`note_editor_screen.dart` and `inbox_screen.dart` duplicate ~180 lines of editor setup: controller creation, iOS/Android controls initialization, `SuperEditor` configuration, toolbar, keyboard padding, and task action handling. Any bug fix or visual tweak must be applied twice. Extracting a shared `NoteEditor` widget that owns the editor surface lets each screen focus only on how it obtains the note and what chrome surrounds the editor.

## Current state

- `lib/features/notes/presentation/note_editor_screen.dart` (231 lines)
  - Creates controller, iOS/Android controls, rich ops.
  - Injects title as H1 into content.
  - Watches `noteProvider(noteId)` and `tasksByNoteStreamProvider(noteId)`.
- `lib/features/notes/presentation/inbox_screen.dart` (259 lines)
  - Same controller/control setup as above.
  - Watches `inboxProvider`.
  - Has `_buildOrganizeFab` and no empty-note exit callback.
- `lib/features/notes/presentation/controllers/note_editor_controller.dart` (249 lines)
  - Owns document/composer/editor/focusNode and save throttle.
  - Has `SnapshotSave`/`EmptyNoteExit` typedefs.

Repo conventions:
- State management: Riverpod 3.x, manual providers, `.autoDispose` by default.
- Widgets: `snake_case.dart`, UI logic out of widgets when possible.

## Commands you will need

| Purpose   | Command | Expected on success |
|-----------|---------|---------------------|
| Analyze   | `flutter analyze lib/features/notes` | no issues |
| Tests     | `flutter test test/features/notes/presentation/note_editor_screen_test.dart` | all pass |
| Tests     | `flutter test test/features/notes/presentation/notes_list_screen_test.dart` | all pass |
| Tests     | `flutter test test/features/notes` | all pass |
| Tests     | `flutter test` | all pass |

## Suggested executor toolkit

- Use `flutter-add-widget-test` skill for new widget tests.
- Review Riverpod 3.x conventions in `RIVERPOD.md` and existing manual providers.

## Scope

**In scope**:
- `lib/features/notes/presentation/widgets/note_editor.dart` — create
- `lib/features/notes/presentation/note_editor_screen.dart` — rewrite to use `NoteEditor`
- `lib/features/notes/presentation/inbox_screen.dart` — rewrite to use `NoteEditor`
- `lib/features/notes/presentation/controllers/note_editor_controller.dart` — simplify if needed
- `test/features/notes/presentation/note_editor_screen_test.dart` — update

**Out of scope**:
- Refactoring `NoteToolbar` (plan 022).
- Changing the serializer (plan 018).
- Changing task/divider components (plans 019/020).
- Changing navigation routes or screen arguments.

## Git workflow

- Branch: `feat/021-shared-note-editor-widget`
- Commit per step; messages like `refactor(notes): extract shared NoteEditor widget`, `refactor(notes): simplify NoteEditorScreen`, `refactor(notes): simplify InboxScreen`.
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Design the shared `NoteEditor` widget API

Create `lib/features/notes/presentation/widgets/note_editor.dart` with the following public shape:

```dart
class NoteEditor extends ConsumerStatefulWidget {
  const NoteEditor({
    super.key,
    required this.noteId,
    required this.content,
    this.title,
    required this.taskMetadata,
    required this.snapshotSave,
    this.emptyNoteExit,
    this.onTaskLongPress,
  });

  final String noteId;
  final String content;
  final String? title;
  final Map<String, TaskModel> taskMetadata;
  final SnapshotSave snapshotSave;
  final EmptyNoteExit? emptyNoteExit;
  final ValueChanged<String>? onTaskLongPress;

  @override
  ConsumerState<NoteEditor> createState() => _NoteEditorState();
}
```

This widget owns:
- `NoteEditorController` lifecycle.
- iOS/Android controls.
- `RichCommonEditorOperations`.
- `SuperEditor` + `NoteToolbar` + keyboard padding.

Move all the duplicated setup code from both screens into `_NoteEditorState`.

### Step 2: Move editor setup into `NoteEditor`

Copy the common setup from both screens into `NoteEditor`:

```dart
class _NoteEditorState extends ConsumerState<NoteEditor> {
  NoteEditorController? _controller;
  final _docLayoutKey = GlobalKey();
  SuperEditorIosControlsController? _iosController;
  SuperEditorAndroidControlsController? _androidController;
  RichCommonEditorOperations? _richOps;

  NoteEditorController _controllerOrCreate() {
    if (_controller != null) return _controller!;
    return _controller = NoteEditorController(
      snapshotSave: widget.snapshotSave,
      emptyNoteExit: widget.emptyNoteExit,
    );
  }

  @override
  void dispose() {
    _iosController?.dispose();
    _androidController?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controllerOrCreate();
    controller.bind(widget.noteId);

    if (controller.document == null) {
      var content = widget.content;
      if (widget.title != null && widget.title!.isNotEmpty) {
        final title = widget.title!.trim();
        final startsWithH1Title = content.trimLeft().startsWith('# $title') ||
            content.trimLeft().startsWith('#  $title');
        if (!startsWithH1Title) {
          content = '# $title\n\n$content';
        }
      }
      controller.init(content: content);
    }

    if (controller.document == null || controller.editor == null || controller.composer == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final editorControlsColor = Theme.of(context).colorScheme.primary;

    _richOps ??= RichCommonEditorOperations(
      editor: controller.editor!,
      document: controller.editor!.document,
      composer: controller.composer!,
      documentLayoutResolver: () => _docLayoutKey.currentState as DocumentLayout,
    );

    _iosController ??= RichSuperEditorIosControlsController(
      editor: controller.editor!,
      documentLayoutResolver: () => _docLayoutKey.currentState as DocumentLayout,
      operations: _richOps!,
      handleColor: editorControlsColor,
    );

    _androidController ??= SuperEditorAndroidControlsController(
      controlsColor: editorControlsColor,
      toolbarBuilder: (overlayContext, mobileToolbarKey, focalPoint) =>
          defaultAndroidEditorToolbarBuilder(
            overlayContext,
            mobileToolbarKey,
            _richOps!,
            SuperEditorAndroidControlsScope.rootOf(overlayContext),
            controller.composer!.selectionNotifier,
            focalPoint,
          ),
    );

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                SuperEditorAndroidControlsScope(
                  controller: _androidController!,
                  child: SuperEditorIosControlsScope(
                    controller: _iosController!,
                    child: SuperEditor(
                      editor: controller.editor!,
                      focusNode: controller.focusNode,
                      documentLayoutKey: _docLayoutKey,
                      stylesheet: noteStylesheet(context),
                      keyboardActions: buildRichKeyboardActions(
                        baseActions: defaultTargetPlatform == TargetPlatform.iOS ||
                                defaultTargetPlatform == TargetPlatform.android
                            ? defaultImeKeyboardActions
                            : defaultKeyboardActions,
                      ),
                      componentBuilders: [
                        const CustomDividerComponentBuilder(),
                        ...defaultComponentBuilders,
                        CustomTaskComponentBuilder(
                          controller.editor!,
                          focusNode: controller.focusNode,
                          taskMetadataById: widget.taskMetadata,
                          onTaskLongPress: widget.onTaskLongPress,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          NoteToolbar(editor: controller.editor!, composer: controller.composer!),
        ],
      ),
    );
  }
}
```

**Verify**: `flutter analyze lib/features/notes/presentation/widgets/note_editor.dart` → no issues.

### Step 3: Rewrite `NoteEditorScreen` to use `NoteEditor`

`NoteEditorScreen` should become:

```dart
class NoteEditorScreen extends ConsumerStatefulWidget {
  final String noteId;
  const NoteEditorScreen({super.key, required this.noteId});

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  @override
  Widget build(BuildContext context) {
    final asyncValue = ref.watch(noteProvider(widget.noteId));
    final tasksAsync = ref.watch(tasksByNoteStreamProvider(widget.noteId));
    final tasksMap = tasksAsync.asData?.value != null
        ? {for (final t in tasksAsync.asData!.value) t.id: t}
        : const <String, TaskModel>{};

    if (asyncValue.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (asyncValue.hasError) {
      return Scaffold(body: Center(child: Text('Error: ${asyncValue.error}')));
    }
    final note = asyncValue.asData?.value;
    if (note == null) {
      return const Scaffold(body: Center(child: Text('Nota nao encontrada')));
    }

    final repo = ref.read(notesRepositoryProvider);
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () => FocusManager.instance.primaryFocus?.unfocus(),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: NoteEditor(
          noteId: widget.noteId,
          content: note.content,
          title: note.title,
          taskMetadata: tasksMap,
          snapshotSave: (noteId, title, markdown, tasks) =>
              defaultSnapshotSave(repo, noteId, title, markdown, tasks),
          emptyNoteExit: (noteId) => defaultEmptyNoteExit(repo, noteId),
          onTaskLongPress: (taskId) => _openTaskActions(context, taskId),
        ),
      ),
    );
  }

  Future<void> _openTaskActions(BuildContext context, String taskId) async {
    // This method needs the controller to flush. Consider moving flush into NoteEditor via callback.
    // For now, keep the existing flow by exposing a controller from NoteEditor or use a provider.
  }
}
```

**Problem**: `_openTaskActions` currently calls `controller.persistSnapshotNow()` and then reads fresh tasks. The screen no longer owns the controller.

**Solution**: Expose a `Future<void> Function()? onBeforeTaskActions` or a `GlobalKey<NoteEditorState>` to flush. Simpler: add a callback `Future<void> Function()? flushSnapshot` to `NoteEditor` and a public method on `_NoteEditorState`:

```dart
class NoteEditor extends ConsumerStatefulWidget {
  ...
  final void Function(String taskId, Future<void> Function() flushSnapshot)? onTaskLongPress;
}
```

Then `_NoteEditorState` passes a closure that flushes:

```dart
CustomTaskComponentBuilder(
  controller.editor!,
  focusNode: controller.focusNode,
  taskMetadataById: widget.taskMetadata,
  onTaskLongPress: widget.onTaskLongPress == null
      ? null
      : (taskId) => widget.onTaskLongPress!(taskId, controller.persistSnapshotNow),
)
```

And `NoteEditorScreen._openTaskActions` becomes:

```dart
Future<void> _openTaskActions(BuildContext context, String taskId, Future<void> Function() flushSnapshot) async {
  await flushSnapshot();
  if (!mounted) return;

  ref.invalidate(tasksByNoteStreamProvider(widget.noteId));
  final freshTasks = await ref.read(tasksByNoteStreamProvider(widget.noteId).future);
  final freshMap = {for (final t in freshTasks) t.id: t};
  final task = freshMap[taskId];
  if (task == null || !mounted) return;

  await TaskActionsSheet.show(context, task: task);
}
```

**Verify**: `flutter analyze lib/features/notes/presentation/note_editor_screen.dart` → no issues.

### Step 4: Rewrite `InboxScreen` to use `NoteEditor`

`InboxScreen` should become similar to `NoteEditorScreen` but:
- Watches `inboxProvider`.
- Does not pass `emptyNoteExit`.
- Has the organize FAB.
- Uses `_openTaskActions` with the same flush callback.

Keep `initState` that calls `ensureInbox()`.

**Verify**: `flutter analyze lib/features/notes/presentation/inbox_screen.dart` → no issues.

### Step 5: Simplify `NoteEditorController` if possible

Now that screens no longer reach into the controller directly, consider:

- Removing `focusNode` exposure if not needed externally (it is still passed to `SuperEditor`).
- Keeping `snapshotSave`/`emptyNoteExit` typedefs where they are — they are used by `NoteEditor`.

Do not over-refactor in this plan; the controller is out of scope beyond what is needed for the new widget.

### Step 6: Update tests

Update `test/features/notes/presentation/note_editor_screen_test.dart`:

- The test that was skipped (`skip: true`) can now be enabled if the shared widget handles stream refreshes correctly. If enabling it still fails, document why and leave it skipped.
- Update expectations if the widget tree changed (e.g., `SuperEditorAndroidControlsScope` may now be inside `NoteEditor`).

Add a new test for `NoteEditor` widget in isolation (optional but recommended):

- Renders `SuperEditor` and `NoteToolbar` when given content.

**Verify**: `flutter test test/features/notes/presentation/note_editor_screen_test.dart` → all pass.

### Step 7: Run regression suite

**Verify**:
- `flutter test test/features/notes/presentation/notes_list_screen_test.dart` → all pass.
- `flutter test test/features/notes` → all pass.
- `flutter test` → all pass.
- `flutter analyze` → no issues.

## Test plan

- Update `note_editor_screen_test.dart` to match the new widget tree.
- Optionally create `test/features/notes/presentation/widgets/note_editor_test.dart` for the shared widget.
- Keep `inbox_screen` integration behavior covered by existing tests or manual verification.

## Done criteria

- [ ] `lib/features/notes/presentation/widgets/note_editor.dart` exists and contains the shared editor surface.
- [ ] `NoteEditorScreen` is reduced to screen chrome + `NoteEditor`.
- [ ] `InboxScreen` is reduced to screen chrome + `NoteEditor` + FAB.
- [ ] No duplicated `SuperEditor`/controls/toolbar setup remains in either screen.
- [ ] `flutter analyze lib/features/notes` exits 0.
- [ ] `flutter test test/features/notes/presentation/note_editor_screen_test.dart` exits 0.
- [ ] `flutter test test/features/notes` exits 0.
- [ ] `flutter test` exits 0.
- [ ] `plans/README.md` status row for plan 021 updated to DONE.

## STOP conditions

Stop and report if:
- The task-actions flush callback cannot be wired without making the screens own the controller again.
- `NoteEditor` rebuilds on every `tasksByNoteStreamProvider` emission and loses editor focus.
- Enabling the previously skipped `note_editor_screen_test` fails for a reason that requires changing the shared widget architecture.

## Maintenance notes

- Future editor visual changes should only touch `NoteEditor`.
- Future screen-specific changes (app bar, FAB, route arguments) should only touch the screen files.
- Reviewers should verify that `InboxScreen` and `NoteEditorScreen` still save/flush correctly on dispose and that the organize FAB still appears only when the inbox has content.
