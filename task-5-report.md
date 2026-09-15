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
