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
