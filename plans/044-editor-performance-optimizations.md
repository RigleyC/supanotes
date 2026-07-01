# Plan 044: Editor Performance and Rendering Optimizations

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 2bc944a..HEAD -- lib/features/notes/presentation/widgets/note_editor.dart lib/features/notes/presentation/widgets/note_suggestion_overlay.dart lib/features/notes/presentation/widgets/note_suggestion_handler.dart`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: performance / tech-debt
- **Planned at**: commit `2bc944a`, 2026-07-01

## Why this matters

1. **Unnecessary Stylesheet Clones**: The `noteStylesheet` is constructed on every single keystroke/build of the editor, creating style rules and cloning maps. This causes layout re-evaluations and typing lag. Memoizing it improves typing latency.
2. **Keystroke Search Lag**: Typing `@` to search notes for autocomplete filters and sorts the entire list of active notes inside the widget `build` method. Memoizing this via a Riverpod provider family prevents sessional CPU spikes.
3. **Double Sync Transactions**: Suggestion inserts trigger two sequential `editor.execute` calls, causing two document update cycles and two database sync writes in quick succession. Batching them makes it atomic.

## Current state

- File: `lib/features/notes/presentation/widgets/note_editor.dart:234-237`
  ```dart
                        stylesheet: noteStylesheet(
                          context,
                          hideCompleted: widget.hideCompleted,
                        ),
  ```
- File: `lib/features/notes/presentation/widgets/note_suggestion_overlay.dart:113-120`
  ```dart
      final notesAsync = ref.watch(activeNotesProvider);
      return notesAsync.when(
        data: (notes) {
          final suggestions = notes
              .where((n) => n.id != widget.currentNoteId && n.title.toLowerCase().contains(match.query.toLowerCase()))
              .toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  ```
- File: `lib/features/notes/presentation/widgets/note_suggestion_handler.dart:13-48`
  ```dart
    editor.execute([
      DeleteContentRequest(...),
      InsertTextRequest(...),
    ]);

    editor.execute([
      ChangeSelectionRequest(...),
    ]);
  ```

## Commands you will need

| Purpose   | Command                              | Expected on success    |
|-----------|--------------------------------------|------------------------|
| Test      | `flutter test test/features/notes/presentation/widgets/note_editor_link_test.dart` | All pass |
| Test      | `flutter test test/features/notes/presentation/note_editor_screen_test.dart` | All pass |

---

## Scope

**In scope**:
- `lib/features/notes/presentation/widgets/note_editor.dart`
- `lib/features/notes/presentation/widgets/note_suggestion_overlay.dart`
- `lib/features/notes/presentation/widgets/note_suggestion_handler.dart`

**Out of scope**:
- Modifying `note_editor_controller.dart` or local database models.

---

## Steps

### Step 1: Memoize Stylesheet in NoteEditor State

Modify `_NoteEditorState` in `lib/features/notes/presentation/widgets/note_editor.dart` to cache the `Stylesheet` object.

Add the cache fields to `_NoteEditorState` (around line 58):
```dart
  Stylesheet? _cachedStylesheet;
  bool? _cachedHideCompleted;
  ColorScheme? _cachedColorScheme;
```

Modify the `build()` method (around line 210) to populate and reuse the cache:
```dart
  @override
  Widget build(BuildContext context) {
    final controller = _controller!;

    if (controller.document == null ||
        controller.editor == null ||
        controller.composer == null) {
      return const Center(child: CircularProgressIndicator());
    }

    _setupControls(context);

    final theme = Theme.of(context);
    if (_cachedStylesheet == null ||
        _cachedHideCompleted != widget.hideCompleted ||
        _cachedColorScheme != theme.colorScheme) {
      _cachedHideCompleted = widget.hideCompleted;
      _cachedColorScheme = theme.colorScheme;
      _cachedStylesheet = noteStylesheet(
        context,
        hideCompleted: widget.hideCompleted,
      );
    }
```

Then pass `_cachedStylesheet!` to the `SuperEditor` widget (around line 234):
```dart
                      stylesheet: _cachedStylesheet!,
```

**Verify**: Run `flutter test test/features/notes/presentation/note_editor_screen_test.dart` to confirm layout renders correctly.

---

### Step 2: Extract Suggestion Filtering to a Riverpod Provider

Create a memoized provider to filter and sort suggestions in `lib/features/notes/presentation/widgets/note_suggestion_overlay.dart`.

Add the provider at the top of the file:
```dart
final noteSuggestionsProvider = Provider.family.autoDispose<List<NoteModel>, String>((ref, query) {
  final notes = ref.watch(activeNotesProvider).valueOrNull ?? [];
  final lowercaseQuery = query.toLowerCase();
  return notes
      .where((n) => n.title.toLowerCase().contains(lowercaseQuery))
      .toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
});
```

Then modify `build()` in `_NoteSuggestionOverlayState` to consume it:
```dart
  @override
  Widget build(BuildContext context) {
    final match = _match;
    if (match == null) return const SizedBox.shrink();

    final suggestions = ref.watch(noteSuggestionsProvider(match.query));
    if (suggestions.isEmpty) return const SizedBox.shrink();

    final chips = suggestions.take(10).map((note) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: () => _onNoteSelected(note),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(
                note.title,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ),
      );
    }).toList();

    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        itemBuilder: (_, i) => chips[i],
      ),
    );
  }
```

**Verify**: Run `flutter test test/features/notes/presentation/widgets/note_editor_link_test.dart` to ensure autocomplete works.

---

### Step 3: Batch Selection and Content Edits Atomically

Bundle selection and content updates in `lib/features/notes/presentation/widgets/note_suggestion_handler.dart` inside a single transaction list.

Modify `applyNoteSuggestion` to call `editor.execute` once:
```dart
void applyNoteSuggestion({
  required Editor editor,
  required String nodeId,
  required int tagStartOffset,
  required int tagEndOffset,
  required NoteModel note,
  required void Function() onPersist,
}) {
  editor.execute([
    DeleteContentRequest(
      documentRange: DocumentRange(
        start: DocumentPosition(
          nodeId: nodeId,
          nodePosition: TextNodePosition(offset: tagStartOffset),
        ),
        end: DocumentPosition(
          nodeId: nodeId,
          nodePosition: TextNodePosition(offset: tagEndOffset),
        ),
      ),
    ),
    InsertTextRequest(
      documentPosition: DocumentPosition(
        nodeId: nodeId,
        nodePosition: TextNodePosition(offset: tagStartOffset),
      ),
      textToInsert: note.title,
      attributions: {LinkAttribution.fromUri(Uri.parse('note://${note.id}'))},
    ),
    ChangeSelectionRequest(
      DocumentSelection.collapsed(
        position: DocumentPosition(
          nodeId: nodeId,
          nodePosition: TextNodePosition(offset: tagStartOffset + note.title.length),
        ),
      ),
      SelectionChangeType.placeCaret,
      SelectionReason.userInteraction,
    ),
  ]);

  onPersist();
}
```

**Verify**: Run both test suites to guarantee total correctness.
```bash
flutter test test/features/notes/presentation/widgets/note_editor_link_test.dart
flutter test test/features/notes/presentation/note_editor_screen_test.dart
```

---

## Test plan

### Automated Verification
- Run tests:
```bash
flutter test test/features/notes/presentation/widgets/note_editor_link_test.dart
flutter test test/features/notes/presentation/note_editor_screen_test.dart
```
Expected: PASS

## Done criteria

- [ ] All widget and router tests pass.
- [ ] Linking suggestions chips render correctly when typing `@`.
- [ ] No double-save logs appear when selecting autocomplete suggestions.

## STOP conditions

- If `SuperEditor` selection crashes on incremental updates.
- If Riverpod notifier family fails to dispose FocusNode correctly.
