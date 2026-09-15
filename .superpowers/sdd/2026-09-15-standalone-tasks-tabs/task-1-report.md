# Task 1 — Contratos de domínio

## Entregue

- `Task`: entidade independente imutável, validação de título/geração, JSON canônico, `copyWith` e `withSchedule`.
- `TaskOperation`: operações create/upsert/complete/reopen/delete com UUID, geração, revisão, payload e SHA-256 determinístico sobre JSON com chaves ordenadas.
- `TaskListItem` e `NoteTask`: união de apresentação entre task independente e adaptador de task de nota.
- `TaskHistoryEntry`: DTO para histórico de ocorrências concluídas.
- Testes de round-trip com completions, limpeza/incremento de geração e idempotência do hash.

## Verificação

Comando executado:

```text
flutter test test/features/tasks/domain/task_test.dart test/features/tasks/domain/task_operation_test.dart
```

Resultado: **PASS**, 4 testes.

Também foi executado `dart analyze` nos quatro arquivos de domínio; não restaram erros de compilação/análise (apenas infos de documentação/lint já não impeditivas).

## Observações

- Instantes são serializados em UTC ISO-8601; chaves de `completions` preservam o formato de wall-clock.
- O `flutter test` atualizou dependências/arquivos gerados localmente; essas alterações foram restauradas e não fazem parte deste commit.

## Fix round 1

Arquivos alterados:

- `lib/features/tasks/domain/task.dart`: `dueDate` agora usa a chave wall-clock canônica sem conversão UTC; instantes continuam UTC. `copyWith` usa sentinel para permitir limpar campos nulos; completions são canonicalizados/validados.
- `lib/features/tasks/domain/task_operation.dart`: payload é deep-snapshot imutável antes do hash e da exposição; `scheduledAt` das operações é canonicalizado.
- `lib/features/tasks/domain/task_list_item.dart`: construtores da união exigem fonte não nula.
- `test/features/tasks/domain/task_test.dart`, `task_operation_test.dart` e `task_list_item_test.dart`: regressões para os cinco achados da revisão.

Comandos e saída:

```text
dart format lib/features/tasks/domain/task.dart lib/features/tasks/domain/task_operation.dart lib/features/tasks/domain/task_list_item.dart test/features/tasks/domain/task_test.dart test/features/tasks/domain/task_operation_test.dart test/features/tasks/domain/task_list_item_test.dart
# Formatted 6 files (4 changed)

flutter test test/features/tasks/domain/task_test.dart test/features/tasks/domain/task_operation_test.dart test/features/tasks/domain/task_list_item_test.dart
# All tests passed! (10 tests)

dart analyze lib/features/tasks/domain/task.dart lib/features/tasks/domain/task_operation.dart lib/features/tasks/domain/task_list_item.dart lib/features/tasks/domain/task_history_entry.dart
# No analyzer errors (only existing documentation/style infos)
```

## Fix round 2

Arquivos alterados:

- `lib/features/tasks/domain/task.dart`: completions agora usam `hasTime` ao canonicalizar chaves; `withSchedule` distingue parâmetros omitidos de `null` explícito usando sentinel.
- `test/features/tasks/domain/task_test.dart`: regressões para chave all-day sem hora, atualização parcial preservando data/recorrência e limpeza explícita.

Comandos e saída:

```text
flutter test --concurrency=1 test/features/tasks/domain/task_test.dart
# All tests passed! (10 tests)

flutter test --concurrency=1 test/features/tasks/domain/task_operation_test.dart
# All tests passed! (3 tests)

flutter test --concurrency=1 test/features/tasks/domain/task_list_item_test.dart
# All tests passed! (1 test)

dart analyze lib/features/tasks/domain/task.dart lib/features/tasks/domain/task_operation.dart lib/features/tasks/domain/task_list_item.dart lib/features/tasks/domain/task_history_entry.dart
# No analyzer errors (only existing documentation/style infos)
```

A primeira execução combinada foi encerrada por falta de memória do
`flutter_tester`; os mesmos testes foram então executados serialmente com
`--concurrency=1` e passaram.

## Fix round 3

Arquivos alterados:

- `lib/features/tasks/domain/task.dart`: parsing lexical de `dueDate` e chaves `scheduledAt` rejeita offsets e preserva wall-clock; `scheduleGeneration` exige inteiro não-negativo; instantes JSON exigem offset/Z explícito e são normalizados para UTC.
- `lib/features/tasks/domain/task_operation.dart`: operações de ocorrência recebem `hasTime` obrigatório e usam a identidade de agenda correspondente, inclusive all-day.
- `test/features/tasks/domain/task_test.dart` e `task_operation_test.dart`: regressões para offsets, formatos de instante, geração inválida e ocorrência all-day/timed.

Comandos e saída:

```text
dart format lib/features/tasks/domain/task.dart lib/features/tasks/domain/task_operation.dart test/features/tasks/domain/task_test.dart test/features/tasks/domain/task_operation_test.dart
# Formatted successfully

flutter test --concurrency=1 test/features/tasks/domain/task_test.dart
# All tests passed! (12 tests)

flutter test --concurrency=1 test/features/tasks/domain/task_operation_test.dart
# All tests passed! (4 tests)

dart analyze lib/features/tasks/domain/task.dart lib/features/tasks/domain/task_operation.dart lib/features/tasks/domain/task_list_item.dart lib/features/tasks/domain/task_history_entry.dart
# No analyzer errors (only existing documentation/style infos)
```

Artefatos alterados pelo `flutter test` (`pubspec.lock` e arquivos gerados do
Windows) foram restaurados antes do commit.
