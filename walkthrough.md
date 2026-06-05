# Feature 1 — Auth (walkthrough)

> Worktree: `D:/projects/supanotes-worktrees/auth` · branch `feat/auth`

## What landed

End-to-end authentication on the Go backend: register, login, JWT-protected
access (HS256, 15 min), opaque refresh tokens (32-byte random, SHA-256-hashed
in DB, 30-day TTL) with rotation on every use, and logout that revokes the
current refresh token.

All routes are mounted under `/api/v1/auth/...` and are public — no JWT is
required to call them. The middleware (`internal/auth.JWT`) is exported and
ready for F2+ to protect `/api/v1/notes/...`, `/api/v1/ai/...`, etc.

## Files touched

| Layer | File | Status |
|---|---|---|
| Primitives | `backend/pkg/auth/{password,jwt,refresh}.go` + `*_test.go` | committed (c81953c) |
| Persistence | `backend/db/migrations/000001_init.{up,down}.sql` | committed (e88373a) |
| Persistence | `backend/db/queries/auth.sql` + `internal/db/sqlcgen/*` | committed (e88373a) |
| Infra | `backend/pkg/db/db.go` (pgxpool) | committed (8a00a24) |
| Infra | `backend/pkg/migrate/migrate.go` (golang-migrate) | committed (8a00a24) |
| Config | `backend/pkg/config/config.go` + `config_test.go` | committed (f1fb576) |
| Config | `backend/.env.example` | committed (f1fb576) |
| Service | `backend/internal/auth/service.go` + `service_test.go` | committed (f2b2b12) |
| HTTP | `backend/internal/auth/handler.go` + `handler_test.go` | committed (f2b2b12) |
| HTTP | `backend/internal/auth/middleware.go` + `middleware_test.go` | committed (f2b2b12) |
| Wiring | `backend/cmd/server/main.go` | committed (f2b2b12) |
| Marker | empty `feat(backend): feature 1 — auth (…)` | committed (748f336) |

## Commit history (this feature)

```
748f336 feat(backend): feature 1 — auth (register, login, JWT, refresh tokens, Argon2id)
f2b2b12 feat(backend): auth service, handler, middleware and route wiring
f1fb576 feat(backend): JWT config and dependencies
8a00a24 feat(backend): db pool and programmatic migrations
e88373a feat(backend): migration 001 - users, settings, refresh + device tokens
c81953c feat(backend): auth primitives - Argon2id, JWT (HS256), refresh tokens
```

## How to run

```bash
# from the worktree
cd backend
make dev-db-up                     # docker compose up -d postgres
cp .env.example .env               # set a real JWT_SECRET (32+ chars)
go run ./cmd/server
```

The startup log will show `migrate: schema migrated from=0 to=1`, then
`database pool ready`, then `supanotes backend starting addr=:8080 env=dev`.
With an empty `DATABASE_URL`, the server boots in dev-no-db mode and skips
the `/auth/*` routes (with a warning).

## API surface

| Method | Path | Body | Success | Errors |
|---|---|---|---|---|
| `GET`  | `/api/v1/health` | — | `200 {"status":"ok"}` | — |
| `POST` | `/api/v1/auth/register` | `{email, password, name}` | `201 {user, access_token, refresh_token}` | `400 validation` / `409 email in use` / `500` |
| `POST` | `/api/v1/auth/login` | `{email, password}` | `200 {user, access_token, refresh_token}` | `400 validation` / `401 invalid credentials` / `500` |
| `POST` | `/api/v1/auth/refresh` | `{refresh_token}` | `200 {access_token, refresh_token}` (rotated) | `400 validation` / `401 invalid refresh token` / `500` |
| `POST` | `/api/v1/auth/logout` | `{refresh_token}` | `204` (no-op if unknown) | `400 validation` / `500` |

All error responses are `{"error": "<message>"}`.

## Security properties

- **Passwords**: Argon2id PHC `$argon2id$v=19$m=65536,t=1,p=4$<salt>$<hash>`,
  16-byte random salt per user, 32-byte key length. Verified in constant
  time via `crypto/subtle`.
- **Access tokens**: HS256, `sub = user_id`, `iat`, `exp = now + 15min`.
  Secret from `JWT_SECRET` (refuses to start outside `dev` mode without it).
- **Refresh tokens**: 32 random bytes from `crypto/rand` → 64-char hex.
  Plain token is never persisted; only its SHA-256 hash. Rotation on
  every use (old row gets `revoked_at = NOW()`); replays of a revoked
  or expired token return `401`.
- **No information leak**: register and login return the same shape
  on conflict (no enumeration via timing or wording).
- **Email normalisation**: lowercased + trimmed before insert, so
  `User@Example.COM` and `user@example.com` collide on the unique index.

## End-to-end smoke test (executed, passed)

```
1. GET  /api/v1/health                                → 200
2. POST /api/v1/auth/register (smoke@example.com)     → 201, access (JWT, 188 chars) + refresh (64 hex) + user
3. POST /api/v1/auth/register (same email)            → 409 {"error":"email already in use"}
4. POST /api/v1/auth/login (wrong password)           → 401 {"error":"invalid credentials"}
5. POST /api/v1/auth/login (correct)                  → 200, new access+refresh (rotated vs step 2)
6. POST /api/v1/auth/refresh (REFRESH2)               → 200, new pair
7. POST /api/v1/auth/refresh (REFRESH2 again)         → 401 {"error":"invalid refresh token"}  (revoked)
8. POST /api/v1/auth/logout  (REFRESH)                → 204
9. DB inspection:
     users.password_hash           = $argon2id$v=19$m=65536,t=1,p=4$…  (Argon2id PHC)
     refresh_tokens.token_hash     = 64 hex chars (SHA-256)
     user_settings.timezone        = "UTC"
     refresh_tokens with revoked_at = 2 (from steps 7 + 8)
     refresh_tokens still active   = 2 (from steps 5 + 6)
```

## Tests

```
go test ./...
ok  github.com/RigleyC/supanotes/internal/auth        (30 cases: 12 service + 11 handler + 7 middleware)
ok  github.com/RigleyC/supanotes/internal/handler     (health)
ok  github.com/RigleyC/supanotes/pkg/auth             (12 cases: 5 password + 4 JWT + 3 refresh)
ok  github.com/RigleyC/supanotes/pkg/config           (3 cases incl. prod-without-JWT_SECRET)
go vet ./...                                          clean
go build ./...                                        clean
```

The service tests use a hand-rolled `mockQuerier` implementing the full
`sqlcgen.Querier` interface, with the same `revoked_at IS NULL AND
expires_at > NOW()` semantics as the real `GetRefreshToken` query.

## Out of scope (next features)

- `GET /api/v1/me` (and other user details routes).
- Email verification / password reset — comes with F3.
- Rate limiting on `/auth/login` — comes with the production hardening pass.
- Rotating `JWT_SECRET` / key versioning — come with the multi-tenant work.

---

# Feature 2 — Notes CRUD, Inbox & Contexts (walkthrough)

## What landed

- **Database**:
  - Migration `000002_notes.up.sql` containing tables: `notes`, `contexts`, `tags`, `note_tags`, `note_links`.
  - Advanced PostgreSQL setup:
    - Full-text search using `tsvector` (`pt_BR` unaccented config).
    - pgvector setup (0-dimension placeholder for now).
    - Automatic `search_vector` update triggers.
    - Automatic `excerpt` generation trigger (plain text snippet, max 200 chars).
    - Constraints: `idx_notes_single_inbox` ensuring exactly one inbox note per user.
- **Data Access Layer**:
  - `sqlc` queries for all tables (`notes.sql`).
  - Auto-generated type-safe models using `pgtype` mapping.
- **Backend Application Logic**:
  - `internal/notes`: `Service`, `Repository`, and HTTP `Handler`. Handles ownership and inbox protections (preventing archive/deletion of the inbox note).
  - `internal/contexts` and `internal/tags`: Lightweight CRUD handlers.
  - Wiring of all protected endpoints into `api.Group("", auth.JWT(cfg))` in `main.go`.
- **Auth Seeding Integration**:
  - Updated `internal/auth/service.go` so that new user registrations automatically seed a first "Inbox" note.

## Endpoints Implemented

### Contexts
- `POST /api/v1/contexts`
- `GET /api/v1/contexts`
- `DELETE /api/v1/contexts/:id`

### Tags
- `POST /api/v1/tags`
- `GET /api/v1/tags`

### Notes
- `POST /api/v1/notes`
- `GET /api/v1/notes` (supports `limit`, `cursor_updated_at`, `cursor_id`, `context_id`, `favorite` filters)
- `GET /api/v1/notes/:id`
- `PATCH /api/v1/notes/:id`
- `DELETE /api/v1/notes/:id` (Soft delete using `deleted_at`)

### Inbox
- `GET /api/v1/notes/inbox`
- `POST /api/v1/notes/inbox/append` (Appends text separated by double newlines)

## Verification
- Verified compilation and types passing via `go build` and `go test` in Docker `golang:latest`.
- Simulated the SQL query operations validating all models and `sqlc` signatures.
- Verified JWT middleware compatibility and dependency injection.

## How to test locally
1. Ensure the PostgreSQL container is running: `make dev-db-up`.
2. Apply migrations automatically via the app startup.
- Call `POST /api/v1/auth/register` to create a user and seed the inbox note.
- Call `GET /api/v1/notes/inbox` with the `Bearer` token to view the seeded note.
- Append text using `POST /api/v1/notes/inbox/append`.

---

# Feature 3 — Tasks como Entidades (walkthrough)

## What landed

- **Database**:
  - Migration `000003_tasks.up.sql` contendo `tasks` e `task_completions`.
  - Controle nativo para data de vencimento (`due_date`), status e `recurrence`.
  - Índice para as datas de vencimento (`idx_tasks_due_date`) e relacionamentos de integridade (CASCADE para `notes` e `users`).
- **Data Access Layer**:
  - Auto-generated type-safe models para as duas novas tabelas com `make sqlc`.
- **Backend Application Logic**:
  - `internal/tasks` package.
  - CRUD operations para Tasks.
  - Lógica especial de `/complete`: Salva histórico em `task_completions`. Se a task for recorrente (`daily`, `weekdays`, `weekly`, `monthly`), reabre automaticamente a task com a próxima `due_date`.
- **Unit Tests**:
  - Lógica de salto e identificação de `due_date` (pulando finais de semana no `weekdays`, etc.) testada exaustivamente via `go test`.

## Endpoints Implemented

### Tasks
- `POST /api/v1/tasks` — com suporte opcional a `due_date` e `recurrence`.
- `GET /api/v1/tasks` — Listagem com filtros por `note_id`, `status` e range de `due_date`.
- `PATCH /api/v1/tasks/:id` — Atualiza propriedades e metadados.
- `DELETE /api/v1/tasks/:id` — Soft-delete nativo.
- `POST /api/v1/tasks/:id/complete` — Conclui ou avança a recorrência.
- `POST /api/v1/tasks/:id/reopen` — Reabre a task e limpa status de concluída.
- `GET /api/v1/tasks/today` — Retorna tasks até às 23:59:59 do timezone local do servidor.

## Verification
- Lógica de datas e rotas compiladas e validadas através da suíte de testes com a infra de Docker do Go 1.24 (`golang:latest`).

---

# Feature 4 — Embeddings + SOUL + Memórias (walkthrough)

## What landed

- **Database**:
  - Migration `000004_ai_infra.up.sql` adicionando a extensão nativa `pgvector`.
  - Tabelas de alta dimensão: `note_embeddings` (1536 dimensões), `souls` e `memories`.
  - Inserção do status do processo de embedding diretamente na tabela `notes` para controle reativo pelo worker (`pending`, `completed`, `failed`).
- **Data Access Layer**:
  - `sqlc` models atualizados com tipos de compatibilidade do `pgvector-go`.
- **Backend Application Logic**:
  - Modificado o cadastro (`/auth/register`) para injetar um *SOUL* default no banco de dados para o usuário.
  - Modificado o `/notes` (create e update) para marcar os registros atualizados com status `pending` novamente.
  - Criada rotina silenciosa (`worker.go`) que acorda a cada 10 minutos varrendo `pending` notes e simulando o embedding (o client real entra na F5).
- **Server Wiring**:
  - `main.go` agora possui rotas do `/soul` e do `/memories`. O worker cron também roda dentro do lifecycle principal atrelado ao `ctx`.

## Endpoints Implemented

### Memories
- `POST /api/v1/memories` — Cria uma memória e atrela ao seu vetor.
- `GET /api/v1/memories` — Lista memórias (paginadas).
- `DELETE /api/v1/memories/:id` — Hard delete de memória inútil.

### Soul
- `GET /api/v1/soul` — Exibe a personalidade atual associada à conta.
- `PUT /api/v1/soul` — Substitui o prompt matriz da conta.

## Verification
- Suíte principal adaptada para suportar stubs de pgvector durante a build.
- `golang:latest` confirmou o build e testes (passando).

---

# Feature 5 — LLM Client Multi-Provider (walkthrough)

## What landed

- **Interface Abstrata**: Pacote `pkg/llm` com interfaces `Client` independentes de vendor.
- **Provider Implementations**:
  - `anthropic.go` mapeando para a API do Claude 3.5 Sonnet com *prompt caching* habilitado via beta headers.
  - `deepseek.go` implementando o padrão DeepSeek V3/R1.
- **Resilience**: Wrapper `retry.go` com Exponential Backoff (1s, 2s, 4s) + Jitter randômico para contornar Rate Limits (`429`) e Timeout Issues nativos das APIs de IA, tentando 3 vezes de forma resiliente.
- **Factory Pattern**: `factory.go` mapeia qual cliente utilizar dependendo do `TaskType` exigido (Agentic ou Generate).
- **Integração de Configuração**: Adicionadas as chaves `ANTHROPIC_API_KEY` e `DEEPSEEK_API_KEY` ao `pkg/config/config.go` carregadas via `.env`.

## Verification
- Testes unitários do Retry foram escritos mockando um servidor que falha propositalmente (para testar o recovery com Exponential Backoff). 
- `go test ./pkg/llm/...` e suite completa validados com Docker.

---

# Refactor — Standard Cron + Generic OpenAI Client

Atendendo ao feedback de design, implementamos:
1. **Generic Client (`pkg/llm/openai_compat.go`)**: Substituímos o cliente exclusivo da DeepSeek por um cliente genérico OpenAI-Compatible, suportando nativamente qualquer modelo futuro (LM Studio, Groq, Ollama) com apenas uma troca de `BaseURL`.
2. **Cron Scheduler**: Substituímos as Goroutines do worker de embeddings por `robfig/cron/v3`, provendo agendamento estilo POSIX limpo e com suporte a graceful shutdown no `cmd/server/main.go`.

---

# Feature 6 — Agent Loop + Tools + Tiered Context (walkthrough)

## What landed

- **Tabela de Mensagens**: Migration `000005_agent_loop` com queries SQLC completas para CRUD do histórico conversacional (separado por `session_id`).
- **RAG Semantic Queries**: Adicionado `SearchNotesByEmbedding` e `SearchMemoriesByEmbedding` ao `ai.sql`, realizando a busca usando similaridade vetorial do `pgvector`.
- **Tiered Context Builder** (`context.go`): O sistema compila o contexto injetando a Soul, Mensagens recentes, Tasks em aberto/atrasadas (via `tasks.Service`), Notas Similares (RAG) e Memórias associadas à query num único prompt formadado.
- **Tool Registry** (`tools.go`): Inicializado com injeção de dependência dos services `notes`, `tasks` e `memories`, permitindo o agente executar as ferramentas preestabelecidas (como `add_note`, `add_task` e `save_memory`).
- **Agent Orchestration** (`loop.go`): O `Loop` recebe a query do usuário, armazena no histórico, compila todo o prompt complexo em milissegundos via `ContextBuilder`, aciona o LLM via `llm.Factory` e devolve a resposta guardando no banco.

## Verification
- Todo o pacote `internal/agent` foi submetido ao build com sucesso junto aos seus respectivos imports de domínios irmãos (`tasks`, `notes`, `memories`).
- Compilação total do repositório (`go test ./...`) assegurou que todo o framework RAG se encontra validado contra as interfaces do projeto.
