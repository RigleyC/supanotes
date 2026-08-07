# Linguagem visual desktop inspirada no Writer

## Problem Statement

A versão desktop do SupaNotes funciona, mas a composição visual ainda se aproxima de uma tela móvel ampliada: a sidebar, o chrome superior e o editor não formam uma aplicação de escrita contínua. O usuário quer trazer para o desktop a linguagem visual do projeto Writer: sidebar densa e redimensionável, controles compactos, superfícies discretas, editor centralizado e espaçamento de leitura amplo.

O Writer é um editor Markdown baseado em arquivos, enquanto o SupaNotes é uma aplicação de notas com documento rico, tarefas, compartilhamento, preferências, persistência local e sincronização REST/OT. A necessidade é copiar somente o design e a composição visual, sem copiar o modelo de dados, o editor interno ou a arquitetura de sincronização do Writer.

## Solution

Aplicar uma camada de composição desktop ao shell atual do SupaNotes.

O desktop deve usar uma estrutura visual contínua com sidebar persistente à esquerda, chrome superior compacto e área de edição à direita. A sidebar deve usar linhas densas, seleção por superfície sutil, busca compacta, divisória fina e largura ajustável. O editor deve usar uma coluna máxima centralizada, padding lateral responsivo, espaço superior generoso e uma superfície de fundo contínua, sem parecer um card ou formulário.

A solução deve manter o Super Editor, o documento REST/OT canônico, as sessões de editor, as projeções de tarefas, as ações de compartilhamento e as preferências existentes. A toolbar contextual do SupaNotes permanece como uma superfície funcional própria; ela não deve ser substituída por uma cópia do editor Markdown do Writer.

## User Stories

1. Como usuário desktop, quero uma sidebar persistente, para navegar entre minhas notas sem abrir uma tela separada.
2. Como usuário desktop, quero redimensionar a sidebar, para ajustar o espaço de navegação ao meu monitor.
3. Como usuário desktop, quero que a largura da sidebar tenha limites seguros, para não ocultar o editor nem ficar estreita demais.
4. Como usuário desktop, quero que a largura escolhida seja preservada, para não precisar reajustá-la em cada abertura.
5. Como usuário desktop, quero uma divisória fina entre sidebar e editor, para entender a separação sem criar uma borda pesada.
6. Como usuário desktop, quero uma busca compacta no topo da sidebar, para encontrar notas sem ocupar grande parte da tela.
7. Como usuário desktop, quero que a busca mantenha o filtro de notas e favoritos, para não perder funções atuais durante o redesign.
8. Como usuário desktop, quero que os itens da sidebar tenham altura consistente, para examinar muitas notas rapidamente.
9. Como usuário desktop, quero que o item selecionado tenha uma superfície sutil, para reconhecer a nota atual sem uma cor agressiva.
10. Como usuário desktop, quero ver título e trecho da nota, para identificar o conteúdo antes de abri-lo.
11. Como usuário desktop, quero manter favoritos e menu de contexto, para que a densidade visual não remova ações existentes.
12. Como usuário desktop, quero um rodapé compacto para configurações e estado da conta, para acessar funções globais sem competir com a lista.
13. Como usuário desktop, quero um chrome superior compacto, para que a interface não pareça uma tela móvel ampliada.
14. Como usuário desktop, quero que o chrome superior contenha as ações da nota em uma hierarquia clara, para separar ações de documento da formatação de texto.
15. Como usuário desktop, quero que superfícies ativas usem transparência e contraste moderado, para obter hierarquia sem excesso de cards e sombras.
16. Como usuário desktop, quero que o editor ocupe uma área contínua, para ter a sensação de uma página de escrita.
17. Como usuário desktop, quero que o texto seja centralizado em uma coluna de leitura, para linhas longas não prejudicarem a concentração.
18. Como usuário desktop, quero que a coluna do editor tenha largura máxima configurada, para manter legibilidade em monitores grandes.
19. Como usuário desktop, quero padding lateral responsivo, para o editor continuar equilibrado em diferentes larguras de janela.
20. Como usuário desktop, quero espaço superior generoso antes do conteúdo, para o documento não ficar colado ao chrome.
21. Como usuário desktop, quero que headings, parágrafos, listas e tarefas tenham ritmo vertical coerente, para a nota ser confortável de ler.
22. Como usuário desktop, quero que a tipografia desktop seja menor e mais densa que a móvel quando apropriado, para aproveitar melhor a tela sem perder legibilidade.
23. Como usuário desktop, quero que a toolbar contextual continue disponível, para formatar a nota sem perder as capacidades atuais.
24. Como usuário desktop, quero que a toolbar continue aberta enquanto navego pelo documento, para aplicar várias formatações sem reabrir o painel.
25. Como usuário desktop, quero que seleção, cursor, tarefas, anexos e links mantenham o comportamento atual, para o redesign não alterar o modelo de edição.
26. Como usuário de tema claro, quero contraste suficiente entre fundo, texto, seleção e item ativo, para ler a nota sem depender de sombras.
27. Como usuário de tema escuro, quero superfícies e textos derivados por opacidade, para a interface ter profundidade sem muitos tons arbitrários.
28. Como usuário com baixa visão, quero controles interativos com área de toque e foco adequada, para usar a interface com segurança.
29. Como usuário com redução de movimento, quero transições reduzidas ou removidas, para a interface respeitar minha preferência.
30. Como usuário de teclado, quero navegar pela sidebar, chrome e editor sem perder o foco do documento, para trabalhar sem mouse.
31. Como usuário offline, quero que a alteração visual não interrompa a edição local, para continuar trabalhando sem conexão.
32. Como usuário colaborativo, quero que a alteração visual não interrompa a sincronização REST/OT, para continuar vendo e enviando operações normalmente.
33. Como usuário de tarefas, quero que mudanças visuais não criem uma escrita direta na projeção de tarefas, para o documento canônico continuar sendo a fonte de verdade.
34. Como mantenedor, quero que o redesign reuse tokens e componentes compartilhados, para evitar estilos divergentes entre desktop e mobile.
35. Como mantenedor, quero que o shell seja o principal seam de composição, para evitar duplicação de ownership entre catalog, editor e roteamento.
36. Como mantenedor, quero que tabs só sejam introduzidas após uma decisão sobre lifecycle de sessões, para não criar inconsistência ao alternar ou fechar notas.
37. Como mantenedor, quero que o redesign seja visual e incremental, para validar cada camada antes de adicionar complexidade de navegação.

## Implementation Decisions

- Implementar o redesign como uma composição desktop sobre o shell existente.
- Manter o domínio do SupaNotes: `Note`, `Document Snapshot`, `Block`, `Task`, `Projection`, `Vault` e `NoteSyncSession`.
- Não importar a árvore de arquivos, o conceito de workspace folder, `Pinned/Recents/Everything`, o modelo de arquivos Markdown, CodeMirror, ProseMark ou Tauri do Writer.
- Manter a sidebar como lista de notas do SupaNotes, com busca, filtros, título, trecho, favorito, seleção, ações de contexto e criação de nota.
- Usar como referência visual inicial: sidebar entre 220 e 420 px; controles e linhas próximas de 32 px; fonte de chrome/sidebar próxima de 13 px; labels próximos de 12 px; raio de item próximo de 8 px; divisória de 1 px.
- Usar como referência inicial para o editor uma coluna máxima entre 720 e 734 px, padding lateral responsivo entre 24 e 64 px e espaço superior amplo.
- Validar o line-height desktop entre o valor atual e aproximadamente 1.8, considerando a leitura de tarefas, listas, anexos e blocos ricos.
- Centralizar os valores desktop em tokens do tema ou de layout compartilhado. Não espalhar números equivalentes em widgets.
- Preservar a paleta Joi/Apple do SupaNotes. O accent laranja do Writer serve apenas como referência de contraste e não deve substituir a identidade atual.
- Usar transparência, `outlineVariant`, opacidade e superfícies compartilhadas para criar hierarquia. Toda transparência deve ter fallback legível sem blur.
- Manter o handle de resize visualmente estreito e preservar um hit target maior para interação. Não aumentar a linha visual para 44 px.
- Manter a toolbar contextual do editor como uma superfície funcional separada do chrome desktop.
- Não introduzir tabs neste primeiro slice. Tabs são uma decisão posterior de navegação e lifecycle, não um requisito visual isolado.
- Se tabs forem aprovadas posteriormente, a troca deve preservar foco, seleção, scroll, sincronização e ownership de uma sessão por `noteId`.
- Não alterar schema do documento, contrato REST/OT, outbox, projeções, persistência de tasks, anexos, sharing ou preferências de negócio.
- Não criar providers para estado puramente visual, como largura provisória durante drag ou estado aberto de uma superfície local.
- A ordem de implementação será: tokens e baseline visual; shell/sidebar; viewport/editor; validação; decisão separada sobre tabs.

### Componentes e responsabilidades

- `AdaptiveNotesShell` continua sendo o único dono da composição desktop. Ele decide se a viewport é desktop, mantém a largura da sidebar e conecta a seleção da Note ao roteador.
- Um `DesktopSidebarSurface` deve ser criado como superfície de apresentação ao redor de `NotesSidebar`. Ele não deve buscar Notes, criar sessões ou executar mutações de domínio.
- A estrutura visual da sidebar deve ser dividida em header compacto, busca/filtros, lista rolável e footer de ações. Cada parte pode ser um widget de apresentação separado quando tiver estado ou teste próprio.
- O resize deve continuar sendo um componente pequeno e independente. A linha visual deve ter 1 px; a área de gesto deve ser maior e não deve alterar a largura percebida da sidebar.
- Um `DesktopNoteChrome` deve substituir visualmente o `AppBar` móvel apenas no desktop. Ele pode receber o estado já carregado da Note e callbacks existentes para compartilhar, alternar concluídas, alternar imagens e ocultar foco. Não deve criar um segundo controller de preferências.
- No mobile, o `AppBar` e a composição atuais permanecem. O redesign desktop não deve forçar a composição de sidebar ou chrome em telas móveis.
- `NoteEditor` continua sendo o host do `SuperEditor`, overlays, componentes de Task, anexos, slash commands e `NoteToolbar`. O novo layout deve entrar como uma camada de viewport ao redor dele, não como um novo editor.
- A viewport desktop deve aplicar a largura máxima, o padding lateral e o espaço superior por meio de uma única configuração de layout. O `Stylesheet` continua responsável por tipografia e espaçamento entre blocos; o shell não deve posicionar blocos individualmente.
- A `noteStylesheet` deve receber os valores desktop já resolvidos pela viewport ou por tokens do tema e manter regras próprias para body, headings, listas, blockquotes, tasks e parágrafos.
- O stylesheet do documento terá entrypoints explícitos para mobile e desktop. Os dois perfis compartilharão as regras semânticas de blocos, mas poderão divergir em tamanhos, line-height, padding e ritmo vertical.
- As regras compartilhadas de `Task`, listas, headings, links, anexos e estados do documento não serão copiadas entre os perfis. Elas ficarão em uma base comum usada pelos dois entrypoints.
- O perfil desktop terá métricas próprias para coluna centralizada, largura máxima, padding lateral, espaço superior, body e headings. O perfil mobile manterá a escala maior e o espaço necessário para teclado e interação por toque.
- O cache do stylesheet no `NoteEditor` deverá considerar o perfil de layout além de `ColorScheme` e `documentPadding`, para nunca reutilizar um stylesheet mobile em desktop ou vice-versa.
- A `NoteToolbar` continua ancorada na parte inferior da viewport. No desktop, ela deve manter sua superfície contextual e não deve ser confundida com o `DesktopNoteChrome` superior.
- O chrome superior não deve recriar a `NoteEditorSession` nem observar o documento por um caminho paralelo. Indicadores de sync, foco e erro devem derivar dos providers e da sessão existente.
- O `NoteSyncSession` e o `NoteSessionCoordinator` ficam fora da árvore visual. A implementação deve apenas montar/desmontar widgets corretamente para que a sessão existente continue sendo aberta uma vez por `noteId` e descartada com segurança.

### Fluxo visual do desktop

```text
AdaptiveNotesShell
├── DesktopSidebarSurface
│   ├── SidebarHeader
│   ├── NotesSearchAndFilters
│   ├── ScrollableNotesList
│   └── SidebarFooter
└── DesktopContentSurface
    └── NoteEditorScreen (desktop composition)
        ├── DesktopNoteChrome
        └── DesktopEditorViewport
            └── NoteEditor
                ├── SuperEditor
                ├── document overlays/components
                └── NoteToolbar contextual
```

Esse desenho é de composição, não de ownership de dados. A lista continua no fluxo `catalog`, a edição continua no fluxo `editor`, e a sincronização continua na sessão canônica.

### Contratos visuais específicos

- A sidebar inicia em aproximadamente 300 px, aceita 220–420 px e usa a viewport para reduzir o máximo em janelas menores.
- Controles de chrome e linhas de navegação usam aproximadamente 32 px de altura visual; componentes tocáveis devem preservar área efetiva adequada sem engrossar o desenho.
- O `DesktopNoteChrome` deve ser transparente ou usar a superfície do tema, sem `Card`, elevação ou sombra pesada. Ações de estado devem usar os componentes compartilhados do app.
- A viewport do editor usa uma coluna máxima próxima de 720–734 px, centralizada no espaço disponível depois da sidebar.
- O conteúdo não deve usar uma largura fixa menor que a viewport; em janelas estreitas, o padding reduz até o mínimo seguro.
- A coluna deve deixar espaço inferior suficiente para a `NoteToolbar`, sem cobrir o último bloco.
- O perfil mobile e o perfil desktop devem produzir o mesmo conteúdo e as mesmas operações para um mesmo Document Snapshot; somente a apresentação pode mudar.
- A seleção e o cursor devem usar os tokens do `ColorScheme`; não criar uma cor independente apenas para imitar o accent laranja do Writer.
- Blur é decorativo. O comportamento correto deve existir com uma superfície opaca/semitransparente quando o blur não estiver disponível.

## Testing Decisions

- Usar o shell desktop como seam principal de composição e testes de layout.
- Testar comportamento observável: largura mínima/máxima, resize, seleção, busca, filtros, criação de nota, navegação, abertura da nota, tema e foco.
- Testar a sidebar com listas vazias, carregamento, erro, busca sem resultado, favorito, seleção e reordenação sem perda de identidade visual.
- Testar o editor com texto longo, headings, listas, tasks, anexos, seleção, scroll e diferentes larguras de viewport.
- Testar light/dark e fallback sem blur; não testar valores internos de `BackdropFilter` ou pixels exatos de uma implementação específica.
- Testar que a toolbar contextual continua aberta durante navegação do cursor e que comandos continuam entrando pelo caminho de comandos do editor.
- Testar que a troca visual não altera o conteúdo do Document Snapshot nem cria writes diretos na Projection de tasks.
- Testar lifecycle de sessão em abertura, navegação, fechamento, reabertura e descarte do widget; não adicionar tabs sem estes testes.
- Usar como prior art os testes existentes de `note_editor_screen`, `note_toolbar`, `note_list_row`, `app_theme`, `app_colors`, sincronização de catálogo e `NoteSessionCoordinator`.
- Validar com `flutter analyze --no-pub` e testes Flutter focados antes de qualquer validação agregada.
- Executar testes desktop com viewport de pelo menos 1280×800 e 1440×900, cobrindo sidebar mínima, largura inicial e largura máxima.
- Fazer validação visual manual em Windows desktop, porque métricas de texto e composição do Flutter podem diferir da implementação CSS do Writer.

## Out of Scope

- Trocar Super Editor por CodeMirror, ProseMark ou outro editor.
- Adotar arquivos Markdown, workspace folders ou sincronização baseada em sistema de arquivos.
- Reintroduzir Yjs/YDoc, CRDT ou qualquer caminho legado de sincronização.
- Criar tabs na primeira implementação.
- Alterar o modelo de dados de Note, Document Snapshot, Block, Task ou Projection.
- Criar funcionalidades de `Pinned`, `Recents` ou árvore de diretórios do Writer.
- Adicionar novas capacidades de documento, como tabelas, drawing, áudio, scanning, cor de texto ou highlight.
- Alterar o comportamento de compartilhamento, permissões, anexos, notificações ou preferências de negócio.
- Fazer uma migração global da paleta Joi/Apple para laranja.
- Adicionar dependências apenas para reproduzir blur, ícones ou layout já suportados pelas dependências atuais.

## Further Notes

- A referência visual é o repositório público [writer-computer](https://github.com/joelbqz/writer-computer), especialmente o layout principal, a sidebar, os tokens CSS e o editor centralizado.
- A especificação deve ser executada em camadas. Cada camada precisa produzir um desktop funcional antes da próxima.
- O working tree atual contém alterações de arquitetura e contrato REST/OT não relacionadas a esta especificação. A implementação deve preservar essas alterações e evitar misturar a mudança visual com a migração estrutural em andamento.
- O primeiro marco de sucesso é: “SupaNotes desktop parece uma aplicação de escrita contínua, com sidebar densa e editor centralizado, mantendo o comportamento atual de notas e sincronização”.
