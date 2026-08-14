# Contextual note toolbar design

## Goal

Replace the formatting panel with one floating note toolbar.

The toolbar stays docked above the software keyboard. It changes its actions
from the current document selection and block type. The editor keeps the caret
visible above the toolbar and keyboard.

## Layout

`KeyboardScaffoldSafeArea` wraps the screen. The screen `Scaffold` keeps
`resizeToAvoidBottomInset: false`. `KeyboardPanelScaffold` owns the floating
toolbar position and reports the toolbar and keyboard insets to the safe area.

The editor stays in the scaffold content builder. It uses the height that
remains above the toolbar and the software keyboard. It does not extend under
the toolbar. This is the supported Super Editor layout and lets its native
scroll behavior keep the selected caret in the visible viewport.

The toolbar material is translucent. It looks like it floats over the note,
but the document does not scroll into the area that can hide the caret.

There is no formatting panel, formatting `Aa` action, panel enum, or panel
switching behavior.

## Toolbar states

The toolbar has one stable container, position, and height.

### Normal state

Use this state when the selection is collapsed in a paragraph, heading,
blockquote, divider, image, or attachment.

Actions, in order:

1. Heading 1, Heading 2, Heading 3, and block quote.
2. Insert divider.
3. Attach image and attach file.

### Contextual state

Use this state when the selection spans text, or when its collapsed caret is
inside a list item or task.

Actions, in order:

1. Bold, italic, and strikethrough.
2. Bulleted list, numbered list, and task.
3. Outdent and indent.

The inline actions are disabled for a collapsed selection. List conversion is
available for selected text and collapsed text blocks. Outdent and indent are
enabled only when the active node is a list item or task.

The existing `NoteEditorCommands` remain the only command path. This keeps
REST/OT operation capture and document metadata unchanged.

## Transition

`motor` animates only the toolbar content. The outer toolbar container does
not move or resize.

When the state changes, outgoing controls reduce opacity and scale down
slightly. Incoming controls enter with opacity, scale, and a short horizontal
translation. The transition uses a project standard effects spring and honors
`MediaQuery.disableAnimations`.

Each action keeps its semantic label. During a transition, only the current
action set is reachable by semantics and hit testing.

## Keyboard and navigation

The editor stays connected to the IME. Tapping or moving the caret continues
to use normal Super Editor selection and scrolling behavior. There is no
custom keyboard hide/show flow and no custom caret scrolling policy.

The toolbar is visible while the software keyboard is open. The screen uses
the Super Editor safe-area contract so the editor viewport excludes the
toolbar and keyboard.

## Validation

Widget tests must cover:

1. The correct action set for paragraph, text selection, list, and task.
2. Bold, italic, strikethrough, list, task, indent, and outdent command paths.
3. Disabled state for inline actions with a collapsed selection and for
   indentation outside lists and tasks.
4. The toolbar keeps one outer container while its content transitions.
5. Keyboard inset geometry: the editor viewport and caret stay above the
   toolbar on Android and iOS test platforms.

Manual validation on Android and iOS is required before release because real
IME animation and viewport metrics are platform behavior.
