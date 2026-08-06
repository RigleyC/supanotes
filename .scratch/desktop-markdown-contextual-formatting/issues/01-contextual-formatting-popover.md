# 01 — Desktop contextual formatting popover

**What to build:** When a desktop user selects editable text in a note, show a
contextual popover beside the selection with bold, italic, and strikethrough
actions. The popover must use the existing editor selection and command flow,
preserve focus and selection while a button is used, and remain separate from
the persistent toolbar for document-level actions.

**Blocked by:** None — can start immediately.

**Status:** implemented

- [x] An expanded desktop text selection shows a popover anchored to the
      selected content and constrained to the editor viewport.
- [x] A null or collapsed selection hides the popover.
- [x] The popover exposes accessible bold, italic, and strikethrough actions.
- [x] Each action applies to the selected range through the existing editor
      command and operation-capture flow.
- [x] Active button state reflects the current selected text attribution.
- [ ] Clicking a popover action does not replace the selected range with an
      unrelated caret position.
- [ ] The editor keeps focus after the formatting action and the popover
      remains usable while the selection is valid.
- [ ] Moving the caret, clicking outside, or clearing the selection hides the
      popover without changing document content.
- [ ] The persistent toolbar continues to provide document-level actions and
      is not duplicated inside the selection popover.
- [x] Mobile editor behavior remains unchanged.
- [x] Widget tests cover visibility, anchoring behavior, active states,
      formatting results, focus, dismissal, and accessibility labels.
