# Walkthrough — tasks independentes e abas Tasks/Notas

Data da verificação: 2026-09-16
Estado: implementação concluída; rollout ainda não aprovado

## O que foi entregue

O recurso separa as duas fontes de task sem criar uma autoridade duplicada:

- `TaskNode` continua dentro do snapshot REST/OT da nota e é alterado por
  operações do editor.
- `Task` é uma task independente, com cópia local em Drift, outbox durável e
  API própria para sincronização entre dispositivos do proprietário.
- A aba Tasks combina as duas fontes somente para leitura, com a opção
  **Mostrar tarefas das notas**. Essa combinação não é persistida como um
  terceiro modelo.
- A tela possui criação/edição de task independente, conclusão, reabertura,
  exclusão, histórico **Concluídas** e navegação de volta para a nota e o
  bloco de origem.
- O feed é compatível com clientes antigos: `scope=notes` continua sendo o
  padrão, enquanto clientes novos optam por `scope=all` depois do bootstrap.
- A migração PostgreSQL e a migração Drift preservam remanescentes legados em
  quarentena; nenhum remanescente é promovido automaticamente.

## Gates executados

Os comandos foram executados no checkout compartilhado em `master`. Não foram
adicionados testes de pixels, geometria, screenshot ou aparência visual.

| Gate | Resultado | Evidência ou limitação |
| --- | --- | --- |
| `flutter test test/features/tasks/domain test/features/tasks/data test/features/tasks/application test/core/sync test/core/database/daos/tasks_dao_test.dart` | PASS | 171 testes passaram. Os warnings de múltiplas instâncias do Drift apareceram durante os testes, mas não causaram falha. |
| `flutter test test/core/router/app_router_test.dart test/features/tasks/presentation` | PASS | 56 testes passaram, cobrindo destinos de rota, filtro, histórico, editor e callbacks. |
| `go test ./...` em `backend` | PASS | Todos os pacotes passaram; pacotes sem testes foram reportados como tal. |
| `go vet ./...` em `backend` | PASS | Nenhum finding. |
| `git diff --check` | PASS | Nenhum erro de whitespace. Os avisos LF/CRLF referem-se a arquivos sujos preexistentes. |
| `flutter analyze` | BLOQUEADO | Exit code 1 por `integration_test/full_suite_test.dart:231`, que chama o método inexistente `loadPendingProjection` fora da feature. O checkout também reporta 2.676 infos/warnings existentes. |

Uma análise direcionada dos arquivos de tasks/roteamento não apontou erro de
compilação da feature, mas também retorna exit code 1 por warnings/infos de
lint. Isso não substitui a correção do erro do gate global.

## Gate de migração isolada

O gate não foi marcado como PASS. A tentativa solicitada não pôde iniciar o
ambiente descartável:

```text
make -C backend dev-db-up
The term 'make' is not recognized as a name of a cmdlet...
```

O mesmo alvo pelo Git Bash também ficou bloqueado:

```text
/usr/bin/bash: line 1: make: command not found
```

As verificações de Docker igualmente retornaram que `docker` não está
disponível. Sem `make`, Docker/Compose e um DSN PostgreSQL descartável, não foi
executado `migrate-up`, não foram conferidos nomes/contagens de quarentena e
não foi feito restore rehearsal. Nenhum comando de limpeza ou alteração de
produção foi executado.

Os testes de migração foram executados explicitamente:

```text
go test -v ./internal/tasks -run 'TestTaskMigration'
--- SKIP: TestTaskMigration
  SUPANOTES_SYNC_TEST_DATABASE_URL is not configured
--- SKIP: TestTaskMigrationQuarantineAndRollbackGuards
  SUPANOTES_TASK_MIGRATION_TEST_DATABASE_URL is not configured
PASS
```

Esse `PASS` é apenas o resultado do processo com os testes de integração
omitidos; ele não é evidência de que a migração PostgreSQL foi aplicada.

## Checklist de revisão da implementação

As etapas T1–T11 foram concluídas em commits separados e passaram revisão
focada antes desta verificação final. O HEAD verificado é `4a42c03e`.

- [x] Contratos de `Task`, operações, geração de agenda e histórico cobertos.
- [x] Schema PostgreSQL independente, log idempotente e quarentena legada
  implementados com guards de rollback.
- [x] Feed compatível, bootstrap versionado, confirmação de operações e
  conflitos de `scheduleGeneration` cobertos por código e testes.
- [x] Drift local, outbox, rebase de operações e quarentena SQLite cobertos.
- [x] Reader de `NoteTask` dedicado; DTOs de listagem não reutilizam o reader
  de notificações.
- [x] Visibilidade de notas, identidade de notificação por origem e
  invalidação temporal explicitamente testadas.
- [x] Tela Tasks, histórico, editor independente e navegação em duas abas
  implementados sem asserções visuais.
- [x] Documentação de ownership, compatibilidade e retenção atualizada.
- [x] Arquivos gerados de sqlc/Drift foram tratados pelos comandos do projeto
  durante a implementação; não foram editados manualmente nesta etapa
  documental.
- [ ] Aprovação operacional da migração: pendente de banco descartável,
  backup/export, restore rehearsal, retenção e contagens verificadas.
- [ ] Gate global do analyzer: pendente da referência quebrada no teste de
  integração fora da feature.

## Rollout seguro

Antes de qualquer produção, executar em ambiente protegido e manter os
artefatos fora do repositório:

1. Criar backup PostgreSQL custom-format, lista do `pg_restore` e hashes.
2. Exportar `tasks` e `task_completions` legados, incluindo soft-deleted, e
   registrar contagens em transação `READ ONLY`.
3. Restaurar o backup em banco isolado e executar a migração ali.
4. Verificar que os remanescentes se chamam
   `tasks_legacy_quarantine_v31` e
   `task_completions_legacy_quarantine_v31`, conferindo suas contagens e a
   criação das novas tabelas independentes.
5. Executar os testes PostgreSQL com DSNs descartáveis e repetir o restore
   rehearsal antes de qualquer cutover.
6. Manter clientes antigos em `scope=notes`; habilitar o bootstrap de tasks e
   `scope=all` somente para clientes compatíveis.

Títulos, conteúdo de notas, e-mails, tokens, URLs de banco e dumps não devem
ser colocados neste repositório ou neste walkthrough.

## Rollback

- Para defeito de aplicação, fazer rollback da versão da aplicação e manter
  as duas fontes de dados intactas. Não reativar readers legados nem converter
  uma linha relacional em `TaskNode`.
- O down migration PostgreSQL só pode ser usado quando as tabelas independentes
  e o log de operações estiverem vazios e não existirem eventos
  `task_changed`/`task_deleted`. O próprio migration aborta dentro de uma
  transação se qualquer guard falhar.
- Se um guard falhar, preservar tasks independentes, operações e quarentena,
  fazer somente rollback da aplicação e abrir uma nova decisão de migração.
  Nunca usar `migrate force` para contornar o guard e nunca apagar exports para
  fazê-lo passar.
- No dispositivo, preservar snapshots e outbox de notas. A quarentena SQLite
  não deve ser removida nem o banco local deve ser apagado como estratégia de
  recuperação; qualquer remoção exige retenção aprovada e confirmação de que
  não é a tabela independente atual.

Nenhum rollback foi executado durante esta verificação.

## Próximos gates necessários

1. Disponibilizar `make`/Docker e DSNs de bancos descartáveis, executar a
   migração isolada e o restore rehearsal.
2. Corrigir ou formalizar a exceção para
   `integration_test/full_suite_test.dart:231`; até lá o analyzer global não é
   um gate verde.
3. Repetir os gates e só então registrar a aprovação operacional do rollout.
