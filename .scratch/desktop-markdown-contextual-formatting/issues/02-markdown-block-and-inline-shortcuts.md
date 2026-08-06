# 02 — Markdown block and inline shortcuts

**What to build:** While typing in the desktop note editor, convert the
supported Markdown markers into the existing semantic blocks and inline
attributions. The user should see the formatted result immediately, with the
typed marker removed and the remaining text preserved.

**Blocked by:** None — can start immediately.

**Status:** implemented

- [x] Typing `# `, `## `, or `### ` at the start of an editable line creates
      the matching heading level.
- [x] Typing `- ` or `* ` at the start of an editable line creates an
      unordered list item.
- [x] Typing `1. ` at the start of an editable line creates an ordered list
      item.
- [x] Typing `> ` at the start of an editable line creates a blockquote.
- [x] Typing the existing horizontal-rule shortcut creates the existing
      horizontal-rule block.
- [x] Supported inline Markdown converts to the existing italic and bold
      attributions when the syntax is complete.
- [ ] Conversion removes only the recognized marker and preserves the text
      that follows it.
- [ ] Markers in the middle of a sentence, incomplete markers, and literal
      prose remain unchanged.
- [x] The implementation uses the official Super Editor Markdown support when
      it covers the required syntax and a local editor reaction only for gaps.
- [ ] Every conversion enters through editor requests and is captured by the
      existing REST/OT operation flow.
- [ ] The canonical document schema and operation vocabulary remain unchanged.
- [ ] Focused tests cover each shortcut, marker precedence, literal text,
      line-start behavior, text preservation, and operation capture.
