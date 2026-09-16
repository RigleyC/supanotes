# Backend: referência de pacotes e classes

## Padrão handler → service → repository

- `handler.go` conhece Echo, path/query/body e status HTTP.
- `service.go` conhece regras, autorização e transações.
- `repository.go` conhece SQLC/pgx e não decide apresentação HTTP.
- `*_test.go` prova cada seam com fakes ou PostgreSQL de integração.

## Pacotes

| Pacote/arquivos | Classes/funções | Motivo |
| --- | --- | --- |
| `internal/auth` | `Service`, `Handler`, `JWT` middleware | Une identidade do request à autorização; refresh e senha ficam fora de notes. |
| `internal/notes` | `Repository`, `Service`, `Handler`, parser | CRUD de nota e regras de vazio/tombstone; não aplica operações de bloco. |
| `internal/noteoperations` | veja [referência detalhada](../../backend/internal/noteoperations/README.md) | Único dono server-side do protocolo REST/OT. |
| `internal/noteoperations` | operações, validação e persistência do snapshot | O documento da nota é a fonte canônica dos `TaskNode`s, seus metadados e sua recorrência; não administra o recurso independente `Task`. |
| `internal/tasks` | `Repository`, `Service`, `Handler`, contratos e operações idempotentes | Recurso independente `Task`: autorização do proprietário, bootstrap, mutações, tombstones e emissão de eventos. Não lê `TaskNode` nem as tabelas legadas em quarentena. |
| `db/queries/tasks.sql` | bootstrap, task reads, mutation log e persistência | Fonte das queries sqlc para a tabela PostgreSQL `tasks` independente e `task_operations`; não é um projetor de documentos. |
| `db/migrations/000055_tasks_v2.*` | quarentena PostgreSQL e schema independente | Renomeia as tabelas legadas para `*_legacy_quarantine_v31`, cria o recurso independente e protege o down migration com guardas de dados/feed. |
| `internal/syncfeed` | `Repository`, `Handler`, `SyncChange` | Mantém o default `scope=notes` para clientes antigos; `scope=all` inclui eventos de `Task` com `task_id` e sem `note_id`. |
| `internal/shares` | repository/service/handler | Autoriza destinatário e permission; chamadas sempre usam `noteId` + usuário autenticado. |
| `internal/attachments` | repository/service/handler/storage | Valida upload, persiste metadados e envia bytes ao storage; storage é adapter substituível. |
| `internal/linkpreview` | service/handler | Busca metadata remota e aplica controles de segurança antes de retornar preview. |
| `internal/settings` | service/handler | Lê e atualiza configurações do usuário autenticado. |
| `internal/mcp` | server/tools/token | Expõe ferramentas para agente usando services existentes; não cria um segundo modelo de nota. |
| `internal/web` | bind/context/response | Convenções de erro e contexto HTTP comuns. |
| `internal/mapper` | conversores pgtype → tipos de saída | Mantém detalhes de pgx fora dos services e DTOs. |
| `internal/db/sqlcgen` | queries e modelos gerados | Output mecânico; a fonte é `db/queries` e as migrations são `db/migrations`. |

## Inicialização

`cmd/server/main.go` carrega config, cria pool, executa migrations, registra
middleware/rotas e inicia o cron de GC. Depois constrói repositories/services
por domínio. A ordem importa: nenhuma rota protegida deve existir sem o
middleware JWT e nenhum service deve abrir sua própria conexão.

## Ownership dos dados de task

`TaskNode` vive no snapshot REST/OT de uma nota (`notes.document`). O pacote
`internal/noteoperations` é o dono de suas operações, incluindo texto,
metadados, recorrência e conclusão.

`Task` é o recurso independente da aba Tasks. Sua autoridade remota é a linha
na tabela PostgreSQL `tasks`; no Flutter, a tabela Drift `tasks` é uma cópia
local-first acompanhada de `pending_task_operations`. O pacote
`internal/tasks` e o repositório Flutter são os donos de suas mutações.

As duas tabelas chamadas `tasks` pertencem a camadas diferentes, mas ambas
armazenam somente tasks independentes. Nenhuma é projeção de `TaskNode`, e não
existe conversão ou cópia automática entre as fontes. A lista global apenas
combina adaptadores de leitura no cliente. Relações e queries legadas para
`task_completions` são evidência de migração/quarentena, não parte do runtime.
