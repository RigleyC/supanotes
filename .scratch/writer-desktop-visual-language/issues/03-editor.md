## Parent

#18 — Aplicar linguagem visual desktop do Writer ao SupaNotes

## What to build

Aplicar ao editor desktop a composição de escrita do Writer sem trocar o Super Editor nem alterar o fluxo `editor`.

### Componentes

- `DesktopNoteChrome` substitui visualmente o `AppBar` móvel apenas no desktop. Ele reutiliza Note, preferências, estado de sync e callbacks existentes.
- `DesktopEditorViewport` controla coluna máxima, padding lateral, espaço superior e espaço inferior para a toolbar.
- `NoteEditor` continua hospedando `SuperEditor`, overlays, componentes de Task, anexos, slash commands e `NoteToolbar`.
- O editor passa a ter entrypoints explícitos de stylesheet para mobile e desktop. Uma base comum mantém as regras semânticas de body, headings, listas, blockquotes, tasks, links e parágrafos; cada perfil define suas métricas de apresentação.
- O cache do stylesheet considera `ColorScheme`, padding e perfil de layout, evitando reutilizar a aparência mobile no desktop ou o inverso.
- `NoteToolbar` continua sendo a superfície contextual inferior. Não deve ser misturada com o chrome superior.

### Visual and behaviour

- O `DesktopNoteChrome` é transparente ou usa superfície do tema, sem Card/elevation pesada.
- O editor usa coluna máxima próxima de 720–734 px, centralizada no espaço restante após a sidebar.
- Padding lateral adapta-se à viewport e não deixa o texto colado às bordas.
- Espaço superior separa chrome e primeiro bloco; espaço inferior evita que a toolbar cubra o último bloco.
- O line-height é calibrado com conteúdo rico real, entre o valor atual e aproximadamente 1.8.
- O perfil mobile mantém escala maior, padding adequado ao teclado e interação por toque; o perfil desktop usa escala compacta, coluna centralizada e ritmo de leitura do Writer.
- Mobile mantém o `AppBar` e o layout atuais.
- A implementação não cria tabs e não toca no ownership de `NoteEditorSession`, `NoteSyncSession` ou `NoteSessionCoordinator`.
- Todas as operações continuam entrando pelo controller/comandos existentes e pelo Document Snapshot canônico.

## Acceptance criteria

- [ ] O desktop apresenta chrome superior compacto.
- [ ] A Note aparece em coluna centralizada com largura máxima próxima de 720–734 px.
- [ ] Padding lateral e espaço superior são responsivos.
- [ ] Body, headings, listas, tasks, anexos e links permanecem legíveis.
- [ ] Existem entrypoints separados de stylesheet para mobile e desktop.
- [ ] Regras semânticas compartilhadas não são duplicadas entre os perfis.
- [ ] O cache invalida/recria o stylesheet quando o perfil mobile/desktop muda.
- [ ] Line-height não quebra geometria de tasks/listas.
- [ ] Toolbar contextual permanece disponível e aberta durante navegação do cursor.
- [ ] Seleção, foco, edição local, flush e REST/OT mantêm comportamento.
- [ ] Light/dark e fallback sem blur permanecem legíveis.
- [ ] Não são adicionadas tabs.
- [ ] Testes cobrem viewport, conteúdo rico, foco/seleção, toolbar e regressão de sessão.
- [ ] `flutter analyze --no-pub` e testes focados do editor passam.

## Blocked by

- #19 — Desktop: estabelecer shell visual e tokens de layout
