# Análise de design desktop: Writer versus SupaNotes

Data: 2026-08-05  
Escopo: análise read-only do frontend do `writer-computer` e do frontend desktop atual do SupaNotes.  
Referência: https://github.com/joelbqz/writer-computer

## Resumo executivo

O `writer-computer` usa uma composição desktop de três camadas:

1. chrome superior com controles de janela, navegação e tabs;
2. sidebar estreita, densa e baseada em árvore de arquivos;
3. área de escrita sem cartão, com uma coluna de texto estreita centrada.

O SupaNotes já tem a base certa para reaproveitar essa linguagem: `AdaptiveNotesShell`, largura de sidebar ajustável, `ResizeDragHandle`, tokens de cor, espaçamento, toolbar translúcida e um editor com stylesheet próprio. A mudança recomendada é uma camada visual desktop sobre o shell atual, não uma troca do Super Editor, do REST/OT ou do modelo de notas.

O ponto de maior valor é alinhar a composição e a densidade visual: sidebar com fundo neutro contínuo, header compacto, busca integrada, item selecionado com superfície sutil, editor centrado com largura máxima e chrome de nota menos parecido com `AppBar` móvel. A semântica do SupaNotes deve permanecer: notas, favoritos, tarefas, compartilhamento, preferências e sincronização.

## Fontes primárias

- Repositório e arquitetura: https://github.com/joelbqz/writer-computer
- Layout principal: https://github.com/joelbqz/writer-computer/blob/master/apps/desktop/src/components/app-layout.tsx
- Busca e composição da sidebar: https://github.com/joelbqz/writer-computer/blob/master/apps/desktop/src/components/sidebar/file-browser.tsx
- Linhas da árvore: https://github.com/joelbqz/writer-computer/blob/master/apps/desktop/src/components/sidebar/file-tree-node.tsx
- Seções da sidebar: https://github.com/joelbqz/writer-computer/blob/master/apps/desktop/src/components/sidebar/sidebar-section.tsx
- Layout do editor: https://github.com/joelbqz/writer-computer/blob/master/apps/desktop/src/components/editor-area/editor-pane.tsx
- Scroll, fade e blur do editor: https://github.com/joelbqz/writer-computer/blob/master/apps/desktop/src/components/editor-area/editor-scroll-container.tsx
- Tokens visuais: https://github.com/joelbqz/writer-computer/blob/master/apps/desktop/src/App.css
- Tema Writer: https://github.com/joelbqz/writer-computer/tree/master/apps/desktop/shared/themes/writer
- Screenshot de referência: https://github.com/joelbqz/writer-computer/blob/master/apps/website/public/screenshots/editor.png

## 1. Anatomia visual do Writer

### 1.1 Janela e chrome superior

- A aplicação ocupa toda a janela.
- Existe uma região superior de arraste de 72 px.
- Os controles principais usam 32 px de altura e 12 px de padding vertical.
- O botão de abrir/fechar sidebar fica no lado esquerdo, com margem inicial grande para respeitar os controles nativos da janela.
- A faixa de tabs começa depois da sidebar e usa o espaço restante.
- Navegação anterior/próxima, tabs e nova tab ficam na mesma faixa visual.
- A tab ativa é indicada por uma superfície translúcida arredondada, não por uma linha forte ou uma cor saturada.

Efeito visual: o chrome não compete com o documento. Ele é baixo, neutro e formado por estados de superfície.

### 1.2 Sidebar

Medidas observadas no código:

| Elemento | Medida/valor |
|---|---:|
| largura mínima | 220 px |
| largura máxima | menor entre 420 px e 35% da viewport, com mínimo efetivo de 280 px |
| altura do controle | 32 px |
| linha de arquivo/pasta | 32 px |
| fonte de linha | 13 px |
| raio de linha | 8 px |
| ícone de arquivo | 16 px dentro de uma célula de 20 px |
| indentação raiz | 10 px |
| indentação por nível | 12 px |
| padding horizontal da sidebar | 12 px |
| label de seção | 12 px, altura 20 px |

Composição:

- A sidebar tem uma única superfície vertical e uma divisória de 1 px no lado direito.
- A busca é um botão de 32 px com preenchimento de input, ícone de 16 px e atalho visível.
- O conteúdo rola sem scrollbar visível e usa fade nas bordas.
- As seções `Pinned`, `Recents` e `Everything` são compactas; cada uma pode recolher.
- A árvore usa linhas de 32 px, gap de aproximadamente 2 px, texto de 13 px e ícones com opacidade reduzida até hover/seleção.
- O item selecionado usa preenchimento neutro translúcido. Não há card, sombra ou borda pesada.
- O workspace atual fica em um botão de 32 px no rodapé da sidebar.

### 1.3 Editor

Tokens observados:

| Elemento | Medida/valor |
|---|---:|
| coluna de texto | 734 px de largura máxima |
| padding lateral | `clamp(24px, 4vw, 64px)` |
| largura externa | coluna + dois paddings |
| texto base | 16 px |
| line-height | 1.8 |
| padding superior inicial | 128 px; 144 px em breakpoint médio |
| padding inferior do documento | 40vh |
| fade/blur superior e inferior | 120 px |
| gutter de scrollbar | 18 px |

O editor não aparece dentro de um cartão. A área de fundo é contínua, e a coluna de leitura é centrada. O conteúdo começa abaixo do chrome, mas ganha espaço superior suficiente para parecer uma página de escrita, não um formulário.

O código também oculta gutters, usa seleção com a cor de destaque em baixa opacidade, mantém hashes de headings no espaço lateral e deixa o editor ser o dono visual do documento. O scroll real fica em um container externo, com blur progressivo nas bordas.

### 1.4 Tipografia e cor

O tema `writer` é deliberadamente pequeno:

- dark: accent `#FF6A00`, background `#111111`, foreground `#FCFCFC`, translucency 20, contrast 16;
- light: accent `#FF6A00`, background `#FFFFFF`, foreground `#0D0D0D`, translucency 10, contrast 20.

O restante deriva de alpha e `color-mix`, produzindo superfícies, texto secundário, texto muted, bordas, seleção e item ativo. Isso explica por que o visual parece rico mesmo com poucas cores explícitas: a hierarquia vem de opacidade, não de muitas cores.

## 2. Comparação com o SupaNotes atual

### O que já está alinhado

- `lib/features/notes/catalog/presentation/adaptive_notes_shell.dart` já separa sidebar e conteúdo em um `Row` desktop e permite redimensionamento.
- `lib/features/notes/catalog/presentation/widgets/resize_drag_handle.dart` já preserva uma linha visual estreita e uma área de gesto maior. O handle atual tem 6 px visuais/estruturais; a decisão anterior de aumentar o hit target sem engrossar a linha continua correta.
- `lib/shared/theme/app_colors.dart` já centraliza cores e possui superfícies light/dark, estados semânticos e indigo/blue/orange.
- `lib/shared/theme/app_spacing.dart` já possui uma escala de 4/8/16/24/32/48 px e raios até 20 px.
- `lib/features/notes/editor/presentation/widgets/note_toolbar.dart` já usa blur, superfície translúcida, borda sutil, sombra leve, radius grande e estados compacto/formatado.
- `lib/features/notes/editor/presentation/note_stylesheet.dart` já reduz a escala do editor em desktop para body 15 px, h1 28 px, h2 22 px e h3 18 px.
- A sidebar atual já usa `ValueKey(note.id)`, busca, favoritos, seleção, excerpt e ações de contexto.

### Diferenças de maior impacto visual

| Área | Writer | SupaNotes atual | Consequência |
|---|---|---|---|
| modelo da sidebar | árvore de workspace | lista de notas | não copiar a árvore; copiar densidade, superfícies e hierarquia |
| header desktop | chrome/tabs compartilhados | `AppBar` do editor e shell separado | o desktop ainda lê como tela móvel ampliada |
| largura inicial | 220–420 px com persistência | 300 px local no estado do shell | falta token/persistência e ajuste alinhado à viewport |
| linha de item | 32 px, 13 px, raio 8 | tile com padding vertical 8, título 13, excerpt 11 | o tile atual é mais alto e mais parecido com lista de cards |
| busca | controle 32 px integrado no topo | `TextField` com padding e abas de filtro | pode manter a função e adotar o chrome compacto do Writer |
| editor | coluna 734 px, line-height 1.8 | padding Super Editor e line-height 1.4 | falta uma coluna desktop mais arejada e centrada |
| tabs | parte essencial do shell | não há tabs equivalentes no shell Flutter | deve ser avaliado como navegação desktop, não como requisito visual isolado |
| rodapé | métricas discretas na borda inferior | não há equivalente evidente no editor Flutter | pode trazer apenas se houver valor para tarefas/notas |
| cor de destaque | laranja único e discreto | Joi/Apple com indigo/blue/semantic colors | não substituir a identidade Joi; usar contraste/superfície antes de trocar a paleta |

## 3. O que copiar e o que não copiar

### Copiar

1. composição de janela: sidebar persistente + área de edição contínua;
2. densidade de 32 px para controles e itens de navegação;
3. fonte de UI próxima de 13 px para chrome/sidebar;
4. seleção com superfície sutil e texto mais opaco;
5. sidebar sem cards individuais, com uma divisória lateral fina;
6. editor centrado, com largura máxima e padding responsivo;
7. top spacing generoso para o documento;
8. superfícies derivadas por alpha, evitando bordas e sombras pesadas;
9. scroll com fade suave, se o custo de renderização for aceitável;
10. header desktop compacto, separado da toolbar contextual do editor.

### Não copiar

1. árvore de arquivos, workspace folders, `Pinned/Recents/Everything` ou recents baseados em mtime;
2. CodeMirror, ProseMark, Tauri ou o modelo de arquivos em disco;
3. tabs como requisito obrigatório sem antes definir a navegação de notas e a lifecycle ownership de sessões;
4. accent laranja como substituição global da paleta Joi/Apple;
5. opacidade/translucência dependente de vibrancy do sistema sem fallback sólido no Flutter;
6. componentes com hit target menor que 44×44 px onde a interação é tocável ou híbrida.

## 4. Proposta de design para o desktop do SupaNotes

### Camada A — shell visual

Criar um shell desktop com estes papéis:

- `DesktopNotesShell`: mantém o `Scaffold` e o `Row`, mas introduz uma camada de chrome desktop.
- `DesktopSidebar`: envolve `NotesSidebar` e aplica superfície, divisória, header compacto e footer de conta/configuração.
- `DesktopNoteChrome`: título da nota, ações de nota e indicador de sincronização; não deve duplicar a toolbar de formatação.
- `DesktopNoteViewport`: área contínua que hospeda o editor, com largura máxima e padding específico para desktop.

Os nomes são papéis de composição. Não criar uma nova camada de estado: roteamento, `NoteEditorSession`, Riverpod e REST/OT continuam nos donos atuais.

### Camada B — tokens desktop

Adicionar tokens locais ao tema compartilhado, sem alterar o significado dos tokens móveis:

| Token proposto | Valor inicial inspirado no Writer |
|---|---:|
| largura inicial sidebar | 280–300 px |
| largura mínima sidebar | 220 px |
| largura máxima sidebar | 420 px ou 35% da viewport |
| altura chrome control | 32 px |
| altura linha sidebar | 32 px |
| fonte chrome/sidebar | 13 px |
| fonte label de seção | 12 px |
| largura máxima coluna editor | 720–734 px |
| padding lateral editor | 24–64 px responsivo |
| line-height editor desktop | validar entre 1.55 e 1.8 |
| raio de item | 8 px |
| divisória | 1 px com `outlineVariant` em baixa opacidade |

Os valores são pontos de partida. Devem ser validados com screenshot e leitura real no Windows/macOS, porque Flutter e CSS não medem texto da mesma forma.

### Camada C — sidebar

Reorganizar a sidebar visual atual nesta ordem:

1. header compacto com nome/identidade e ações essenciais;
2. busca de 32 px;
3. filtro `Todas/Favoritas` com aparência de section control, não de chip grande;
4. lista de notas com linhas de 32–40 px, dependendo de o excerpt permanecer visível;
5. footer com configurações e estado da conta.

Recomendação de conteúdo: manter o excerpt, pois ele é útil no SupaNotes, mas reduzir o padding vertical e usar opacidade para criar a densidade do Writer. Não transformar notas em árvore artificial.

### Camada D — editor

- Remover a sensação de `AppBar` móvel no desktop.
- Manter ações de nota no chrome superior, mas reduzir o peso visual.
- Centralizar o documento em uma coluna máxima próxima de 720–734 px.
- Aumentar o espaço horizontal disponível ao redor do texto sem aumentar a fonte de forma agressiva.
- Testar line-height desktop entre o atual 1.4 e o Writer 1.8; tarefas e listas podem exigir um valor intermediário.
- Preservar a toolbar contextual inferior, porque ela é uma decisão de produto do SupaNotes e não existe um equivalente funcional direto no Writer.
- Se usar fade/blur no scroll, aplicar apenas na viewport desktop e garantir fallback sem blur.

### Camada E — tabs e navegação

Não implementar tabs apenas para imitar a screenshot. Primeiro definir a regra de sessão:

- abrir duas notas cria duas sessões ou reutiliza uma sessão por `noteId`;
- trocar de tab preserva seleção, foco, scroll e sync;
- fechar uma tab não descarta uma sessão ainda usada por outra rota;
- restart/offline continua recuperando o outbox.

Se essas regras forem aprovadas, uma faixa de tabs pode ser adicionada depois como navegação desktop. Até lá, o visual do Writer pode ser obtido com um chrome superior de nota sem tabs.

## 5. Sequência recomendada de implementação

### Fase 1 — baseline visual

- capturar screenshots do SupaNotes em desktop light/dark em pelo menos 1280×800 e 1440×900;
- medir a largura atual da sidebar, altura dos itens, coluna do editor e top chrome;
- definir os tokens desktop e uma matriz de viewport;
- não alterar navegação nem sync.

### Fase 2 — shell e sidebar

- ajustar a largura da sidebar para limites do Writer;
- persistir a largura conforme o padrão de preferências já usado no projeto;
- aplicar header/busca/itens/divisória com densidade 32 px;
- manter o hit target do resize maior que a linha visual;
- adicionar testes de layout e seleção/reordenação da lista.

### Fase 3 — editor

- aplicar coluna máxima e padding responsivo ao `NoteEditor` desktop;
- calibrar tipografia e espaçamento de heading/lista/tarefa;
- ajustar o chrome do editor para não parecer `AppBar` móvel;
- preservar toolbar, seleção, navegação do cursor e sincronização.

### Fase 4 — navegação avançada

- decidir tabs por comportamento, não por aparência;
- implementar somente após testes de sessão, troca de nota, fechamento, processo morto e offline;
- adicionar footer/status apenas se métricas de nota forem úteis para o produto.

## 6. Critérios de aceitação visual

- Em 1280 px de largura, a sidebar não consome mais de 35% da janela e continua utilizável entre 220 e 420 px.
- Linhas da sidebar têm altura consistente e não parecem cards separados.
- O item selecionado é perceptível sem uma cor forte ou sombra.
- A busca, as ações e os itens mantêm pelo menos 44×44 px de área efetiva quando usados como controles de toque; a densidade visual pode continuar em 32 px apenas para controles exclusivamente mouse/teclado, com validação de acessibilidade.
- O corpo da nota fica centrado e não ocupa toda a largura da janela.
- Títulos, tarefas, listas, anexos e toolbar continuam legíveis em light/dark.
- Navegar o cursor dentro da nota não fecha a toolbar contextual aberta.
- A alteração visual não cria writes diretos na projeção de tasks, não duplica sessão de editor e não reintroduz Yjs/YDoc.
- `flutter analyze --no-pub` e os testes focados de shell, sidebar, editor e toolbar passam.

## Veredito

Vale copiar a linguagem visual do Writer. O SupaNotes já tem componentes e decisões que reduzem o custo: o trabalho principal é consolidar um shell desktop e calibrar métricas visuais. A maior oportunidade é fazer a versão desktop parecer uma aplicação de escrita contínua, e não uma tela mobile com sidebar. A maior restrição é não importar a arquitetura de arquivos/tabs do Writer sem uma decisão explícita sobre sessões, rotas e sincronização.
