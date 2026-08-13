# Notes: referência de arquivos, classes e métodos

Este documento é a leitura detalhada do módulo `notes`. Ele descreve o código
ativo dentro dos submódulos novos. Os arquivos em `notes/data`, `notes/domain`
e `notes/presentation` que só fazem `export` são compatibilidade temporária e
não têm comportamento próprio.

## Como ler a tabela

“Métodos-chave” são os pontos que definem o contrato ou o ciclo de vida. Um
`build()` de widget apenas transforma estado em UI; a decisão que alimenta
esse estado é documentada no controller, provider ou repositório indicado.

## Catalog

| Arquivo | Classe/provider | Métodos-chave e motivo |
| --- | --- | --- |
| `catalog/model/note_model.dart` | `NoteModel` | `copyWith` cria uma versão de apresentação sem mutar a linha; o modelo representa nota + permissões + preferências já combinadas. |
| `catalog/model/note_strings.dart` | `NoteStrings` | Mantém mensagens longas e compartilhadas fora dos widgets. |
| `catalog/data/local/notes_local_repository.dart` | `NotesLocalRepository` | `watchActiveNotes` e `watchNoteById` leem o catálogo reativamente; `createNoteWithId`, `updateNoteRaw`, `softDeleteNote`, `hardDeleteNote` preservam o ciclo local-first. |
| `catalog/data/notes_repository.dart` | `INotesRepository`, `NotesRepository` | Interface usada por UI; `watchNotes` e `watchNoteById` expõem leitura; `createLocalNote` cria antes da navegação; `saveSnapshot` mantém conteúdo e links juntos; `deleteIfEmptyOrTombstone` diferencia nota local vazia de nota remota. |
| `catalog/data/note_catalog_sync.dart` | `NoteCatalogSync`, `noteCatalogSyncProvider` | `pullRemoteNotes` hidrata o catálogo; `_pullRemoteNote` ignora notas ativas e usa `AppDatabase.saveRemoteNote` para gravar o snapshot confirmado e os metadados da nota atomicamente. A atualização remota usa comparação de versão e recusa linhas sujas, excluídas, ausentes ou alteradas durante a requisição. |
| `catalog/application/notes_providers.dart` | `activeNotesProvider`, `noteWithTasksProvider` | Convertem os streams do repositório em `AsyncValue`; a tela não decide como consultar Drift. |
| `catalog/presentation/notes_list_screen.dart` | `NotesListScreen` | `_openSearch`/`_closeSearch` controlam somente UI; `_onSearchQueryChanged` aplica debounce; `_openNewNote`, `_deleteNote`, `_toggleFavorite` delegam ao repositório; `build` combina `AsyncValue` com grid/lista. |
| `catalog/presentation/widgets/notes_grid_view.dart` | `NotesGridView` | `build` apenas distribui `NoteCard` em grid; callbacks continuam pertencendo à tela. |
| `catalog/presentation/widgets/notes_list_view.dart` | `NotesListView` | `build` distribui `NoteListRow` em lista. |
| `catalog/presentation/widgets/note_card.dart` | `NoteCard` | `build` exibe resumo; `_confirmDelete` pede confirmação antes de delegar exclusão. |
| `catalog/presentation/widgets/note_list_row.dart` | `NoteListRow` | `build` exibe título, excerpt, favorito e compartilhamento; não busca dados adicionais. |
| `catalog/presentation/widgets/notes_more_menu.dart` | `NotesMoreMenu` | `build` oferece modo de exibição, settings e logout; não implementa essas ações. |

## Editor: application

| Arquivo | Classe/provider | Métodos-chave e motivo |
| --- | --- | --- |
| `editor/application/note_editor_controller.dart` | `NoteEditorController` | É a fachada mutável do SuperEditor; `completeTaskInEditor`, `reopenTaskInEditor` e `updateTaskMetadataInEditor` alteram blocos, não DAOs; uploads usam o repositório de anexos e protegem callbacks obsoletos. |
| `editor/application/note_editor_delegate.dart` | `NoteEditorDelegate` | Agrupa callbacks de task da tela; mantém `NoteEditor` desacoplado de snackbar, sheet e router. |
| `editor/application/note_editor_session.dart` | `NoteEditorSession` | Une controller + `NoteEditorSyncHandle`; `start`, `flushNow` e `dispose` delegam sync e depois descartam controller. É o owner de uma nota aberta. |
| `editor/application/note_editor_provider.dart` | `_noteEditorSessionOwnerProvider`, `noteEditorSessionProvider`, `noteEditorSessionStatusProvider`, `noteEditorControllerProvider` | Abrem uma sessão por `noteId`, verificam disposal antes/depois de async, acompanham permissão read-only e publicam estado sem criar um segundo owner. |

## Editor: document

| Arquivo | Classe | Métodos-chave e motivo |
| --- | --- | --- |
| `editor/document/note_node.dart` | `NoteNode` | Modelo intermediário para blocos do snapshot; `copyWith` permite transformação imutável durante decode/projeção. |
| `editor/document/attachment_nodes.dart` | `AttachmentNode`, `DocumentAttachmentNode`, `RichLinkNode` | Implementam nós não textuais do SuperEditor; `copy`, equivalência e substituição de metadata são necessários para reconciliação sem perder identidade. |
| `editor/document/note_document_codec.dart` | `NoteDocumentCodec` | `encodeDocument`/`encodeNode` produzem JSON canônico; `decodeNode`/`decodeBlock` reconstroem nós; `encodeAttributedTextToDelta` e `attributedFromDelta` preservam formatação; helpers de attribution normalizam o contrato com Go. Este arquivo é a seam entre SuperEditor e REST/OT. |
| `editor/document/document_projection_applier.dart` | `DocumentProjectionApplier` | `rebuildFromSnapshot` aplica snapshot + operações locais; `applyFullDocument` e `applyOperationPayload` transformam mudanças em comandos do editor; preserva seleção e atualiza texto/metadata sem disparar captura remota. |
| `editor/document/note_editor_commands.dart` | `NoteEditorCommands`, `RandomDividerConversionReaction` | Comandos de alto nível para inserir task, divider, links e metadata; reactions automatizam padrões de digitação sem colocar regra no widget. |
| `editor/document/keep_first_line_as_title_reaction.dart` | `KeepFirstLineAsTitleReaction` | Mantém a convenção de título derivado do primeiro bloco; não cria campo `title` independente. |

## Editor: sync

| Arquivo | Classe | Métodos-chave e motivo |
| --- | --- | --- |
| `editor/sync/note_sync_client.dart` | DTOs e `NoteSyncClient` | `getDocument`, `listNotes`, `getOperationsSince`, `syncOperations` são somente transporte; `toJson` e factories mantêm o contrato HTTP; `_mapError` converte Dio para `NoteOperationsException`. |
| `editor/sync/editor_operation_capture.dart` | `OperationRequestData`, `EditorOperationCapture` | `start`/`stop` gerenciam listener; `buildMirror` cria estado comparável; `_onDocumentChanged` classifica alterações; diffs de texto/attribution geram operações pequenas em vez de snapshots completos. |
| `editor/sync/note_operation_contract.dart` | `NoteOperationKind`, `NoteOperationPayloads`, `NoteOperationContract` | Centraliza nomes wire, builders e validação local dos sete tipos de operação; o adapter rejeita payload inválido antes da outbox e o servidor continua sendo o owner autoritativo. |
| `editor/sync/note_operation_adapter.dart` | `NoteOperationAdapter` | `start` carrega revisão e hidrata; `setCaptureLocalOperations` alterna edição/read-only; `flushNow` esvazia debounce; `reconcile` aplica confirmação/remoto; `rebuildFromSnapshot` coordena applier + capture. É o adaptador entre editor mutável e outbox. |
| `editor/sync/note_operation_rebaser.dart` | `NoteOp`, `NoteOperationRebaser` | `rebase` mantém operações pendentes após remoto; `transformOp` resolve conflitos por bloco/posição; uma operação não aplicável retorna nula para não corromper o documento. |
| `editor/sync/note_sync_session.dart` | `NoteSyncSession` | `start` inicia adapter, materialização local do documento efetivo e polling; `pollNow` busca remoto; `flushNow` garante envio imediato; `_runSyncOperation` serializa concorrência; `dispose` espera filas e fecha recursos; `isProtocolError` separa erro definitivo de falha transitória. |
| `editor/sync/note_session_coordinator.dart` | `NoteSessionCoordinator<T>`, `NoteSessionSnapshot` | `open` reutiliza sessão pendente/pronta; `close` aguarda fechamento; `statusOf`, `statusChangesOf` e `snapshot` expõem uma visão consistente; `closeAll` encerra logout. O mapa usa identidade para impedir cleanup obsoleto. |
| `editor/sync/note_session_handle.dart` | `NoteSessionHandle`, `NoteEditorSyncHandle`, `NoteSessionStatus` | Interface mínima do ciclo de vida; permite testar coordinator com fake e evita que ele conheça `NoteSyncSession`. |
| `editor/sync/note_session_activity_tracker.dart` | `NoteSessionActivityTracker` | `markActive`/`markInactive` e `isActive` impedem catalog sync de sobrescrever nota aberta. |

## Attachments, sharing e preferences

| Arquivo | Classe/provider | Motivo |
| --- | --- | --- |
| `attachments/model/attachment_model.dart` | `AttachmentModel`, enums | Modelo de leitura com status e tipo derivados de MIME. |
| `attachments/data/local/attachments_local_repository.dart` | `AttachmentsLocalRepository` | Encapsula DAO e streams locais para upload resiliente. |
| `attachments/data/attachments_repository.dart` | `AttachmentsRepository`, providers | Cria estado `uploading`, envia multipart e marca `failed`/URL; a UI nunca conhece Dio. |
| `sharing/model/share_model.dart`, `share_permission.dart` | `ShareModel`, `SharePermission` | Contrato de permissão; `toJson`/`fromJson` mantém API estável. |
| `sharing/data/shares_repository.dart` | `SharesRepository` | `shareNote`, `listShares`, `deleteShare` são a única porta HTTP de compartilhamento. |
| `sharing/application/share_list_controller.dart` | `shareListProvider` | Fetch único por `noteId`; a lista não é global. |
| `sharing/application/share_note_controller.dart` | `ShareNoteController` | `share`/`revoke` usam contador de operação para uma resposta antiga não substituir a nova. |
| `sharing/presentation/` | `ShareNoteSheet`, `ShareListSection` | Formulário e lista; delegam mutação aos controllers. |
| `preferences/data/user_note_preferences_repository.dart` | `UserNotePreferencesRepository` | Stream e escritas de preferências por usuário/nota. |
| `preferences/application/note_preferences_mutation_controller.dart` | `NotePreferenceMutationController` | `setHideCompleted`, `setCollapseImages`, `_rollbackIfStillCurrent` e versões por campo evitam rollback de uma escolha mais nova. |

## O que não deve ser feito

- Tarefas não têm uma projeção relacional: o bloco no documento canônico é a
  fonte de leitura e escrita.
- Não criar `NoteSyncSession` dentro de um widget ou provider secundário.
- Não escrever `tasks` para editar conteúdo; produza uma operação do documento.
- Não tratar `NoteSyncClient` como regra de negócio; ele só transporta DTOs.
