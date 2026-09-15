# Task 5 — persistência local de tasks independentes

## Entregue

- `Tasks` e `PendingTaskOperations` foram adicionadas ao schema Drift.
- `TasksDao` observa tasks por proprietário, esconde tombstones da lista aberta,
  ordena a agenda e mantém a outbox ordenada por task.
- `TaskRepository` grava a mutação otimista e a operação com `operationId`,
  `payloadHash` e `scheduleGeneration` na mesma transação SQLite. Criação,
  atualização, conclusão, reabertura e exclusão mantêm a representação
  canônica de `Task`.
- A migração física é schema 32→33. Restos de `tasks`, `task_completions` e
  `local_task_completions` são renomeados para quarentena versionada e nunca
  são descartados. Linhas não vazias deixam o diagnóstico em estado
  `blocked`, sem impedir o banco de notas de abrir.
- Snapshots remotos são aplicados mantendo o outbox e rebasing as operações
  locais pendentes sobre o snapshot; a confirmação por `operationId` ficará a
  cargo do worker da Task 6.

## Fix round 1

- `TaskRepository.update` agora deriva a geração da agenda a partir do task
  local atual. Alterações em `dueDate`, `hasTime` ou `recurrenceRule` usam
  `withSchedule`, incrementam a geração e limpam `completions`; alterações
  apenas em `reminder` preservam o histórico. A geração e os completions do
  draft não são mais confiados, e limpezas explícitas de agenda continuam
  válidas.
- `applyRemoteTask` compara cada operação pendente com a geração corrente:
  patches de agenda precisam ser o próximo incremento e as demais operações
  precisam observar a geração atual. Operações incompatíveis não alteram o
  snapshot remoto, permanecem na outbox com status `blocked` e ficam expostas
  em `lastRebaseDiagnostic` para o fluxo de conflito da Task 6.
- `readTaskStorageDiagnostic` agora varre todos os nomes com os prefixos de
  quarentena, incluindo tabelas sufixadas como
  `tasks_legacy_quarantine_v32_1`.

Regressões adicionadas para geração derivada, conflito/rebase compatível e
quarentena sufixada.

```text
dart format lib/features/tasks/data/task_repository.dart lib/core/database/database.dart \
  test/features/tasks/data/task_repository_test.dart test/core/database/daos/tasks_dao_test.dart
flutter test --no-pub --concurrency=1 test/features/tasks/data/task_repository_test.dart
flutter test --no-pub --concurrency=1 test/core/database/daos/tasks_dao_test.dart
dart analyze lib/features/tasks/data/task_repository.dart lib/core/database/database.dart \
  test/features/tasks/data/task_repository_test.dart test/core/database/daos/tasks_dao_test.dart
```

Os dois grupos de testes passaram (7 testes de repositório e 4 de DAO). A
análise focada não encontrou erros; somente infos/lints já existentes e
documentação de API foram reportados.

## Verificação

```text
dart run build_runner build --delete-conflicting-outputs
flutter test --no-pub --concurrency=1 \
  test/core/database/daos/tasks_dao_test.dart \
  test/features/tasks/data/task_repository_test.dart
```

O build do Drift e os 7 testes focados passaram. O teste de migração cobre
quarentena não vazia, preservação do novo schema e diagnóstico bloqueado.

## Limitações conhecidas

- O worker HTTP/outbox, confirmação idempotente, bootstrap remoto e aplicação
  do feed de tasks são escopo da Task 6 e seguintes.
- Não houve validação visual ou de dispositivo; este task só cobre dados,
  transações, migração e contratos locais.
- O relatório não afirma `flutter analyze` global limpo: a análise focada não
  encontrou erros nos arquivos de Task 5, mas mantém apenas infos/lints
  existentes no restante do projeto.
