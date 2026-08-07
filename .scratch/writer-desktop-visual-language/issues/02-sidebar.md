## Parent

#18 — Aplicar linguagem visual desktop do Writer ao SupaNotes

## What to build

Aplicar a linguagem visual compacta do Writer à sidebar do SupaNotes sem transformar Notes em árvore de arquivos. A sidebar mantém o fluxo `catalog` e só muda composição e densidade visual.

### Componentes

- `NotesSidebar` continua sendo o widget de dados e interação da lista.
- `SidebarHeader` apresenta identidade e ações de criação/configuração sem buscar dados adicionais.
- `NotesSearchAndFilters` mantém busca e filtros `Todas/Favoritas` como controles compactos.
- `ScrollableNotesList` contém loading, erro, vazio e linhas com identidade estável.
- `SidebarNoteTile` mantém título, trecho, favorito, seleção e menu de contexto.
- `SidebarFooter` apresenta configurações/conta sem cobrir a lista.

### Visual and behaviour

- Fundo contínuo, divisória fina e ausência de cards pesados por Note.
- Linhas próximas de 32 px quando só exibirem título; se o trecho exigir altura maior, usar uma altura única e documentada para todas as linhas.
- Texto de UI próximo de 13 px, labels próximos de 12 px, raio próximo de 8 px.
- Seleção usa superfície/contraste derivado do `ColorScheme`, não uma cor nova.
- A área visual pode ser densa, mas controles tocáveis preservam hit target adequado.
- A lista usa `ValueKey(note.id)` e não perde identidade durante sincronização/reordenação.
- Nenhuma árvore de diretórios, pinned/recents ou workspace folder do Writer.

## Acceptance criteria

- [ ] A sidebar usa superfície contínua e divisória fina.
- [ ] Busca e filtros atuais continuam disponíveis no chrome compacto.
- [ ] Linhas de Note têm altura, tipografia e truncamento consistentes.
- [ ] Seleção funciona em light/dark com contraste sutil.
- [ ] Título, trecho, favorito e menu de contexto continuam funcionando.
- [ ] Criação de Note e navegação continuam funcionando.
- [ ] Footer compacto não cobre a lista.
- [ ] Estados vazio, loading, erro e sem resultado permanecem legíveis.
- [ ] A identidade das linhas é preservada durante atualizações do catálogo.
- [ ] Testes cobrem seleção, busca, filtros, favorito, erro, reordenação e viewport desktop.
- [ ] `flutter analyze --no-pub` e testes focados da sidebar passam.

## Blocked by

- #19 — Desktop: estabelecer shell visual e tokens de layout
