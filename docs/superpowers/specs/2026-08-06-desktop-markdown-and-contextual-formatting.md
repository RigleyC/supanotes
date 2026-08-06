# Desktop Markdown shortcuts and contextual formatting

## Problem Statement

The desktop note editor does not yet provide the writing flow expected from a
desktop rich-text editor.

Users want to type common Markdown markers and see the matching semantic
document structure immediately. For example, `# ` should create an H1 and a
list marker should create a list item. Users also want inline formatting
controls to appear automatically when they select text. They should not need
to open the existing general editor toolbar before applying italic, bold, or
strikethrough.

Tasks need the same fast input flow. Typing `[] ` should create an unchecked
task, and the standard Markdown form `- [ ] ` should create the same document
structure.

The feature is for the desktop editor. Mobile behavior remains unchanged in
this slice.

## Solution

Add two coordinated desktop editor capabilities:

1. A contextual formatting popover that appears automatically for an expanded
   text selection and follows the selected content. It exposes bold, italic,
   and strikethrough actions. It is separate from the persistent editor
   toolbar, which continues to expose document-level actions such as
   attachments and dividers.
2. Markdown-as-you-type conversion for the supported structural and inline
   shortcuts. Conversion removes the recognized marker and creates the
   corresponding semantic block or text attribution through the existing
   editor operation flow.

The canonical document remains the source of truth. A task shortcut creates a
`TaskNode`; it does not write directly to the relational task projection.

## User Stories

1. As a desktop note editor user, I want to type `# ` at the start of a line,
   so that the paragraph becomes an H1 without opening a menu.
2. As a desktop note editor user, I want to type `## ` at the start of a line,
   so that the paragraph becomes an H2.
3. As a desktop note editor user, I want to type `### ` at the start of a
   line, so that the paragraph becomes an H3.
4. As a desktop note editor user, I want to type `- ` at the start of a line,
   so that the paragraph becomes an unordered list item.
5. As a desktop note editor user, I want to type `* ` at the start of a line,
   so that the paragraph becomes an unordered list item.
6. As a desktop note editor user, I want to type `1. ` at the start of a line,
   so that the paragraph becomes an ordered list item.
7. As a desktop note editor user, I want to type `> ` at the start of a line,
   so that the paragraph becomes a blockquote.
8. As a desktop note editor user, I want to type `---` as a divider shortcut,
   so that the editor creates a horizontal rule using the existing document
   capability.
9. As a desktop note editor user, I want to type `[] ` at the start of a line,
   so that the editor creates an unchecked task.
10. As a desktop note editor user, I want to type `- [ ] ` at the start of a
    line, so that standard Markdown task syntax creates an unchecked task.
11. As a desktop note editor user, I want the shortcut marker to disappear
    after conversion, so that the note shows the semantic result instead of
    raw Markdown syntax.
12. As a desktop note editor user, I want the text typed after a structural
    marker to remain in the new block, so that conversion does not lose my
    content.
13. As a desktop note editor user, I want Markdown markers in the middle of a
    sentence to remain literal text, so that ordinary prose is not changed by
    accident.
14. As a desktop note editor user, I want to type `*text*`, so that the text
    becomes italic when the supported inline syntax is complete.
15. As a desktop note editor user, I want to type `**text**`, so that the text
    becomes bold when the supported inline syntax is complete.
16. As a desktop note editor user, I want the supported strikethrough syntax
    to create the existing strikethrough attribution, so that Markdown input
    and toolbar formatting produce the same document result.
17. As a desktop note editor user, I want to select a word or phrase, so that a
    formatting popover appears automatically near the selection.
18. As a desktop note editor user, I want the popover to follow the selection
    while I scroll or move the caret, so that its position remains useful.
19. As a desktop note editor user, I want to apply italic from the popover,
    so that I can format selected text with one action.
20. As a desktop note editor user, I want to apply strikethrough from the
    popover, so that I can mark selected text without opening `Aa`.
21. As a desktop note editor user, I want to apply bold from the popover, so
    that emphasis is available beside the selected content.
22. As a desktop note editor user, I want active formatting buttons to reflect
    the selected text, so that I can see whether italic or strikethrough is
    already applied.
23. As a desktop note editor user, I want the popover to hide when the
    selection collapses or disappears, so that it does not cover the editor
    while I am only moving the caret.
24. As a desktop note editor user, I want the selected range to remain the
    target while I click a popover button, so that opening the popover does not
    change what will be formatted.
25. As a desktop note editor user, I want the editor to retain focus after a
    formatting command, so that I can continue typing immediately.
26. As a desktop note editor user, I want the popover to close when I click
    outside it, so that temporary controls do not remain on screen.
27. As a desktop note editor user, I want keyboard navigation to continue
    working while the popover is visible, so that the popover does not block
    normal editing.
28. As a desktop note editor user, I want formatting changes to be available
    offline, so that the local-first editor remains useful without a network
    connection.
29. As a collaborating note user, I want shortcut conversions and formatting
    changes to synchronize like other editor changes, so that every participant
    sees the same document.
30. As a desktop note editor user, I want task shortcuts to use the normal task
    checkbox and task metadata behavior, so that a task created by typing is
    not a special task type.
31. As a maintainer, I want shortcut conversion to use the existing editor
    command and reaction seams, so that document capture and REST/OT validation
    remain centralized.
32. As a maintainer, I want the contextual popover to use the existing
    selection and command seams, so that the feature does not create a second
    document mutation path.
33. As a user with reduced motion enabled, I want the popover to reach its
    final position without unnecessary animation, so that the interaction is
    comfortable.
34. As a user with accessibility needs, I want each popover action to have a
    clear label and active state, so that the formatting controls are usable
    with keyboard navigation and assistive technology.

## Implementation Decisions

- Limit this feature to the desktop editor. Do not change mobile toolbar or
  mobile selection behavior.
- Render the selection formatter as a contextual popover, not as a second
  persistent bottom toolbar.
- Follow the Super Editor popover pattern: observe the composer selection,
  render through an overlay portal, anchor to selection bounds, constrain the
  popover to the editor viewport, and share focus between the editor and the
  popover.
- Reuse the existing `follow_the_leader` capability for selection anchoring.
  Do not add a custom coordinate calculation when the existing dependency can
  follow the selection.
- Show the contextual popover only for an expanded selection containing
  editable text. Hide it for a null or collapsed selection and for selections
  that contain no editable text.
- Keep the persistent editor toolbar for document-level actions. Do not move
  attachments or the divider action into the selection popover in this slice.
- Reuse the existing inline attribution commands for bold, italic, and
  strikethrough. Do not create a second formatting command layer.
- Derive active button state from the current document and selection. Do not
  persist active formatting state in a provider or in the note model.
- Preserve the selected range while the popover receives focus. A formatting
  command must restore or use the valid selected range before dispatching the
  editor request.
- Keep the popover open after an inline formatting command when the selection
  remains valid. Hide it when the selection is cleared or collapsed.
- Use Markdown-as-you-type support for supported inline and structural syntax
  when the current Super Editor dependency provides it.
- Add a local editor reaction for task syntax and any structural shortcut not
  supported by the official Markdown plugin. The reaction must dispatch editor
  requests rather than mutate the document directly.
- Recognize structural shortcuts only at the start of an editable paragraph
  or line and only when the marker is completed with its trigger space, except
  for the existing horizontal-rule rule.
- Recognize these initial structural shortcuts: `# `, `## `, `### `, `- `,
  `* `, `1. `, `> `, `[] `, standard `- [ ] `, and `---`.
- Convert `[] ` and `- [ ] ` into an unchecked `TaskNode`. Remove the marker
  and preserve the remaining text in the task.
- Keep literal markers unchanged when they are not at a valid shortcut
  position. Do not add a Markdown source mode or a second document format.
- Map shortcut results to existing semantic nodes and attributions. Do not
  store Markdown markers in the canonical document after conversion.
- Route every conversion through the existing editor command, operation
  capture, outbox, and REST/OT validation flow.
- Do not write directly to the relational `tasks` or `task_completions`
  projections. The task projection remains derived from the canonical
  document snapshot.
- Do not change the document schema, REST/OT operation vocabulary, sync
  lifecycle, account isolation, or task projection contract.
- Keep the implementation desktop-specific at the presentation and keyboard
  activation boundary. The command and reaction logic may remain reusable if
  it does not change mobile behavior.
- Prefer the existing Super Editor package and project dependencies. Add
  `super_editor_markdown` only if the pinned Super Editor revision requires it
  for the supported Markdown-as-you-type behavior.

## Testing Decisions

- Use the rendered desktop editor as the highest test seam. Assert visible
  behavior and resulting document state, not private widget names or overlay
  implementation details.
- Reuse the existing note editor widget fixtures and toolbar fixtures. Do not
  introduce a second editor integration harness.
- Test that an expanded selection shows the contextual popover and a
  collapsed selection hides it.
- Test that the popover follows a selection after editor scrolling and remains
  inside the desktop editor viewport.
- Test that the popover actions expose accessible labels and active states.
- Test that bold, italic, and strikethrough apply to the selected range and
  preserve the editor focus contract.
- Test that changing the selection updates active formatting state without
  reusing an obsolete range.
- Test that clicking outside the popover hides it without changing document
  content.
- Test that keyboard navigation and Escape do not leave a stale popover.
- Test the structural shortcut conversion for each heading level.
- Test unordered and ordered list shortcut conversion, including both `- `
  and `* ` for unordered lists.
- Test blockquote and horizontal-rule conversion.
- Test `[] ` and `- [ ] ` conversion into an unchecked `TaskNode`, including
  marker removal and text preservation.
- Test that task shortcut conversion uses the same operation capture as a task
  created through the existing editor command.
- Test inline Markdown conversion for supported italic and bold syntax and
  verify that the resulting attributions match toolbar formatting.
- Test that unsupported or incomplete markers remain literal text and that
  markers in the middle of a sentence are not converted.
- Test conversion at the start of an empty line, after a line break, and when
  text follows the marker.
- Test that a converted task, heading, list item, or blockquote survives local
  snapshot reconstruction and pending-operation replay.
- Test that conversion creates no direct writes to task projections.
- Test the existing operation contract and backend validator with the new
  captured operations if the conversion produces a new operation shape.
- Run focused editor, toolbar, command, operation-capture, and operation
  contract tests before the full Flutter analysis.
- Treat existing unrelated working-tree changes as user-owned and do not use
  a clean checkout assumption for validation.

## Out of Scope

- Mobile contextual selection toolbar changes.
- A complete Markdown source editor or Markdown export redesign.
- Full CommonMark or GitHub-Flavored Markdown coverage.
- Tables, fenced code blocks, inline code, images, links, footnotes, raw HTML,
  or other Markdown features not already supported by the document model.
- Checked-task syntax such as `- [x] ` unless it is already supported by the
  selected Super Editor Markdown plugin and can be added without a new
  product decision.
- New task metadata, independent tasks, cross-note task hierarchy, or changes
  to task projections.
- Changes to REST/OT synchronization, rebasing, authentication, sharing, or
  account isolation.
- Replacing the existing editor toolbar, editor, composer, or document schema.
- A new state-management provider for selection formatting or shortcut state.
- A new overlay, animation, or Markdown parsing framework when an existing
  project dependency provides the required capability.

## Further Notes

The contextual popover and Markdown conversion are separate editor seams. The
popover is a presentation and selection interaction. Markdown conversion is an
editor input reaction that produces canonical document operations.

The Super Editor documentation recommends an overlay portal, selection links,
and a follower for a selection popover. It also provides a Markdown-as-you-type
plugin for supported syntax. The current project must verify the exact pinned
revision before relying on plugin coverage for lists or tasks. Task conversion
remains an explicit local reaction because `TaskNode` is a SupaNotes domain
requirement and must enter the existing REST/OT capture path.

This specification is local only. It is not published to an external issue
tracker.
