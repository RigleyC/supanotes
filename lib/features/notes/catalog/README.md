# Notes catalog

Este submódulo trata a nota fora do editor: catálogo, criação local, remoção,
busca e hidratação remota.

## Papéis

- `data/notes_repository.dart`: interface `INotesRepository` e implementação
  que compõe DAOs locais. Métodos como `createLocalNote`, `watchNotes`,
  `watchNoteWithTasks` é a porta para telas. O ciclo de vida local usa
  `NoteLifecycleStore` diretamente.
- `data/local/notes_local_repository.dart`: chamadas de baixo nível ao DAO,
  sempre limitadas ao usuário autenticado.
- `data/note_catalog_sync.dart`: sincroniza todas as páginas do catálogo e
  baixa snapshots das notas que não estão com uma sessão de editor ativa,
  calcula `content`, `excerpt` e tarefas com `NoteDocumentProjector` e usa
  `AppDatabase.saveRemoteNote` para persistir a linha do catálogo, o snapshot
  e as projeções na mesma transação. A sincronização é iniciada no escopo do
  app e roda em segundo plano; abrir uma nota lê o estado local e não espera a
  rede. Uma edição local, exclusão ou versão concorrente faz a hidratação
  remota ser ignorada.
- `model/`: `NoteModel`, `NoteWithTasks` e textos compartilhados do catálogo.
- `application/notes_providers.dart`: streams reativos para lista e detalhe.
- `presentation/`: shell desktop, lista e widgets de cartão/barra lateral.

## Por que criar localmente antes de abrir?

O usuário pode abrir e editar sem rede. A nota recebe um ID local estável antes
da navegação, mas não aparece no catálogo enquanto não tiver conteúdo. Se o
usuário sair sem escrever, `NoteLifecycleStore` remove todo o agregado local
em uma transação, somente quando não há conteúdo, projeções ou estado de sync.
Quando existe conteúdo, a primeira operação aceita pelo REST/OT marca a linha
como cópia remota e a nota passa a ter o ciclo de vida normal.

## Ligações

- Abrir uma nota navega para o [editor](../editor/README.md).
- `NoteCatalogSync` respeita `NoteSessionActivityTracker`: nunca deve
  sobrescrever uma nota enquanto uma sessão local está editando-a. A gravação
  remota também usa uma comparação de versão para proteger uma edição feita
  enquanto a requisição estava em andamento.
- Tarefas para a lista são leitura da projeção em [tasks](../../tasks/README.md).
