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
| `internal/tasks` | repository/service/handler, `recurrence.go`, `wire.go` | Endpoints e leitura de tarefas; o snapshot ainda é a fonte de escrita do editor. |
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
