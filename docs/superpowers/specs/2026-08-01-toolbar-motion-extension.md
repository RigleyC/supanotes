# Toolbar Motion Extension

## Problem Statement

A toolbar da nota já possui um pop-up de listas com efeito glass e movimento baseado em spring. Outros estados da toolbar ainda usam animações lineares e independentes, como `AnimatedSize` e `AnimatedOpacity`, quando ações aparecem após uma seleção de texto ou quando um comando muda de estado.

Isso faz com que a abertura do grupo de ações pareça separada do restante da toolbar. A experiência deve ter uma linguagem de movimento consistente, sem transformar cada ação em uma animação pesada ou introduzir uma nova arquitetura de estado.

## Solution

Estender o uso do `motor` para as microinterações da toolbar, mantendo as animações estruturais existentes onde elas são adequadas.

O layout continuará usando `AnimatedSize` para crescer e recolher grupos de ações. O `motor` será usado para animar os elementos internos: entrada dos botões, mudança de estado ativo, seleção do item de lista, checkmark e troca do ícone principal de lista.

Quando dois ícones não tiverem paths compatíveis para um morph geométrico real, a experiência usará um morph perceptual: redução breve do ícone atual, troca, expansão elástica do novo ícone, pequena rotação ou deslocamento e atualização coordenada de cor e fundo.

## User Stories

1. As a note editor user, I want the inline formatting actions to enter smoothly when I select text, so that the toolbar feels connected to my action.
2. As a note editor user, I want the inline formatting actions to leave smoothly when I clear the selection, so that the toolbar does not collapse abruptly.
3. As a note editor user, I want bold, italic and strikethrough buttons to show their active state with motion, so that I can understand the current formatting without relying only on color.
4. As a note editor user, I want the active button background and icon color to transition together, so that the state change feels intentional.
5. As a note editor user, I want the list toolbar button to react when the current block changes list type, so that the selected list format is clear.
6. As a note editor user, I want the list icon to transition when changing between bullet, numbered and checklist modes, so that the new mode does not appear as an unrelated replacement.
7. As a note editor user, I want the list pop-up checkmark to appear with a short spring motion, so that the selected option is easy to identify.
8. As a note editor user, I want list menu selection to keep the current editor selection, so that applying a format does not lose the intended target.
9. As a note editor user, I want the toolbar to keep its current glass surface and anchored pop-up behavior, so that the new motion remains consistent with the existing POC.
10. As a desktop user, I want the same toolbar motion as on mobile, so that the editor does not have separate interaction behavior on desktop.
11. As a user with reduced-motion enabled, I want the toolbar to disable or reduce spring transitions, so that the interface respects my accessibility preference.
12. As a keyboard user, I want Escape and outside-click dismissal to keep working while the menu is animating, so that I can close it at any point.
13. As a keyboard user, I want focus to return to the editor after a list option is selected, so that I can continue typing without an extra click.
14. As a note editor user, I want rapid selection changes to settle on the latest toolbar state, so that obsolete animations do not finish over the current state.
15. As a note editor user, I want the toolbar to remain usable when an action is disabled, so that disabled visual feedback does not block other actions.
16. As a maintainer, I want motion behavior to be shared by toolbar actions, so that new actions do not each create unrelated animation controllers.
17. As a maintainer, I want layout animation and icon-state animation to have separate responsibilities, so that changes to one do not break the other.
18. As a maintainer, I want tests to describe visible behavior rather than the chosen animation implementation, so that the motion implementation can evolve safely.

## Implementation Decisions

- Keep `AnimatedSize` as the owner of structural width changes when a group appears or disappears.
- Add a reusable toolbar motion component for the internal entry, exit and active-state transitions.
- Reuse `motor` and the existing spring tokens already used by the list pop-up. Do not add a second animation framework.
- Use one motion controller per reusable animated component, not one global controller for the whole toolbar.
- Keep toolbar actions stateless with respect to document content. The editor remains the source of truth for selection, attributions and block type.
- Keep the existing command callbacks and list selection flow unchanged.
- Use morph-perceptual transitions for `IconData` changes. A true vector morph is out of scope unless compatible vector paths are introduced later.
- Preserve the existing glass surface, pop-up anchoring, placement calculation, keyboard dismissal and focus restoration.
- Respect `MediaQuery.disableAnimations` by switching to immediate state changes or a minimal opacity transition.
- Coalesce rapid state changes so that the latest toolbar state wins and old transitions cannot trigger stale visual state.
- Keep button semantics, labels, hit targets and disabled states unchanged.
- The highest test seam is the existing `NoteToolbar` widget test seam. The tests should exercise selection changes, list format changes, menu selection, dismissal and reduced-motion behavior through the rendered toolbar.

## Testing Decisions

- Tests must verify external behavior: which actions are visible, which state is selected, which icon or semantic label is exposed, whether the menu opens and closes, and whether focus is restored.
- Do not assert internal controller values, exact spring physics, private widget names or animation frame counts.
- Extend the existing toolbar widget tests for:
  - actions appearing after a non-collapsed selection;
  - actions disappearing after the selection is cleared;
  - active inline formatting state;
  - list trigger state for bullet, numbered and checklist formats;
  - menu option selection and checkmark state;
  - outside tap and Escape dismissal;
  - reduced-motion behavior;
  - desktop toolbar visibility.
- Use settled widget frames only to verify the final externally visible state. Use bounded pump durations only when needed to verify that an intermediate transition does not remove interaction.
- Run the focused toolbar widget test suite first, then the related editor presentation tests, then `flutter analyze`.
- Existing toolbar and editor tests are the prior art for the test seam.

## Out of Scope

- Replacing every `AnimatedSize`, `AnimatedOpacity` or `AnimatedContainer` in the application.
- Adding a new animation or icon-morph package.
- Changing the editor document model, REST/OT operations or sync behavior.
- Changing the list pop-up layout, labels, icons or command semantics.
- Implementing true SVG path morphing between arbitrary icons.
- Adding new toolbar actions.
- Changing the Liquid Glass visual treatment beyond motion-related state transitions.
- Redesigning the mobile or desktop editor layout.

## Further Notes

The first implementation should target the inline formatting group and the list trigger because they already expose clear state transitions and share the same toolbar. If the motion feels natural there, the same component can be reused for the list menu checkmark and future toolbar actions.

The implementation should remain a small vertical slice. The success criterion is a toolbar that feels more continuous and responsive, not a general-purpose animation system.
