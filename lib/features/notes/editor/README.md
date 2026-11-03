# Editor de nota e REST/OT

O editor é o AppFlowy Editor. A fronteira importante: widgets mostram um
`EditorState`, mas somente a sessão converte mudanças em operações e
sincroniza dados. O formato sincronizado é uma lista plana de blocos
(`NoteBlock`); o AppFlowy é só a visão dela.

## Subpastas

| Pasta | Dono | Responsabilidade |
| --- | --- | --- |
| `application/` | Riverpod e sessão | abre uma sessão canônica por `noteId`; controller de tarefas e anexos |
| `document/` | formato do documento | `NoteBlock`, diff, aplicação de operações, validação do contrato |
| `appflowy/` | ponte com o editor | codec blocos ↔ nós, adapter de sync, blocos customizados, comandos de formatação |
| `sync/` | sincronização de uma nota aberta | outbox, rebase, sessão e estados |
| `presentation/` | interface | tela, toolbar, sugestões `@` e renderizadores de anexo |

## Ciclo de vida

1. `noteEditorSessionProvider` pede uma sessão ao `NoteSessionCoordinator`.
2. `NoteEditorSession` cria e possui o `NoteEditorController` (que possui o
   `NoteEditorState`) e a `NoteSyncSession` com um `AppFlowyNoteAdapter`.
3. `NoteSyncSession.start()` hidrata o documento confirmado mais as operações
   pendentes locais (`projectNoteBlocks`) e marca a sessão como pronta; sync
   roda em segundo plano, sem bloquear o primeiro frame.
4. A cada transação local, o adapter relê só os nós tocados, compara a lista
   de blocos (`diffNoteBlocks`) e grava as operações na outbox.
5. Mudanças remotas chegam por `reconcileRemote`: o documento efetivo é
   reprojetado e aplicado como transação remota (sem eco, fora do undo),
   preservando o caret.
6. Ao fechar, a sessão aguarda filas, tenta flush e descarta os recursos.

## Documentos e métodos-chave

- `document/note_blocks.dart`: `NoteBlock`, `applyNoteOperation` (mesma
  semântica do servidor), `projectNoteBlocks` e `diffNoteBlocks`.
- `document/note_document_codec.dart`: valida snapshots e blocos contra o
  contrato (`contracts/note_document/corpus.json`). Mude-o quando o schema
  de um bloco mudar.
- `appflowy/note_appflowy_codec.dart`: blocos ↔ árvore do AppFlowy. Itens de
  lista e tarefas com `indent` viram filhos; o id estável fica no atributo
  `blockId`; itálico é guardado como `italics`.
- `appflowy/appflowy_note_adapter.dart`: captura, persistência e
  reconciliação.
- `appflowy/note_format_commands.dart`: toolbar (estilos, listas, tarefas,
  recuo, divisória) reescrevendo só os blocos de topo tocados, sem reordenar.
- `appflowy/note_editor_state.dart`: impede editar tarefas concluídas
  ocultas.
- `sync/note_operation_rebaser.dart`: ajusta operações locais restantes após
  operações remotas ou confirmação do servidor.

## Por que não sincronizar no widget?

Widgets podem ser reconstruídos ou descartados por navegação. A sessão precisa
sobreviver a essas transições de forma controlada, preservar a identidade do
documento e garantir que somente um owner faça flush.

## Ligações

- Outbox e HTTP: [core sync](../../../core/sync/README.md).
- Tasks e notificações: [tasks](../../tasks/README.md).
- Aplicação no servidor: [backend noteoperations](../../../../backend/internal/noteoperations/README.md).
