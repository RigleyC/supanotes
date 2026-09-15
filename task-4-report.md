# Task 4 — feed compatível e bootstrap versionado

## Implementado

- `SyncChange` e `SyncInboxEntry` aceitam `taskId` opcional; eventos de task não
  exigem `noteId`.
- `SyncFeedClient` usa `scope=notes` por omissão sem enviar query extra e só
  envia `scope=all` quando solicitado. O worker troca para `all` apenas depois
  de `bootstrapVersion >= 2`.
- `SyncInbox` e `SyncFeedCursors` declaram as novas colunas; o cursor e a
  versão são monotônicos. O checkpoint aceita uma função de escrita no mesmo
  `AppDatabase.transaction`, mantendo a versão abaixo de 2 quando o snapshot
  falha.
- O coordenador ganhou `bootstrapTasks`, `applyTaskChanged` e
  `applyTaskDeleted`, preservando o roteamento de notas e mantendo eventos
  desconhecidos pendentes quando há erro de protocolo.
- `NoteCatalogSync` separa `fetchRemoteNotes` de
  `applyRemoteNotesSnapshot(InTransaction)`, permitindo juntar o snapshot de
  notas ao bootstrap de tasks antes do checkpoint final.
- O backend já presente da Task 3 mantém `scope=notes` como filtro padrão,
  `scope=all` para os dois recursos e 400 para escopo inválido.

## Validação

Passaram, serialmente com `--concurrency=1`:

```text
flutter test test/core/sync/sync_feed_client_test.dart \
  test/core/sync/sync_inbox_store_test.dart \
  test/core/sync/note_remote_sync_coordinator_test.dart \
  test/core/sync/sync_inbox_worker_test.dart \
  test/core/sync/multi_device_sync_e2e_test.dart \
  test/features/notes/data/note_catalog_sync_test.dart
```

Também passou o teste isolado do snapshot remoto e:

```text
go test ./internal/syncfeed -v
```

O teste PostgreSQL de integração foi descoberto e pulado porque
`SUPANOTES_SYNC_TEST_DATABASE_URL` não está configurada.

## Limite de schema no commit inicial

No commit inicial do Task 4, `schemaVersion` continuava em `31`; não eram
criadas as tabelas Drift de tasks nem aplicada a migração física v32. Esse
limite foi corrigido no fix round 1 abaixo. O rebuild legado 30→31 continua
reconstruindo as tabelas do inbox já com as colunas novas, enquanto bancos
físicos que já estavam em v31 recebem as colunas pela migração aditiva 31→32.

As alterações preexistentes em sqlc, `pubspec.lock` e arquivos gerados do
Windows foram preservadas fora deste escopo.

## Fix round 1

- `AppDatabase.schemaVersion` agora é `32`. A migração `31 -> 32` adiciona
  fisicamente `sync_feed_cursors.bootstrap_version` e `sync_inbox.task_id`
  quando ainda não existem; a migração legada `30 -> 31` continua reconstruindo
  as tabelas com as colunas completas e não as duplica.
- O caminho `31 -> 32` permanece exclusivo e aditivo para as colunas do feed.
  A Task 5 deve partir do schema físico `32` e fazer um único upgrade `32 -> 33`
  para tabelas/quarentena de tasks, sem acrescentar essas tabelas ao `31 -> 32`
  nem criar uma migração concorrente.
- `NoteRemoteSyncCoordinator` agora recebe um `fetchBootstrap` que busca e
  materializa o snapshot antes da transação. O retorno contém apenas callbacks
  de aplicação local (`applyNotesInTransaction` e, quando disponível,
  `applyTasksInTransaction`); a runtime usa `fetchRemoteNotes` e
  `applyRemoteNotesSnapshotInTransaction`, removendo a rede de dentro do
  checkpoint transacional.
- Adicionado teste de migração a partir de um banco físico v31 e teste de seam
  que verifica a ordem fetch → apply. O suporte opcional a tasks mantém a
  versão 2 bloqueada até que o snapshot traga seu aplicador transacional.

### Verificação do fix

Comando executado, serialmente:

```text
flutter test --concurrency=1 test/core/sync/sync_feed_client_test.dart \
  test/core/sync/sync_inbox_store_test.dart \
  test/core/sync/note_remote_sync_coordinator_test.dart \
  test/core/sync/sync_inbox_worker_test.dart \
  test/core/sync/multi_device_sync_e2e_test.dart \
  test/features/notes/data/note_catalog_sync_test.dart
```

Resultado: **PASS**, 46 testes.

Também foi executado `dart analyze` nos arquivos Dart alterados; não houve
erros de analyzer (somente infos de documentação/style já existentes). O
`git -c core.whitespace=cr-at-eol diff --check` não encontrou whitespace
inválido. A validação PostgreSQL do feed continua dependente de
`SUPANOTES_SYNC_TEST_DATABASE_URL`, conforme registrado acima.

## Fix round 2

- O marcador do bootstrap usa `scope=all` quando o bootstrap de tasks está
  habilitado, para ancorar o cursor no maior watermark combinado de notas e
  tasks. Clientes sem tasks continuam usando `scope=notes`.
- As mudanças retornadas pelo marker não são ingeridas: o coordenador usa
  somente o `watermark`; o snapshot remoto continua sendo buscado antes e
  aplicado dentro da transação de checkpoint, e o worker lê eventos posteriores
  depois de habilitar `scope=all`.
- O teste do coordenador cobre o marker `all`, garante que uma mudança histórica
  do próprio marker não seja aplicada e mantém a cobertura do caminho `notes`.

### Verificação do fix round 2

Executada serialmente com `--concurrency=1`:

```text
flutter test --no-pub --concurrency=1 test/core/sync/sync_feed_client_test.dart \
  test/core/sync/sync_inbox_store_test.dart \
  test/core/sync/note_remote_sync_coordinator_test.dart \
  test/core/sync/sync_inbox_worker_test.dart \
  test/core/sync/multi_device_sync_e2e_test.dart \
  test/features/notes/data/note_catalog_sync_test.dart
```

Resultado: **PASS**, 46 testes. O analyzer focado terminou com exit code 0;
foram reportadas apenas infos preexistentes de documentação/style. O diff
check com `core.whitespace=cr-at-eol` também passou sem whitespace inválido.
