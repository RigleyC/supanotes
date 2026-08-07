# Note operations: servidor REST/OT

Este pacote é o lado servidor do contrato usado pelo editor Flutter. Ele é
dono de aceitar uma operação contra uma revisão, aplicar transformações e
persistir um novo snapshot canônico de forma atômica.

## Arquivos e responsabilidade

| Arquivo | Responsabilidade |
| --- | --- |
| `handler.go` | extrai usuário/nota da requisição e chama o service |
| `service.go` | autoriza, carrega estado, coordena transação e resposta |
| `repository.go` | lê e grava snapshots, revisões e operações no PostgreSQL |
| `operation.go` | tipos e parsing das operações REST/OT |
| `validator.go` | rejeita payloads e transições inválidas antes de persistir |
| `transformer.go` | transforma operações concorrentes para preservar intenção |
| `document.go` | aplica uma operação ao documento e deriva dados auxiliares |

## Contrato dos payloads

Os nomes wire e os builders usados pelo editor Flutter ficam em
`lib/features/notes/editor/sync/note_operation_contract.dart`. O Go é o owner
autoritativo da validação e da aplicação:

| Operação | Regra de payload relevante |
| --- | --- |
| `text_delta` | `ops` é uma lista de operações Delta e exige `blockId`. |
| `create_block` | `id`, `type` válido e `delta` são obrigatórios; `blockId`, quando enviado, deve coincidir com `id`. |
| `delete_block` | Exige `blockId`; a remoção usa esse ID como alvo. |
| `move_block` | Exige `blockId` no envelope e no payload, com o mesmo valor. |
| `set_block_type` | Exige um tipo de bloco permitido. |
| `set_block_metadata` | `metadata` deve ser objeto; valores `null` representam remoções explícitas. |
| `complete_task_occurrence` | `taskId` deve coincidir com `blockId`, `scheduledAt` não pode ser vazio e o alvo deve ser um bloco `task`. |

`test/fixtures/operation_contract.json` é consumido pelos testes Dart e Go.
Ele cobre um exemplo válido de cada operação e evita que os dois adapters
evoluam com vocabulários diferentes.

## Contrato de sync

1. O cliente envia `knownRevision`, `clientId` e uma lista ordenada de
   operações com `operationId`.
2. O service confirma acesso à nota e valida todas as operações.
3. O transformer ajusta operações contra alterações já confirmadas desde a
   revisão-base.
4. A transação persiste operações, revisão e `notes.document` juntos.
5. A resposta inclui operações aceitas, revisão final, operações remotas e o
   documento canônico. O cliente usa isso para rebase da própria outbox.

## Por que snapshot e log de operações?

O snapshot torna leitura e recuperação simples. O log permite detectar e
transformar concorrência entre a revisão-base do cliente e a revisão atual.
Os dois fazem parte do mesmo contrato; não atualize apenas um deles.

## Ligações

- Cliente: [Flutter editor](../../../lib/features/notes/editor/README.md).
- Outbox: [Flutter core sync](../../../lib/core/sync/README.md).
- Tarefas: o snapshot é projetado no cliente; não torne `tasks` uma segunda
  fonte de verdade para metadados do documento.

## Classes e métodos

- `Handler.RegisterRoutes` instala os endpoints `GET document`, `GET
  operations` e `POST operations:sync`; o handler apenas faz bind e converte
  erros para JSON HTTP.
- `Service.Sync` é o caso de uso principal: autentica o ator, carrega revisão,
  valida a lista, transforma operações, aplica o documento e commita uma
  transação única.
- `Repository` lê o snapshot, operações e permissões e grava a revisão. Ele é
  o único lugar que conhece detalhes pgx/SQL.
- `ValidateOperation` rejeita tipos, IDs, payloads e transições inválidas antes
  de chamar o documento.
- `TransformOperations`/`TransformOperation` resolve concorrência entre
  operações da revisão-base e operações já aceitas.
- `ApplyOperation` muda blocos do snapshot; `DeriveContentFromDocument` gera
  dados auxiliares sem se tornar uma segunda fonte de verdade.

Os testes de `document`, `operation`, `transformer`, `validator` e
`service` são a especificação executável desses contratos.
