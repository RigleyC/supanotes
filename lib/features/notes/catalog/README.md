# Notes catalog

Este submódulo trata a nota fora do editor: catálogo, criação local, remoção,
busca e hidratação remota.

## Papéis

- `data/notes_repository.dart`: interface `INotesRepository` e implementação
  que compõe DAOs locais. Métodos como `createLocalNote`, `watchNotes`,
  `watchNoteWithTasks` e `deleteIfEmptyOrTombstone` são a porta para telas.
- `data/local/notes_local_repository.dart`: chamadas de baixo nível ao DAO,
  sempre limitadas ao usuário autenticado.
- `data/note_catalog_sync.dart`: baixa snapshots das notas que não estão com
  uma sessão de editor ativa e chama a projeção de tarefas.
- `model/`: `NoteModel`, `NoteWithTasks` e textos compartilhados do catálogo.
- `application/notes_providers.dart`: streams reativos para lista e detalhe.
- `presentation/`: shell desktop, lista e widgets de cartão/barra lateral.

## Por que criar localmente antes de abrir?

O usuário pode abrir e editar sem rede. A nota começa sem cópia remota; se ela
ficar vazia, `deleteIfEmptyOrTombstone` decide entre apagar localmente e criar
um tombstone para uma nota que já existia no servidor.

## Ligações

- Abrir uma nota navega para o [editor](../editor/README.md).
- `NoteCatalogSync` respeita `NoteSessionActivityTracker`: nunca deve
  sobrescrever uma nota enquanto uma sessão local está editando-a.
- Tarefas para a lista são leitura da projeção em [tasks](../../tasks/README.md).
