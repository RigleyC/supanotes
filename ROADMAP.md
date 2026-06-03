# SupaNotes — Roadmap de Implementação v1

Plano feature-by-feature derivado do [escopo técnico v3](SuperNotes/notes-agent-scope-v3.md).  
Cada feature é uma unidade independente com entregáveis claros, projetada para ser implementada e commitada em sequência.

> **Convenção de commits**: `feat(scope): descrição` — seguindo [agents.md](agents.md).  
> **Branch**: cada feature é desenvolvida em `feat/<nome>` e mergeada em `main`.

---

## Legenda

- `[BE]` — Backend Go
- `[FE]` — Frontend Flutter
- `[DB]` — Migration PostgreSQL
- `[INFRA]` — Docker, CI, deploy

---

## Feature 0 — Fundação do projeto

**Objetivo**: Configurar a base do backend Go com todas as dependências, Docker Compose para dev local, e a estrutura de pastas definitiva.

**Branch**: `feat/foundation`

### Entregáveis

- [ ] `[BE]` Reestruturar `backend/` para a estrutura final do escopo:
  ```
  backend/
  ├── cmd/api/main.go              # Entrypoint (Echo)
  ├── internal/                    # Pacotes privados (vazio por agora)
  ├── db/
  │   ├── migrations/              # golang-migrate
  │   └── queries/                 # sqlc
  ├── pkg/
  │   ├── config/config.go         # Carrega env vars
  │   └── llm/                     # Interface LLM (vazio por agora)
  ├── sqlc.yaml
  ├── Dockerfile
  ├── .env.example
  └── go.mod / go.sum
  ```
- [ ] `[BE]` `go.mod` com dependências iniciais:
  - `github.com/labstack/echo/v4` — HTTP framework
  - `github.com/jackc/pgx/v5` — PostgreSQL driver
  - `github.com/golang-migrate/migrate/v4` — Migrations
  - `github.com/rs/zerolog` — Structured logging
  - `github.com/joho/godotenv` — .env loader
- [ ] `[BE]` `cmd/api/main.go`: servidor Echo com health check, graceful shutdown, zerolog
- [ ] `[BE]` `pkg/config/config.go`: carrega variáveis de ambiente com defaults
- [ ] `[INFRA]` `docker-compose.yml` na raiz: PostgreSQL 16 + pgvector
- [ ] `[INFRA]` `backend/Dockerfile` atualizado (multi-stage build)
- [ ] `[BE]` `.env.example` completo com todas as variáveis previstas
- [ ] `[BE]` `Makefile` com targets: `run`, `build`, `migrate-up`, `migrate-down`, `sqlc`, `test`

**Dependências**: nenhuma  
**Resultado**: `docker compose up` levanta Postgres; `make run` sobe o servidor Echo com health check em `GET /api/v1/health`.

---

## Feature 1 — Auth (Registro, Login, JWT)

**Objetivo**: Sistema de autenticação completo com JWT + refresh tokens + Argon2id.

**Branch**: `feat/auth`

### Entregáveis

- [ ] `[DB]` Migration 001: `users`, `user_settings`, `refresh_tokens`, `device_tokens`
- [ ] `[BE]` `db/queries/auth.sql` — queries sqlc para users e refresh tokens
- [ ] `[BE]` `internal/auth/handler.go` — endpoints:
  - `POST /api/v1/auth/register` — cria usuário, hash Argon2id, seed SOUL e rotinas padrão
  - `POST /api/v1/auth/login` — valida credenciais, retorna access + refresh tokens
  - `POST /api/v1/auth/refresh` — troca refresh por novo par
  - `POST /api/v1/auth/logout` — invalida refresh token
- [ ] `[BE]` `internal/auth/service.go` — lógica de Argon2id, JWT (15min), refresh (30d)
- [ ] `[BE]` `internal/auth/middleware.go` — middleware JWT para rotas protegidas
- [ ] `[BE]` Formato de erro consistente: `{ "error": "message" }`

**Dependências**: Feature 0  
**Resultado**: Fluxo completo de register → login → refresh → logout testável via curl/Postman.

---

## Feature 2 — CRUD de Notas + Inbox + Contextos

**Objetivo**: Operações completas de notas, inbox note especial, contextos (pastas) e tags.

**Branch**: `feat/notes-crud`

### Entregáveis

- [ ] `[DB]` Migration 002: `notes` (com triggers de FTS e excerpt), `contexts`, `tags`, `note_tags`, `note_links`, `attachments`
- [ ] `[BE]` `db/queries/notes.sql` — queries sqlc (CRUD, filtros, paginação cursor-based)
- [ ] `[BE]` `internal/notes/handler.go` — endpoints:
  - `POST /api/v1/notes`
  - `GET /api/v1/notes` — com filtros `?context_id=&has_tasks=&favorite=&limit=&cursor=`
  - `GET /api/v1/notes/:id`
  - `PATCH /api/v1/notes/:id`
  - `DELETE /api/v1/notes/:id` — soft delete (`deleted_at`)
  - `GET /api/v1/notes/inbox`
  - `POST /api/v1/notes/inbox/append`
- [ ] `[BE]` `internal/notes/service.go` — validações, ownership check, regras da inbox (não deleta, não arquiva, não aparece em listagens)
- [ ] `[BE]` `internal/notes/repository.go` — camada de acesso a dados
- [ ] `[BE]` `internal/contexts/handler.go` — `GET`, `POST`, `DELETE /api/v1/contexts`
- [ ] `[BE]` `internal/tags/handler.go` — `GET`, `POST /api/v1/tags`
- [ ] `[BE]` Seed da inbox note no fluxo de registro (Feature 1)
- [ ] `[DB]` Unique index: máximo uma inbox note ativa por usuário

**Dependências**: Features 0, 1  
**Resultado**: CRUD completo de notas testável via API. Inbox note criada automaticamente no registro.

---

## Feature 3 — Tasks como Entidades

**Objetivo**: Tasks como entidades first-class no banco, com due dates, recorrência, e histórico de conclusão.

**Branch**: `feat/tasks`

### Entregáveis

- [ ] `[DB]` Migration 003: `tasks`, `task_completions`
- [ ] `[BE]` `db/queries/tasks.sql` — queries sqlc
- [ ] `[BE]` `internal/tasks/handler.go` — endpoints:
  - `GET /api/v1/tasks` — com filtros `?note_id=&status=&due_before=&due_after=&limit=&cursor=`
  - `POST /api/v1/tasks` — `{ note_id, title, due_date?, recurrence? }`
  - `PATCH /api/v1/tasks/:id` — `{ title?, due_date?, recurrence?, position? }`
  - `DELETE /api/v1/tasks/:id` — soft delete
  - `POST /api/v1/tasks/:id/complete` — se recorrente, reabre com nova due_date
  - `POST /api/v1/tasks/:id/reopen`
  - `GET /api/v1/tasks/today` — due_date = hoje ou atrasadas
  - `GET /api/v1/notes/:id/tasks` — tasks de uma nota específica
- [ ] `[BE]` `internal/tasks/service.go` — lógica de recorrência:
  - `daily` → +1 dia
  - `weekdays` → próximo dia útil
  - `weekly` → +7 dias
  - `monthly` → +1 mês
- [ ] `[BE]` `internal/tasks/repository.go`
- [ ] `[BE]` Ao completar task recorrente: salva em `task_completions`, reabre com nova `due_date`

**Dependências**: Features 0, 1, 2  
**Resultado**: Tasks CRUD completo. Completar task recorrente gera histórico e reabre automaticamente.

---

## Feature 4 — Embeddings + SOUL + Memórias

**Objetivo**: Infraestrutura de IA: embeddings assíncronos, SOUL (personalidade do agent), e memórias de longo prazo.

**Branch**: `feat/ai-infra`

### Entregáveis

- [ ] `[DB]` Migration 004: `note_embeddings` (pgvector), `souls`, `memories`
- [ ] `[BE]` `internal/embeddings/service.go` — gera embeddings via OpenAI `text-embedding-3-small`
- [ ] `[BE]` `internal/embeddings/repository.go` — upsert/busca no pgvector
- [ ] `[BE]` `internal/embeddings/worker.go` — cron job a cada 10min:
  - Busca notas com `embedding_status = 'pending'` ou `'failed'` (exclui inbox)
  - Trunca conteúdo a 500 tokens
  - Gera embedding e salva
  - Retry de falhas automático
- [ ] `[BE]` `internal/notes/service.go` — ao criar/atualizar nota, marca `embedding_status = 'pending'`
- [ ] `[BE]` `internal/memories/service.go` — CRUD de memórias com embedding
- [ ] `[BE]` `internal/memories/repository.go`
- [ ] `[BE]` Endpoints:
  - `GET /api/v1/memories`
  - `DELETE /api/v1/memories/:id`
  - `GET /api/v1/soul`
  - `PUT /api/v1/soul`
- [ ] `[BE]` Seed do SOUL padrão no registro do usuário (personalidade default em Markdown)

**Dependências**: Features 0, 1, 2  
**Resultado**: Notas geram embeddings em background. SOUL e memórias acessíveis via API.

---

## Feature 5 — LLM Client Multi-Provider

**Objetivo**: Wrapper plugável de LLM com suporte a Anthropic (Claude) e DeepSeek, retry com backoff, e prompt caching.

**Branch**: `feat/llm-client`

### Entregáveis

- [ ] `[BE]` `pkg/llm/client.go` — interface `Client` com `Complete(ctx, Request) (*Response, error)`
- [ ] `[BE]` `pkg/llm/anthropic.go` — implementação Anthropic com prompt caching (header `anthropic-beta`)
- [ ] `[BE]` `pkg/llm/deepseek.go` — implementação DeepSeek (API compatível com OpenAI, troca `base_url`)
- [ ] `[BE]` `pkg/llm/factory.go` — `LLMFactory` com `For(TaskType)`:
  - `TaskAgentic` → Claude Sonnet
  - `TaskGenerate` → DeepSeek V4 Flash
- [ ] `[BE]` `pkg/llm/retry.go` — retry com backoff exponencial (1s, 2s, 4s) para erros 429/500/503
- [ ] `[BE]` Logging de usage (input/output tokens, cache hits) via zerolog

**Dependências**: Feature 0  
**Resultado**: Pacote `pkg/llm` testável isoladamente. Factory seleciona provider por tipo de tarefa.

---

## Feature 6 — Agent Loop + Tools + Tiered Context

**Objetivo**: O coração do produto — agent conversacional com tool calling, contexto em camadas, e busca semântica.

**Branch**: `feat/agent`

### Entregáveis

- [ ] `[DB]` Migration 005: `messages` (histórico do agent)
- [ ] `[BE]` `internal/agent/loop.go` — Agent loop principal:
  - Salva mensagem do usuário
  - Monta tiered context
  - Chama LLM com tools
  - Loop de tool calling (máx 5 iterações)
  - Salva resposta
- [ ] `[BE]` `internal/agent/context.go` — Tiered context builder:
  - Tier 0: SOUL
  - Tier 1: Conversa recente (10 msgs, filtro por session_id)
  - Tier 2: Contexto estruturado (tasks abertas, today, overdue, notas recentes 48h, stats)
  - Tier 3: RAG semântico (top 6 notas por similaridade, exclui inbox)
  - Tier 4: Notas relacionadas (linkadas às do Tier 3)
  - Tier 5: Memórias relevantes (top 5 por similaridade)
  - Tier 6: Meta (data/hora no timezone do usuário)
  - Token budget explícito (8.000 tokens, truncamento de notas longas)
- [ ] `[BE]` `internal/agent/tools.go` — definição e execução de todas as ~20 tools:
  - Notas: `add_note`, `get_notes`, `search_notes`, `append_to_note`, `update_note`, `link_notes`, `get_vault_context`, `get_inbox_note`, `append_to_inbox`, `plan_inbox_organization`, `apply_inbox_organization`
  - Tasks: `add_task`, `complete_task`, `get_open_tasks`, `get_today_tasks`, `update_task`
  - Memórias: `save_memory`, `list_memories`, `delete_memory`
  - Soul: `get_soul`, `update_soul`
  - Rotinas: `list_routines`, `set_daily_brief_schedule`, `set_weekly_brief_schedule`, `test_daily_brief`, `test_weekly_brief`
- [ ] `[BE]` `internal/agent/soul.go` — carrega SOUL do banco
- [ ] `[BE]` `internal/agent/handler.go` — endpoints:
  - `POST /api/v1/agent/chat` — resposta completa
  - `POST /api/v1/agent/chat/stream` — SSE (Server-Sent Events)
  - `GET /api/v1/agent/messages` — histórico com `?limit=`
  - `DELETE /api/v1/agent/messages` — limpa histórico
- [ ] `[BE]` Ownership validation em todas as tools que operam sobre recursos
- [ ] `[BE]` Organização transacional do inbox (`ApplyOrganizationPlan` com `db.WithTx`)

**Dependências**: Features 2, 3, 4, 5  
**Resultado**: Conversa com o agent via API. Tools executam operações reais. SSE funciona para streaming.

---

## Feature 7 — Busca Híbrida

**Objetivo**: Busca full-text (FTS) + semântica + Reciprocal Rank Fusion.

**Branch**: `feat/search`

### Entregáveis

- [ ] `[BE]` `internal/search/handler.go` — endpoint `POST /api/v1/search`
  - Body: `{ query, mode: "fts" | "semantic" | "hybrid" }`
- [ ] `[BE]` `internal/search/service.go`:
  - `fullTextSearch` — usa `tsvector` com `plainto_tsquery('simple', ...)` e `ts_rank`
  - `semanticSearch` — gera embedding da query, busca por cosine similarity no pgvector
  - `hybridSearch` — combina FTS + semântica via RRF (Reciprocal Rank Fusion)
- [ ] `[BE]` `db/queries/search.sql` — queries de FTS e semântica (exclui inbox, exclui arquivadas)

**Dependências**: Features 2, 4  
**Resultado**: Busca funcional nos 3 modos. Inbox note nunca aparece nos resultados.

---

## Feature 8 — Rotinas (Daily/Weekly Briefs)

**Objetivo**: Cron runner que gera daily e weekly briefs usando LLM, salva histórico, e notifica.

**Branch**: `feat/routines`

### Entregáveis

- [ ] `[DB]` Migration 006: `routines`, `routine_logs`
- [ ] `[BE]` `internal/routines/handler.go` — endpoints:
  - `GET /api/v1/routines`
  - `GET /api/v1/routines/logs`
  - `PATCH /api/v1/routines/daily`
  - `PATCH /api/v1/routines/weekly`
  - `POST /api/v1/routines/daily/test` — dry-run
  - `POST /api/v1/routines/weekly/test` — dry-run
- [ ] `[BE]` `internal/routines/service.go` — lógica de teste (dry-run sem salvar nem notificar)
- [ ] `[BE]` `internal/routines/repository.go`
- [ ] `[BE]` `internal/routines/runner.go` — cron runner:
  - Verifica a cada minuto rotinas habilitadas
  - Avalia dia/horário no timezone do usuário (`user_settings.timezone`)
  - Lock por `routine_id` (evita execução dupla)
  - `BuildForRoutine` (context sem histórico de conversa)
  - Salva resultado em `routine_logs`
  - Envia via Telegram quando houver vínculo ativo
  - Envia FCM push "Novo brief disponível"
- [ ] `[BE]` `internal/agent/context.go` — `BuildForRoutine` (Tier 1 omitido, query fixa)
- [ ] `[BE]` Seed das rotinas padrão no registro do usuário:
  - Daily: Seg–Sex, 08:00, ativo
  - Weekly: Segunda, 09:00, ativo
- [ ] `[BE]` Cleanup job semanal: deleta mensagens com >90 dias
- [ ] `[BE]` Prompts de brief (daily e weekly) em arquivos Markdown dedicados

**Dependências**: Features 1, 5, 6  
**Resultado**: Briefs gerados automaticamente por cron. Logs acessíveis via API. Dry-run funcional.

---

## Feature 9 — Gateway Telegram

**Objetivo**: Bot Telegram integrado ao backend Go que consome o mesmo agent loop.

**Branch**: `feat/telegram`

### Entregáveis

- [ ] `[DB]` Migration 007: `telegram_links`, `telegram_link_codes`
- [ ] `[BE]` `internal/gateway/bot.go` — setup do bot Telegram (telebot ou equivalente):
  - Handler `/start CODIGO` — vincula conta
  - Handler de texto — resolve `telegram_user_id` → `user_id`, chama agent stream
  - Streaming simulado: edita mensagem a cada 600ms via `editMessageText`
- [ ] `[BE]` `internal/gateway/bridge.go` — conecta webhook do Telegram ao agent loop
- [ ] `[BE]` `internal/gateway/handler.go` — endpoints:
  - `GET /api/v1/telegram/link` — status do vínculo
  - `POST /api/v1/telegram/link-code` — gera código temporário
  - `DELETE /api/v1/telegram/link` — remove vínculo
  - `POST /api/v1/gateway/telegram/webhook` — endpoint público do webhook
- [ ] `[BE]` Mensagem amigável quando `telegram_user_id` não está vinculado

**Dependências**: Features 1, 6  
**Resultado**: Bot Telegram funcional. Usuário vincula conta via código, conversa com o agent pelo Telegram.

---

## Feature 10 — Push Notifications (FCM)

**Objetivo**: Firebase Cloud Messaging para notificar o app sobre briefs e eventos relevantes.

**Branch**: `feat/fcm`

### Entregáveis

- [ ] `[BE]` `internal/notifications/fcm.go` — wrapper do Firebase Admin SDK:
  - `Send(userID, message)` — envia para todos os device tokens do usuário
  - Trunca body a 200 chars
- [ ] `[BE]` Endpoints para device tokens:
  - `POST /api/v1/device-tokens` — registra token FCM
  - `DELETE /api/v1/device-tokens/:id` — remove token
- [ ] `[BE]` Integrar com runner de rotinas (Feature 8) — notificar "Novo brief disponível"

**Dependências**: Features 0, 1  
**Resultado**: App pode registrar tokens FCM. Backend envia push notifications.

---

## Feature 11 — Sync API (Local-First)

**Objetivo**: Endpoints de sincronização para suportar a arquitetura local-first do app Flutter.

**Branch**: `feat/sync-api`

### Entregáveis

- [ ] `[BE]` `internal/sync/handler.go` — endpoints:
  - `POST /api/v1/sync/pull` — `{ last_synced_at }` → registros com `updated_at > last_synced_at` (inclui soft-deleted), com `limit` + `cursor` para paginação
  - `POST /api/v1/sync/push` — `{ changes[] }` → recebe mudanças do app, servidor atribui `updated_at = NOW()`
- [ ] `[BE]` `internal/sync/service.go`:
  - Resolução de conflitos: last-write-wins por registro (server timestamp)
  - Suporte a notas, tasks, contexts, tags
- [ ] `[BE]` `internal/sync/repository.go`
- [ ] `[BE]` Job periódico: hard delete de registros com `deleted_at` > 30 dias

**Dependências**: Features 2, 3  
**Resultado**: App Flutter pode fazer pull/push incremental. Conflitos resolvidos por LWW.

---

## Feature 12 — Settings

**Objetivo**: Endpoint de configurações do usuário (timezone, etc.).

**Branch**: `feat/settings`

### Entregáveis

- [ ] `[BE]` `internal/settings/handler.go` — endpoints:
  - `GET /api/v1/settings`
  - `PUT /api/v1/settings`
- [ ] `[BE]` `internal/settings/service.go` — validações (timezone válido, etc.)

**Dependências**: Feature 1  
**Resultado**: Usuário pode consultar e alterar suas configurações.

---

## Feature 13 — Flutter: Foundation + Auth

**Objetivo**: Setup do app Flutter com a estrutura final, dependências, auth, e navegação.

**Branch**: `feat/flutter-foundation`

### Entregáveis

- [ ] `[FE]` Reestruturar `lib/` para a estrutura do escopo:
  ```
  lib/
  ├── main.dart
  ├── core/
  │   ├── api/           # Dio HTTP client
  │   ├── database/      # Drift (SQLite local) + DAOs
  │   ├── sync/          # SyncService + ConnectivityMonitor
  │   ├── di/            # Dependency injection (Riverpod)
  │   └── router/        # Go Router
  ├── features/
  │   ├── auth/          # Login, register
  │   ├── notes/
  │   ├── tasks/
  │   ├── agent/
  │   ├── routines/
  │   ├── search/
  │   └── settings/
  └── shared/
      ├── widgets/
      └── theme/
  ```
- [ ] `[FE]` Dependências: `riverpod`, `go_router`, `dio`, `drift`, `sqlite3_flutter_libs`, `connectivity_plus`
- [ ] `[FE]` `core/api/` — Dio client com interceptor JWT (auto-refresh)
- [ ] `[FE]` `core/router/` — Go Router com guards de auth
- [ ] `[FE]` `features/auth/` — telas de login e registro
- [ ] `[FE]` `shared/theme/` — tema base (dark mode, tipografia, cores)

**Dependências**: Feature 1 (backend auth funcional)  
**Resultado**: App Flutter com login/registro funcional, navegação configurada, tema aplicado.

---

## Feature 14 — Flutter: Drift + Sync

**Objetivo**: Banco local SQLite via Drift, espelhando o schema do Postgres, com SyncService.

**Branch**: `feat/flutter-drift-sync`

### Entregáveis

- [ ] `[FE]` `core/database/` — schema Drift para `notes`, `tasks`, `contexts`, `tags` (com coluna `isDirty`)
- [ ] `[FE]` `core/database/daos/` — DAOs para cada entidade (queries locais)
- [ ] `[FE]` `core/sync/sync_service.dart`:
  - Push: envia registros `isDirty=true` para `POST /api/v1/sync/push`
  - Pull: pede registros com `updated_at > lastSyncedAt` via `POST /api/v1/sync/pull`
  - Sync ao abrir app, ao reconectar, e periodicamente (30s)
- [ ] `[FE]` `core/sync/connectivity_monitor.dart` — observa estado de rede
- [ ] `[FE]` Indicador visual sutil de status offline

**Dependências**: Features 11, 13  
**Resultado**: App funciona offline para notas e tasks. Sync automático em background.

---

## Feature 15 — Flutter: Notas + Editor (super_editor)

**Objetivo**: Listagem de notas, editor Markdown com super_editor, inbox note com captura rápida.

**Branch**: `feat/flutter-notes`

### Entregáveis

- [ ] `[FE]` `features/notes/presentation/` — telas:
  - Lista de notas (com filtros por contexto, favoritas)
  - Editor de nota com super_editor
  - Inbox note com botão "Organizar"
- [ ] `[FE]` `features/notes/data/local/` — lê/escreve do Drift (fonte primária)
- [ ] `[FE]` `features/notes/data/remote/` — API calls (apenas para sync)
- [ ] `[FE]` `features/notes/domain/` — modelos e use cases
- [ ] `[FE]` Widgets customizados do super_editor para headings, listas, etc.
- [ ] `[FE]` FAB (Floating Action Button) para captura rápida → salva no inbox
- [ ] `[FE]` Auto-save no editor (debounce de 2s)

**Dependências**: Features 13, 14  
**Resultado**: Criar, editar, listar notas localmente. Editor funcional com super_editor.

---

## Feature 16 — Flutter: Tasks

**Objetivo**: UI de tasks integrada às notas — checkbox widgets no editor, tela de "Hoje".

**Branch**: `feat/flutter-tasks`

### Entregáveis

- [ ] `[FE]` `features/tasks/presentation/` — telas:
  - Tasks de hoje (due_date = hoje + atrasadas)
  - Tasks dentro de uma nota
- [ ] `[FE]` `features/tasks/data/` — local (Drift) + remote (sync)
- [ ] `[FE]` Widget de checkbox interativo no super_editor (renderiza task como widget)
- [ ] `[FE]` Lógica de completar task recorrente no local (marca done, cria nova entry com due_date futura)

**Dependências**: Features 14, 15  
**Resultado**: Tasks visíveis e interativas no editor. Tela "Hoje" funcional.

---

## Feature 17 — Flutter: Agent Chat

**Objetivo**: Interface de chat com o agent, consumindo SSE para streaming de respostas.

**Branch**: `feat/flutter-agent`

### Entregáveis

- [ ] `[FE]` `features/agent/presentation/` — tela de chat:
  - Mensagens com scroll
  - Input de texto com envio
  - Streaming da resposta (SSE via Dio `ResponseType.stream`)
  - Botão "Nova conversa" (gera novo `session_id`)
  - Auto-nova sessão se app ficou em background >30min
- [ ] `[FE]` `features/agent/data/` — API calls para chat/stream
- [ ] `[FE]` Indicador de "pensando" enquanto o agent processa

**Dependências**: Features 6, 13  
**Resultado**: Chat com o agent funcional. Respostas em tempo real via SSE.

---

## Feature 18 — Flutter: Busca

**Objetivo**: Tela de busca com suporte a FTS, semântica, e híbrida.

**Branch**: `feat/flutter-search`

### Entregáveis

- [ ] `[FE]` `features/search/presentation/` — tela de busca:
  - Campo de texto com debounce
  - Resultados com excerpt e score
  - Toggle de modo (FTS / Semântica / Híbrida)
- [ ] `[FE]` `features/search/data/` — API call para `POST /api/v1/search`
- [ ] `[FE]` Feature online-only (desabilitada quando offline)

**Dependências**: Features 7, 13  
**Resultado**: Busca funcional nos 3 modos. Resultados navegáveis para a nota completa.

---

## Feature 19 — Flutter: Settings + Rotinas + Telegram

**Objetivo**: Telas de configuração, agenda de briefs, e vínculo Telegram.

**Branch**: `feat/flutter-settings`

### Entregáveis

- [ ] `[FE]` `features/settings/presentation/` — telas:
  - Conta (email, nome)
  - Notificações
  - Avançado → Personalidade do agent (SOUL editor)
  - Avançado → Contextos
  - Avançado → Dados
- [ ] `[FE]` `features/routines/presentation/` — UI de briefs:
  - Daily brief: toggle ativo, seletor de dias, horário, botão testar
  - Weekly brief: toggle ativo, seletor de dia, horário, botão testar
  - Histórico de briefs (lista de `routine_logs`)
- [ ] `[FE]` Telegram: tela com status do vínculo, gerar código, instruções de `/start`, desconectar
- [ ] `[FE]` Features online-only

**Dependências**: Features 8, 9, 12, 13  
**Resultado**: Todas as configurações acessíveis. Briefs configuráveis. Telegram vinculável.

---

## Feature 20 — Polish + Testes + Deploy

**Objetivo**: Qualidade, performance, e primeiro deploy.

**Branch**: `feat/polish`

### Entregáveis

- [ ] `[BE]` Testes unitários para: auth service, notes service, tasks recurrence, agent tools, search RRF
- [ ] `[BE]` Testes de integração para: agent loop end-to-end, sync pull/push
- [ ] `[FE]` Widget tests para: editor, tasks, chat
- [ ] `[FE]` Golden tests para telas principais
- [ ] `[INFRA]` CI/CD pipeline (GitHub Actions):
  - Backend: lint, test, build
  - Flutter: analyze, test, build
- [ ] `[INFRA]` Deploy inicial no Railway:
  - PostgreSQL + pgvector
  - Backend Go
  - Telegram webhook configurado
- [ ] `[FE]` Ícone do app e splash screen
- [ ] `[FE]` Tratamento de erros global (snackbars, retry)
- [ ] `[FE]` Loading states e empty states em todas as telas

**Dependências**: todas as features anteriores  
**Resultado**: App deployado e funcional no Railway. CI/CD rodando.

---

## Ordem de Execução Recomendada

```
Feature 0  → Fundação
Feature 1  → Auth
Feature 2  → Notas CRUD
Feature 3  → Tasks
Feature 4  → Embeddings + SOUL + Memórias
Feature 5  → LLM Client
Feature 12 → Settings (simples, desbloqueia frontend)
Feature 6  → Agent Loop
Feature 7  → Busca Híbrida
Feature 8  → Rotinas
Feature 9  → Gateway Telegram
Feature 10 → Push Notifications (FCM)
Feature 11 → Sync API
Feature 13 → Flutter Foundation + Auth
Feature 14 → Flutter Drift + Sync
Feature 15 → Flutter Notas + Editor
Feature 16 → Flutter Tasks
Feature 17 → Flutter Agent Chat
Feature 18 → Flutter Busca
Feature 19 → Flutter Settings + Rotinas + Telegram
Feature 20 → Polish + Testes + Deploy
```

---

## Estimativa Total

**Backend (Features 0–12)**: ~5–6 semanas  
**Frontend (Features 13–19)**: ~3–4 semanas  
**Polish (Feature 20)**: ~1 semana  
**Total v1**: ~9–11 semanas

---

## Referências

- [Escopo técnico v3](SuperNotes/notes-agent-scope-v3.md)
- [Glossário de domínio](SuperNotes/CONTEXT.md)
- [ADR 001 — Managed Backend LLM](SuperNotes/docs/adr/0001-managed-backend-llm.md)
- [ADR 002 — Official Telegram Bot Linking](SuperNotes/docs/adr/0002-official-telegram-bot-linking.md)
- [ADR 003 — Tasks as Database Entities](SuperNotes/docs/adr/0003-tasks-as-entities.md)
- [Convenções do projeto](agents.md)
