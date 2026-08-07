## Parent

#18 — Aplicar linguagem visual desktop do Writer ao SupaNotes

## What to build

Estabelecer a base visual desktop do SupaNotes para que a aplicação tenha uma composição contínua: sidebar à esquerda, divisória discreta e área de edição à direita. O shell continua sendo o dono da composição; ele não deve assumir ownership de Notes, edição ou sincronização.

### Componentes

- `AdaptiveNotesShell` continua decidindo desktop/mobile, roteando seleção de Note e mantendo a largura da sidebar.
- `DesktopSidebarSurface` envolve a sidebar atual e fornece fundo, divisória, largura e composição vertical.
- `DesktopContentSurface` fornece a área contínua do conteúdo e hospeda a tela filha.
- `DesktopLayoutTokens`/tokens equivalentes devem centralizar largura inicial/mínima/máxima, altura de controle, altura de linha, padding e raios. Reusar `AppColors`, `AppSpacing` e `AppTheme` sempre que possível.
- `ResizeDragHandle` continua independente: linha visual de 1 px e hit target maior, sem engrossar a divisória.

### Behaviour

- A largura inicia próxima de 300 px, fica entre 220 e 420 px e é limitada pela viewport.
- A largura persistida usa o mecanismo de preferências existente.
- O shell funciona em light/dark e tem fallback legível quando blur/transparência não estiver disponível.
- Mobile mantém sua composição atual.
- O shell não cria estado de Note, controller de edição, sessão de sync ou mutação de domínio.

## Acceptance criteria

- [ ] O desktop mantém sidebar e conteúdo no mesmo shell, sem alterar navegação entre Notes.
- [ ] A sidebar aceita resize com limites seguros e respeita a largura da viewport.
- [ ] O resize não engrossa visualmente a divisória e mantém área de interação adequada.
- [ ] A largura é preservada ao reconstruir o shell e reabrir a aplicação.
- [ ] Tokens compartilhados controlam altura de controle, linha, largura, divisória e raios.
- [ ] Light/dark e fallback sem blur permanecem legíveis.
- [ ] Criação, seleção e abertura de Note continuam funcionando.
- [ ] Existem testes para limites, persistência, viewport, mobile e tema.
- [ ] `flutter analyze --no-pub` e testes focados do shell passam.

## Blocked by

None — can start immediately.
