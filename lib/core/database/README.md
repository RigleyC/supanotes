# Banco local: Drift SQLite

O banco local existe para o aplicativo funcionar offline e para consultas
reativas da UI. Ele não substitui a fonte de verdade remota do documento.

## Tabelas por papel

| Grupo | Tabelas | Por que existem |
| --- | --- | --- |
| Nota local | `notes`, `local_note_documents`, `note_links` | catálogo e último snapshot confirmado |
| Outbox REST/OT | `pending_note_operations`, `sync_sessions`, `note_sync_errors` | sobreviver a offline, retry e interrupção durante sync |
| Projeções | `tasks`, `task_completions` | filtros e lembretes rápidos, derivados do documento |
| Recursos | `attachments`, `user_note_preferences` | estado local de anexos e preferências por nota |

## Regras importantes

- `AppDatabase` é a única porta de migração e transação entre tabelas.
- Cada DAO encapsula consultas de uma tabela ou de um agregado de leitura.
- `TaskProjectionEngine` é o escritor de `tasks` para alterações que vêm do
  editor. A hidratação remota do catálogo usa `AppDatabase.saveRemoteNote`;
  não adicione uma escrita direta da UI para “resolver rápido”.
- A outbox usa operações ordenadas e revisão-base; não apague ou reordene
  operações fora de `NoteOperationsSyncService`.

## Próximos passos

- Protocolo e recuperação da outbox: [../sync](../sync/README.md).
- Quem cria documentos e projetos de tarefa: [Notes editor](../../features/notes/editor/README.md).

## Classes e métodos que definem a fronteira

- `AppDatabase.clearAllData`: limpa dados no logout; `saveProjectedDocument`
  coordena snapshot e projeções do editor na mesma transação; `saveRemoteNote`
  coordena linha do catálogo, snapshot, conteúdo e tarefas durante hidratação
  remota.
- `saveRemoteNote` aceita `InsertRemoteNote` ou `UpdateRemoteNote` com a
  versão esperada. A atualização falha sem escrever o agregado quando a linha
  foi alterada, ficou suja, foi excluída ou deixou de existir.
- `NotesDao.watchAllActiveNotes`, `watchNoteById` e `watchNoteWithTasks` são
  consultas reativas usadas pelo catálogo; `createNote`, `updateNote` e
  `softDeleteNote` implementam o ciclo de vida local. `updateRemoteNoteIfUnchanged`
  protege a hidratação remota por comparação de versão e
  `updateRemoteShareMetadata` centraliza a atualização de metadados de
  compartilhamento.
- `NoteOperationsDao` mantém snapshot confirmado, operações pendentes,
  `in_flight`, sessão persistida, erros e transações. Seus métodos
  `markInFlight`, `replacePendingOps`, `deleteAccepted` e `runInTransaction`
  existem para tornar retry e rebase idempotentes.
- `TasksDao.syncProjectedTasksForNoteTyped` substitui a projeção de uma nota;
  os métodos de leitura (`watchTodayTasks`, `watchOpenTasks`, `watchNoteTasks`)
  não são a fonte de escrita do editor.
- `TaskCompletionsDao` identifica uma ocorrência por tarefa/data agendada;
  `upsertCompletion` e `isOccurrenceCompleted` tornam retry seguro.
