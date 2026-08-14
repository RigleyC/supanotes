# Note Editor Keyboard and Toolbar Design

## Goal

Use the keyboard layout infrastructure supplied by the pinned Super Editor dependency to give the note editor one owner for the editor viewport, compact toolbar, software keyboard, and formatting panel.

## Scope

This change covers only the editable note screen layout and interaction between:

- the note AppBar;
- the `SuperEditor` viewport;
- the compact note toolbar;
- the software keyboard;
- the full formatting panel.

It does not change document data, task behavior, synchronization, attachments, or formatting commands.

## Architecture

The note screen will use `KeyboardScaffoldSafeArea` around a `Scaffold`. The `Scaffold` will set `resizeToAvoidBottomInset: false`, as required by `KeyboardPanelScaffold`.

The AppBar will remain outside the editor viewport. The body will not extend behind the AppBar. The AppBar can own its background treatment, but the editor viewport will not use transparency or layout extension to create that effect.

The body will contain `KeyboardPanelScaffold<NoteEditorPanel>`. It will be the only component that interprets keyboard height and divides the available vertical space:

- `contentBuilder` builds the editor content and suggestion overlay;
- `toolbarBuilder` builds the compact `NoteToolbar`;
- `keyboardPanelBuilder` builds the formatting panel in place of the software keyboard.

The `SuperEditor` will continue to receive the existing `SoftwareKeyboardController`, focus node, editor, composer, component builders, overlay builders, and IME policies. It will receive the IME connection signal required by `KeyboardPanelScaffold`.

## Toolbar Responsibilities

`NoteToolbar` will keep the compact actions:

- open formatting;
- insert divider;
- attach image;
- attach file.

It will no longer:

- read `MediaQuery.viewInsets`;
- hide or reopen the software keyboard;
- preserve and restore focus around formatting mode;
- expand into the full formatting interface;
- own back-button behavior for the formatting panel.

Opening formatting will request the formatting panel through the parent-owned `KeyboardPanelController`.

## Formatting Panel

The existing formatting controls will move into a dedicated `NoteFormattingPanel` widget. It will preserve the current formatting capabilities and selection behavior:

- paragraph and heading types;
- bold, italic, and strikethrough;
- ordered, unordered, and task lists;
- indent and unindent;
- close and return to typing.

The selection used for formatting will be captured before switching away from the software keyboard. Formatting commands will continue to target that selection while the panel is open.

Closing the formatting panel through its close action or system back will return to the compact toolbar. The explicit return-to-typing action will show the software keyboard and restore editor focus. A general panel close does not open the keyboard unless the user requested a return to typing.

## Layout Behavior

When the keyboard is visible, the order is:

1. AppBar;
2. editor viewport using the remaining height;
3. compact toolbar;
4. software keyboard.

When the formatting panel is visible, it replaces the software keyboard:

1. AppBar;
2. editor viewport using the remaining height;
3. compact toolbar;
4. formatting panel.

When neither keyboard nor panel is visible, the compact toolbar remains at the bottom safe area.

The editor must receive its actual visible height in every state. Super Editor's native auto-scroll remains responsible for keeping the caret within that viewport.

## Visual Treatment

The editor will not be wrapped in a full-viewport opacity mask for the AppBar transition. Any fade, blur, or surface treatment at the top belongs to the AppBar layer and must not change editor geometry.

The compact toolbar keeps its current visual design. The formatting panel may reuse the existing formatting control styling, but it occupies the keyboard-panel area rather than expanding the compact toolbar.

## Ownership and State

The editor widget owns:

- `SoftwareKeyboardController`;
- `KeyboardPanelController<NoteEditorPanel>`;
- IME connection notifier;
- the active editor panel;
- the formatting selection snapshot.

`NoteToolbar` and `NoteFormattingPanel` receive typed callbacks and editing dependencies. They do not infer keyboard state from `MediaQuery` and do not manage keyboard geometry.

Only one panel type is required initially: `NoteEditorPanel.formatting`. No generic panel registry or speculative extension layer will be added.

## Error and Lifecycle Handling

Controllers and notifiers created by the editor will be disposed with the editor state. The software keyboard controller will be detached before disposal according to the Super Editor API.

Panel transitions must be safe when the editor becomes read-only, the route closes, or the widget is disposed. No delayed focus callback may access an unmounted context.

## Validation

Focused widget coverage will verify:

- the caret stays above the compact toolbar while typing on Android and iOS;
- the compact toolbar stays above the software keyboard;
- the formatting panel replaces the keyboard;
- opening the formatting panel preserves the selected range;
- formatting commands still change the captured selection;
- closing the panel through system back does not pop the note route;
- returning to typing restores editor focus and the software keyboard;
- the editor body starts below the AppBar with and without the keyboard;
- no manual toolbar padding depends on `MediaQuery.viewInsets`.

Existing toolbar command tests remain valid. Tests that depend on the old expanding-toolbar ownership will be migrated to the dedicated formatting panel.

## Non-goals

- No redesign of formatting commands.
- No change to note persistence or synchronization.
- No new dependency.
- No backward-compatible fallback to the manual keyboard layout.
- No full-screen editor content behind the AppBar.
