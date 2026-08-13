# Editor de nota e REST/OT

O editor tem uma fronteira importante: widgets mostram um `MutableDocument`,
mas somente a sessão converte mudanças em operações e sincroniza dados.

## Subpastas

| Pasta | Dono | Responsabilidade |
| --- | --- | --- |
| `application/` | Riverpod e sessão | abre uma sessão canônica por `noteId` |
| `document/` | formato do documento | nós, codec, comandos e aplicação de snapshot |
| `sync/` | sincronização de uma nota aberta | captura, outbox, rebase, polling e estados |
| `presentation/` | interface SuperEditor | tela, toolbar, slash commands e renderizadores |

## Ciclo de vida

1. `noteEditorSessionProvider` pede uma sessão ao `NoteSessionCoordinator`.
2. `NoteEditorSession` cria e possui o `NoteEditorController` e
   `NoteSyncSession`.
3. `NoteSyncSession.start()` hidrata o documento confirmado e as operações
   pendentes locais, marca a sessão como pronta e inicia a materialização do
   documento efetivo, o sync e o polling em segundo plano. Assim, latência de
   rede não bloqueia o primeiro frame do editor.
4. O adapter captura operações do editor, grava a outbox e pede sync.
5. Ao fechar, a sessão aguarda filas, tenta flush, para polling e descarta os
   recursos. Uma finalização atrasada não pode remover uma nova sessão do mesmo
   `noteId`.

## Documentos e métodos-chave

- `document/note_document_codec.dart`: converte entre o JSON do snapshot e
  nós SuperEditor. Mude-o quando o schema de um bloco mudar.
- `document/document_projection_applier.dart`: reconstrói o editor a partir do
  snapshot mais operações locais ainda pendentes.
- `sync/editor_operation_capture.dart`: observa o documento e produz operações
  semânticas; não faz HTTP.
- `sync/note_operation_adapter.dart`: aplica debounce, persiste operações,
  hidrata e reconcilia o documento.
- `sync/note_operation_rebaser.dart`: ajusta operações locais restantes após
  operações remotas ou confirmação de servidor.
- `sync/note_sync_session.dart`: serializa sync/polling e materialização local,
  e expõe os
  estados `opening`, `ready`, `syncing`, `syncError`, `error` e `closed`.

## Por que não sincronizar no widget?

Widgets podem ser reconstruídos ou descartados por navegação. A sessão precisa
sobreviver a essas transições de forma controlada, preservar a identidade do
documento e garantir que somente um owner faça polling e flush.

## Ligações

- Outbox e HTTP: [core sync](../../../core/sync/README.md).
- Tasks e notificações: [tasks](../../tasks/README.md).
- Aplicação no servidor: [backend noteoperations](../../../../backend/internal/noteoperations/README.md).
