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

## Limite de schema

`schemaVersion` continua em `31`; não foram criadas as tabelas Drift de tasks
nem aplicada a migração física v32. Como as declarações tipadas novas precisam
ser utilizáveis no upgrade legado exercitado pelos testes atuais, o rebuild
existente 30→31 passa a reconstruir as tabelas do inbox já com as colunas
novas, preenchendo valores padrão. A Task 5 deve consolidar esse formato na
migração física 31→32 junto das tabelas independentes e remover qualquer
duplicação do rebuild legado.

As alterações preexistentes em sqlc, `pubspec.lock` e arquivos gerados do
Windows foram preservadas fora deste escopo.
