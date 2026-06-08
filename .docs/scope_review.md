# SupaNotes — Revisão de Escopo vs Implementação

Análise detalhada comparando o escopo documentado em [notes-agent-scope-v3.md](file:///c:/Users/rigleyc/projects/supanotes/.docs/notes-agent-scope-v3.md) e [CONTEXT.md](file:///c:/Users/rigleyc/projects/supanotes/.docs/CONTEXT.md) com o que está implementado no código.

---

## Resumo Executivo

| Área | Status | Comentário |
|------|--------|-----------|
| **Estrutura do projeto** | ✅ Alinhado | Backend Go (`internal/` + `pkg/` + `db/`) + Flutter com features, core, shared |
| **Stack** | ✅ Alinhado | Echo, pgx/sqlc, golang-migrate, zerolog, robfig/cron, Drift, Riverpod, Go Router, Dio, super_editor |
| **Schema (migrations)** | ⚠️ Divergências menores | Todos os 7 migrations cobrem o schema, mas com variações de naming e campos |
| **API Endpoints** | ⚠️ Gaps significativos | ~70% dos endpoints implementados, vários faltando |
| **Agent loop** | ✅ Alinhado | Tool calling loop com max 5 iterações funcional |
| **Tiered Context** | ⚠️ Incompleto | Tiers 0-2 implementados; Tiers 3-5 (RAG, notas relacionadas, memórias semânticas) faltam |
| **Tools do agent** | ⚠️ Incompleto | 15 de ~21 tools implementadas; 6 faltam |
| **LLM multi-provider** | ✅ Alinhado | Factory com Anthropic + DeepSeek + OpenAI-compat |
| **Rotinas** | ⚠️ Divergência de schema (UX ok) | Schema usa cron_expr ao invés de days_of_week + time_of_day, mas Flutter abstrai com DaySelector+TimePickerField |
| **Embeddings** | ❌ Stub | Pipeline de processamento criado mas sem integração real com OpenAI embeddings |
| **Busca** | ⚠️ Parcial | FTS funcional; semantic e hybrid são stubs |
| **Sync local-first** | ✅ Alinhado | Push/pull com isDirty, LWW, soft delete implementados |
| **Flutter** | ✅ Alinhado na arquitetura | Super_editor com markdown serializer, Drift local DB, DAOs, sync |
| **Onboarding** | ✅ Alinhado | Inbox + Soul + Rotinas + Settings criados em transação |
| **Telegram Gateway** | ✅ Alinhado | Fluxo de linking, webhook, free-form text → agent, notificações |

---

## 1. Estrutura do Projeto

### Escopo
```
backend/cmd/api/ → entrypoint
backend/internal/ → packages de domínio
backend/db/ → migrations + queries
backend/pkg/ → packages reutilizáveis
app/lib/ → Flutter
```

### Implementação
```
backend/cmd/server/main.go → ✅ (renomeado de cmd/api para cmd/server — detalhe menor)
backend/internal/ → ✅ 21 packages (agent, auth, contexts, db, dto, embeddings, gateway, handler, mapper, memories, notes, notifications, onboarding, routines, search, settings, soul, sync, tags, tasks, web)
backend/db/migrations/ → ✅ 7 migrations
backend/db/queries/ → ✅ 8 arquivos SQL
backend/pkg/ → ✅ (auth, config, db, llm, migrate, uid)
lib/ → ✅ (core/, features/, shared/)
```

> [!NOTE]
> O entrypoint é `cmd/server/` e não `cmd/api/` como no escopo. Diferença apenas de naming. O módulo Go está correto: `github.com/RigleyC/supanotes`.

> [!WARNING]
> O escopo define `backend/pkg/llm/openai.go` para o wrapper OpenAI, mas a implementação usa `openai_compat.go` — funciona via API compatível OpenAI (DeepSeek). Não há um client OpenAI "puro" separado.

---

## 2. Schema / Migrations

### Comparação detalhada

| Tabela do Escopo | Migration | Status | Notas |
|------|-----------|--------|-------|
| `users` | 000001 | ✅ | Campo `name` é NOT NULL na impl, nullable no escopo |
| `user_settings` | 000001 | ✅ | Default 'UTC' na impl vs 'America/Fortaleza' no escopo |
| `refresh_tokens` | 000001 | ✅ | Tem `revoked_at` na impl (melhor que não ter) |
| `device_tokens` | 000001 | ✅ | Suporta mais plataformas (`web`, `desktop` além de ios/android) |
| `contexts` | 000002 | ✅ | |
| `notes` | 000002 | ⚠️ | Falta coluna `embedding_status` na migration 002 — adicionada na 004 via ALTER |
| `tags` | 000002 | ✅ | |
| `note_tags` | 000002 | ✅ | |
| `note_links` | 000002 | ⚠️ | Implementado sem campo `relation` e sem `id` PK — usa PK composta `(source_id, target_id)` |
| `attachments` | 000002 | ✅ | Campos ligeiramente diferentes (`url NOT NULL` vs `url TEXT` nullable) |
| `tasks` | 000003 | ⚠️ | `due_date` é `TIMESTAMPTZ` na impl vs `DATE` no escopo; `status` é `VARCHAR(50)` sem CHECK constraint |
| `task_completions` | 000003 | ⚠️ | Falta coluna `due_date` (tracking de qual due_date foi cumprida); tem `status` ao invés |
| `note_embeddings` | 000004 | ✅ | Tem `id` PK na impl (escopo usa `note_id` como PK) — funcionalmente igual |
| `souls` | 000004 | ⚠️ | Coluna se chama `personality` na impl vs `content` no escopo |
| `memories` | 000004 | ✅ | Inclui `embedding vector(1536)` |
| `messages` | 000005 | ✅ | Tem `tool_calls JSONB` e `tool_call_id` extras (bom) |
| `routines` | 000006 | ⚠️ | Usa `cron_expr TEXT` ao invés de `days_of_week + time_of_day + brief_type`. Sem field `last_run_at` e sem `name` |
| `routine_logs` | 000006 | ⚠️ | Tem `user_id`, `status`, `error_msg` extras (melhoria). Falta `telegram_sent_at` |
| `telegram_links` | 000007 | ⚠️ | Falta `telegram_user_id` (escopo tem separado do chat_id). Tem `id` UUID PK ao invés de `user_id` como PK |
| `telegram_link_codes` | 000007 | ✅ | |

### Triggers

| Trigger | Status |
|---------|--------|
| `notes_search_vector_update` | ✅ Implementado com weights A/B (melhor que escopo!) |
| `notes_excerpt_update` | ⚠️ Implementado mas trunca em 140 chars sem strip markdown (escopo: 200 chars com regex strip) |
| `update_updated_at_column` | ✅ Helper genérico criado |

### Índices faltando

- `notes_active_idx` — WHERE deleted_at IS NULL (escopo)
- `tasks_user_open_idx` com filtro parcial
- `tasks_user_due_idx` com filtro parcial  
- `tasks_active_idx`
- `memories_embedding_idx` com ivfflat

> [!IMPORTANT]
> Os índices parciais de performance para queries filtradas por `deleted_at IS NULL` e `status = 'open'` não foram criados. Pode impactar performance em escala.

---

## 3. API Endpoints

### ✅ Implementados e registrados em [main.go](file:///c:/Users/rigleyc/projects/supanotes/backend/cmd/server/main.go)

| Endpoint (Escopo) | Rota Registrada | Status |
|---|---|---|
| `POST /auth/register` | ✅ | |
| `POST /auth/login` | ✅ | |
| `POST /auth/refresh` | ✅ | |
| `POST /auth/logout` | ✅ | |
| `GET /settings` | ✅ | |
| `PUT /settings` | ✅ | |
| `POST /notes` | ✅ | |
| `GET /notes` | ✅ | |
| `GET /notes/:id` | ✅ | |
| `DELETE /notes/:id` | ✅ | |
| `GET /contexts` | ✅ | |
| `POST /contexts` | ✅ | |
| `DELETE /contexts/:id` | ✅ | |
| `GET /tags` | ✅ | |
| `POST /tags` | ✅ | |
| `POST /agent/chat` | ✅ | |
| `GET /agent/messages` | ✅ | |
| `DELETE /agent/messages` | ✅ | |
| `GET /soul` | ✅ | |
| `PUT /soul` | ✅ | |
| `GET /memories` | ✅ | |
| `DELETE /memories/:id` | ✅ | |
| `POST /tasks` | ✅ | |
| `GET /tasks` | ✅ | |
| `DELETE /tasks/:id` | ✅ | |
| `POST /tasks/:id/complete` | ✅ | |
| `POST /tasks/:id/reopen` | ✅ | |
| `GET /tasks/today` | ✅ | |
| `POST /sync/pull` | ✅ | |
| `POST /sync/push` | ✅ | |
| `POST /gateway/telegram/webhook` | ✅ | |
| `POST /search` | ✅ (via RegisterRoutes) | |
| `GET /routines` | ✅ (via RegisterRoutes) | |
| `GET /routines/logs` | ✅ (via RegisterRoutes) | |
| `POST /device-tokens` | ✅ (extra, necessário) | |

### ⚠️ Divergências

| Endpoint (Escopo) | Status | Detalhe |
|---|---|---|
| `PATCH /notes/:id` | ⚠️ | Registrado como `PUT` ao invés de `PATCH` |
| `PATCH /tasks/:id` | ⚠️ | Registrado como `PUT` ao invés de `PATCH` |

### ❌ Não Implementados

| Endpoint do Escopo | Criticidade |
|---|---|
| `GET /notes/inbox` | 🔴 Alta — handler existe ([GetInbox](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/notes/handler.go#L217)) mas rota não registrada em main.go |
| `POST /notes/inbox/append` | 🔴 Alta — handler existe ([AppendToInbox](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/notes/handler.go#L235)) mas rota não registrada |
| `POST /notes/inbox/organize/plan` | 🔴 Alta — Flutter side totalmente construído ([InboxOrganizeSheet](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/widgets/inbox_organize_sheet.dart), [AgentRepository](file:///c:/Users/rigleyc/projects/supanotes/lib/features/agent/data/agent_repository.dart), [OrganizationPlan model](file:///c:/Users/rigleyc/projects/supanotes/lib/features/agent/domain/organization_plan.dart)), mas **backend endpoint não existe**. O próprio código Flutter documenta isso nos comentários (L10-L14). |
| `POST /notes/inbox/organize/apply` | 🔴 Alta — idem. Flutter chama `/agent/inbox/organize/apply` mas backend retorna 404 |
| `POST /agent/chat/stream` | 🔴 Alta — SSE streaming endpoint não implementado |
| `GET /notes/:id/tasks` | 🟡 Média — tasks por nota específica |
| `PATCH /routines/daily` | 🟡 Média — atualizar brief diário (existe via tool, mas endpoint REST usa via `RegisterRoutes` genérico) |
| `PATCH /routines/weekly` | 🟡 Média — idem |
| `POST /routines/daily/test` | 🟡 Média — existe via tool, mas não verificado como endpoint REST separado |
| `POST /routines/weekly/test` | 🟡 Média — idem |
| `POST /memories` | ✅ Implementado (não estava no escopo API mas existe — correto) |

> [!TIP]
> **Correção**: As rotas do Telegram (`GET /telegram/link`, `POST /telegram/link-code`, `DELETE /telegram/link`) **estão implementadas** via [gateway.RegisterRoutes](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/gateway/handler.go#L254-L259) chamado no [main.go L279](file:///c:/Users/rigleyc/projects/supanotes/backend/cmd/server/main.go#L279). O webhook público também está registrado em L280. ✅

> [!CAUTION]
> As rotas de **inbox** (`GET /notes/inbox`, `POST /notes/inbox/append`) têm handlers prontos em [notes/handler.go](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/notes/handler.go#L217-L253) mas **não estão registradas** no [main.go](file:///c:/Users/rigleyc/projects/supanotes/backend/cmd/server/main.go). O Flutter inteiro de organização de inbox está construído ([InboxOrganizeSheet](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/widgets/inbox_organize_sheet.dart) + [OrganizationPlan](file:///c:/Users/rigleyc/projects/supanotes/lib/features/agent/domain/organization_plan.dart)) mas o backend retorna 404 — é o gap front-back mais visível do projeto.

---

## 4. Agent Loop

### ✅ Alinhado com o escopo

- [loop.go](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/agent/loop.go): Tool calling loop com max 5 iterações ✅
- Mensagens acumuladas a cada iteração ✅
- Salva mensagem do usuário antes de chamar LLM ✅
- Salva resposta do assistant após cada turno ✅
- Usa `llmFact.For(TaskTypeAgentic)` para selecionar provider ✅
- Session management: client envia `session_id`, servidor é stateless ✅

### ⚠️ Detalhes
- O escopo diz que mensagens de tool usam `role: "user"` com `ToolUseID`, mas a implementação usa `role: "tool"` — **isso está correto** para a API da Anthropic (messages API exige role `"tool"` para tool results).

---

## 5. Tiered Context

### Comparação com [context.go](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/agent/context.go)

| Tier | Escopo | Implementado |
|------|--------|-------------|
| Tier 0 — SOUL | ✅ | `GetSoul()` |
| Tier 1 — Conversa recente | ✅ | `GetMessages()` com limit 10 |
| Tier 2 — Tasks (open/today/overdue) | ⚠️ Parcial | `GetTodayTasks()` implementado, mas falta `GetOpen` e `GetOverdue` separados |
| Tier 2 — Notas recentes (48h) | ✅ | `GetRecentNotes()` |
| Tier 2 — Stats do vault | ❌ | Não implementado |
| Tier 3 — RAG semântico | ❌ | Não implementado (depende de embeddings funcionais) |
| Tier 4 — Notas relacionadas | ❌ | Não implementado |
| Tier 5 — Memórias relevantes | ❌ | Não implementado (busca semântica nas memórias) |
| Tier 6 — Meta (timezone/data) | ✅ | `time.Now().Format(time.RFC1123)` |
| Token budget explícito | ❌ | Não implementado (sem constantes de budget, sem truncamento de notas) |
| `BuildForRoutine` | ✅ | Omite histórico corretamente |

> [!IMPORTANT]
> O Context Builder é funcional mas significativamente simplificado em relação ao escopo. Os Tiers 3-5 (RAG semântico + notas relacionadas + memórias semânticas) são a essência da IA proativa e estão faltando. O token budget explícito também não foi implementado.

---

## 6. Tools do Agent

### Implementadas em [tools.go](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/agent/tools.go)

| Tool (Escopo) | Status | Notas |
|---|---|---|
| `add_note` | ✅ | |
| `get_notes` | ❌ | Não implementada como tool |
| `search_notes` | ⚠️ | Stub — retorna erro |
| `append_to_note` | ❌ | Não implementada |
| `update_note` | ❌ | Não implementada |
| `link_notes` | ❌ | Não implementada |
| `get_vault_context` | ❌ | Não implementada |
| `get_inbox_note` | ✅ | |
| `append_to_inbox` | ✅ | |
| `plan_inbox_organization` | ❌ | Não implementada |
| `apply_inbox_organization` | ❌ | Não implementada |
| `add_task` | ✅ | ⚠️ Não aceita `note_id`, `due_date`, `recurrence` (schema parcial) |
| `complete_task` | ✅ | |
| `get_open_tasks` | ✅ | |
| `get_today_tasks` | ❌ | Não implementada como tool (apenas no context builder) |
| `update_task` | ❌ | Não implementada como tool |
| `save_memory` | ✅ | |
| `list_memories` | ✅ | |
| `delete_memory` | ❌ | Não implementada |
| `get_soul` | ✅ | |
| `update_soul` | ❌ | Não implementada |
| `list_routines` | ✅ | |
| `set_daily_brief_schedule` | ✅ | |
| `set_weekly_brief_schedule` | ✅ | |
| `test_daily_brief` | ✅ | |
| `test_weekly_brief` | ✅ | |

**Implementadas: 15/25** (~60%)

> [!WARNING]
> O `add_task` tool não aceita `note_id`, `due_date` nem `recurrence` no schema JSON. Isso significa que o agent não consegue criar tasks com data de vencimento ou recorrência — funcionalidade core do escopo.

> [!IMPORTANT]
> A **ownership validation** mencionada no escopo (seção 11) não está sendo feita em todas as tools. O `add_task` por exemplo passa `pgtype.UUID{}` vazio como `noteID`, não validando pertencimento.

---

## 7. LLM Multi-Provider

### ✅ Bem alinhado com [factory.go](file:///c:/Users/rigleyc/projects/supanotes/backend/pkg/llm/factory.go)

- Anthropic para `TaskTypeAgentic` ✅
- DeepSeek para `TaskTypeGenerate` ✅
- OpenAI-compat para `TaskTypeInboxOrganize` ✅ (extra, não no escopo)
- Retry com backoff exponencial + jitter ✅ ([retry.go](file:///c:/Users/rigleyc/projects/supanotes/backend/pkg/llm/retry.go))
- `isRetryable` checa 429, 500, 502, 503, 504 ✅

### ⚠️ Detalhe
- O retry faz string matching em mensagens de erro (`strings.Contains(msg, "429")`) ao invés de checar `StatusCode` em um `APIError` typed — menos robusto que o escopo sugere, mas funcional.

---

## 8. Rotinas

### ⚠️ Divergência de schema (mitigada na UI)

| Aspecto | Escopo | Implementação |
|---------|--------|--------------|
| Agenda | `days_of_week SMALLINT[] + time_of_day TIME` | `cron_expr TEXT` |
| Nome | `name TEXT NOT NULL` | Não tem campo `name` na tabela (gerado no Flutter via `RoutineModel.name`) |
| `brief_type` | Campo explícito com CHECK | `type TEXT` sem CHECK |
| `last_run_at` | Campo na tabela | Não existe |
| UI/tool | Configura dias da semana + horário | Configura cron expression |

> [!NOTE]
> **Correção**: A UI do Flutter **abstrai totalmente o cron_expr** para o usuário. O [BriefScheduleCard](file:///c:/Users/rigleyc/projects/supanotes/lib/features/routines/presentation/widgets/brief_schedule_card.dart) mostra checkboxes de dias ([DaySelector](file:///c:/Users/rigleyc/projects/supanotes/lib/features/routines/presentation/widgets/day_selector.dart)) + seletor de horário ([TimePickerField](file:///c:/Users/rigleyc/projects/supanotes/lib/features/routines/presentation/widgets/time_picker_field.dart)), e converte internamente via `buildCronExpr()` (L207-L211). O `DaySelector` opera em modo `single` para weekly e `multi` para daily (L118-L119), exatamente como o escopo prevê. A divergência é de schema, não de UX.

### ✅ O que está correto
- [runner.go](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/routines/runner.go): Runner funcional com semáforo, reload periódico, FCM push + Telegram notify ✅
- `BuildForRoutine` omite histórico de conversa ✅
- Maintenance job para cleanup de mensagens antigas ✅
- Lock por semáforo para evitar execução concorrente ✅

### ⚠️ Runner usa `TaskTypeAgentic` ao invés de `TaskTypeGenerate`
Na [runner.go L144](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/routines/runner.go#L144): `r.llmFactory.For(llm.TaskTypeAgentic)`. O escopo diz que rotinas devem usar DeepSeek V4 Flash (generate), não Claude Sonnet (agentic). Isso impacta custo.

---

## 9. Embeddings & Busca Semântica

### ❌ Maior gap da implementação

- [embeddings/service.go](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/embeddings/service.go): `GenerateAndSave()` é um **stub** que retorna erro.
- O cron de processamento de pending embeddings está configurado (30s interval em main.go) mas chama o stub.
- [search/service.go](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/search/service.go): FTS funcional ✅, mas `searchSemantic` e `searchHybrid` retornam erro.

> [!CAUTION]
> Sem embeddings funcionais, os Tiers 3-5 do context builder, a busca semântica, a busca híbrida e o RAG do agent ficam inoperantes. Esse é o gap mais crítico para a "IA proativa" do produto.

---

## 10. Sync Local-First (Flutter)

### ✅ Bem alinhado

- [sync_service.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/core/sync/sync_service.dart): Push dirty → Pull remote a cada 30s ✅
- Drift tables espelham PostgreSQL com `isDirty` ✅ ([notes.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/core/database/tables/notes.dart), [tasks.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/core/database/tables/tasks.dart))
- DAOs: notes, tasks, contexts, tags, task_completions ✅
- `ConnectivityMonitor` + sync on reconnect ✅
- `SharedPreferences` para `last_synced_at` ✅
- Backend sync: transacional com LWW via upsert ✅

### ⚠️ Detalhes
- O sync pull no Flutter não implementa paginação (`limit` + `cursor`), manda um pull simples.
- O backend não tem job de hard delete após 30 dias de soft delete (o runner tem `HardDeleteExpired` mas não sei se a query está implementada corretamente).

---

## 11. Flutter Frontend

### ✅ Arquitetura alinhada

| Componente | Status |
|------------|--------|
| Features: notes, tasks, agent, routines, search, settings, telegram, auth | ✅ |
| Super_editor para rich text | ✅ (fork customizado em [pubspec.yaml](file:///c:/Users/rigleyc/projects/supanotes/pubspec.yaml)) |
| Markdown round-trip | ✅ ([markdown_serializer.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/data/markdown_serializer.dart)) |
| Riverpod para estado | ✅ |
| Go Router | ✅ |
| Dio HTTP client | ✅ |
| Drift local DB | ✅ |
| Auth com flutter_secure_storage | ✅ |
| Quick capture FAB | ✅ ([quick_capture_fab.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/widgets/quick_capture_fab.dart)) |
| Inbox organize sheet | ✅ ([inbox_organize_sheet.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/widgets/inbox_organize_sheet.dart)) |
| Save indicator | ✅ |
| Task extraction do editor | ✅ (via `_extractTasks` em [note_editor_screen.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/note_editor_screen.dart)) |

---

## 12. Onboarding

### ✅ Alinhado com [onboarding/service.go](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/onboarding/service.go)

Transação única cria:
1. `user_settings` (timezone UTC) ✅
2. Inbox note (com conteúdo inicial) ✅
3. Soul (personalidade padrão) ✅
4. Daily routine (08:00 seg-sex) ✅
5. Weekly routine (09:00 segunda) ✅

> [!NOTE]
> O Soul padrão na implementação é bem mais simples que o do escopo. O escopo tem um template markdown detalhado com seções de Personalidade, Regras e Formato. A implementação tem uma string genérica curta. Isso pode afetar o comportamento do agent significativamente.

---

## 13. Checklist do Roadmap v1

Direto do [escopo seção 24](file:///c:/Users/rigleyc/projects/supanotes/.docs/notes-agent-scope-v3.md#L1646-L1668):

| Item | Status |
|------|--------|
| Setup Go + Echo + Docker Compose + zerolog + Argon2id | ✅ |
| Migration 001: users + user_settings + refresh_tokens + device_tokens | ✅ |
| Auth: register, login, refresh, logout (Argon2id + JWT) | ✅ |
| Migration 002: notes + tags + note_tags + note_links + inbox_note seed | ✅ |
| CRUD de notas + inbox note + contextos | ✅ |
| Migration 003: note_embeddings + souls + memories | ✅ (numerado como 004) |
| Migration 004: tasks + task_completions | ✅ (numerado como 003) |
| CRUD de tasks + lógica de recorrência | ✅ |
| Embeddings assíncronos ao criar/atualizar nota | ⚠️ Pipeline pronto, integração com OpenAI faltando |
| SOUL seed no registro | ✅ |
| Agent loop (Tiered context + tool calling + max 5 + retry) | ⚠️ Loop ok, tiered context incompleto |
| SSE endpoint `/api/v1/agent/chat/stream` | ❌ Não implementado |
| Migration 005: routines + routine_logs | ✅ (numerado como 006) |
| Rotinas: runner + timezone + lock + Telegram + FCM | ✅ (sem timezone do usuário) |
| Gateway Telegram integrado | ✅ |
| Busca híbrida (FTS + semântica + RRF) | ⚠️ FTS ok, semantic/hybrid stubs |
| FCM push notifications | ✅ |
| Sync pull/push endpoints | ✅ |
| Flutter: Drift database local | ✅ |
| Flutter: SyncService + ConnectivityMonitor | ✅ |
| Flutter: auth + notas + editor + agent chat + FAB + Go Router + Riverpod + Dio | ✅ |

---

## 14. Bugs / Inconsistências Encontradas

### 🐛 `note_editor_screen.dart` — Column dentro de CustomScrollView

No [note_editor_screen.dart L146-L159](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/note_editor_screen.dart#L146-L159): Um `Column` com `Expanded` dentro de `CustomScrollView.slivers` — isso deve causar um erro de layout. `CustomScrollView.slivers` espera Slivers, não widgets comuns. Deveria ser um `SliverFillRemaining` ou similar.

### 🐛 Routines Runner usa provider errado

[runner.go L144](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/routines/runner.go#L144): `r.llmFactory.For(llm.TaskTypeAgentic)` — deveria ser `llm.TaskTypeGenerate` para usar DeepSeek Flash em vez de Claude Sonnet nas rotinas.

### 🐛 Inbox routes não registradas

[notes/handler.go](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/notes/handler.go) tem `GetInbox()` e `AppendToInbox()` mas as rotas não estão em [main.go](file:///c:/Users/rigleyc/projects/supanotes/backend/cmd/server/main.go).

### 🐛 `add_task` tool sem parâmetros essenciais

O schema JSON do [AddTaskTool](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/agent/tools.go#L126-L141) só aceita `title`. Falta `note_id`, `due_date`, `recurrence`.

### 🐛 Task status "completed" vs "done"

O escopo define `status IN ('open', 'done')` mas a implementação usa `'completed'` em [tasks/service.go L129](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/tasks/service.go#L129). Inconsistência que pode causar bugs na query de tasks abertas.

---

## 15. Priorização dos Gaps

### 🔴 Críticos (bloqueiam uso real do produto)

1. **Integração real de embeddings com OpenAI** — sem isso, RAG e busca semântica não funcionam
2. **Rotas de inbox não registradas** — feature core já implementada mas inacessível
3. **SSE streaming endpoint** — necessário para UX fluida no chat e para o Telegram gateway
4. **Tools do agent incompletas** — `append_to_note`, `update_note`, `get_notes`, `delete_memory`, `update_soul` precisam existir para o agent ser útil
5. **Tiered context incompleto** — Tiers 3-5 são o diferencial do produto

### 🟡 Importantes (afetam UX e economia)

6. **Runner de rotinas usa provider errado** (custo 10x maior do que deveria)
7. **Anthropic model hardcoded errado** — usa `claude-3-5-sonnet-latest` ao invés de `claude-sonnet-4-20250514` como no escopo ([anthropic.go L80](file:///c:/Users/rigleyc/projects/supanotes/backend/pkg/llm/anthropic.go#L80))
8. **Prompt caching não funcional** — o header `anthropic-beta: prompt-caching-2024-07-31` é enviado, mas o system prompt é passado como `string` simples, não como `[]anthropicContent` com `CacheControl` block como o escopo especifica (seção 17). Sem o bloco `cache_control`, o cache nunca é ativado.
9. **Soul default mais completo** — agent precisa de instruções melhores
10. **add_task tool schema parcial** — agent não consegue criar tasks completas
11. **Status "completed" vs "done"** — inconsistência potencialmente quebrando queries

### 🟢 Menores (polish para v1)

12. PATCH vs PUT nos endpoints de notes/tasks
13. Excerpt truncando em 140 vs 200 chars
14. Índices parciais de performance
15. Token budget explícito no context builder
16. Timezone do usuário nas rotinas (atualmente usa UTC)
17. Schema da rotina usa `cron_expr` vs `days_of_week + time_of_day` — impacto zero na UX (Flutter abstrai), mas dificulta queries SQL no banco

---

## 16. Achados Extras (Investigação Profunda)

### ✅ Telegram Gateway — Mais completo do que aparentava

O [gateway/handler.go](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/gateway/handler.go) implementa o fluxo completo de linking:
- `/start <CODE>` → valida código, cria link, marca `used_at` ✅
- Free-form text → resolve `user_id` via `chat_id`, chama `agent.Chat()` ✅
- Mensagens de unlinked users → resposta amigável pedindo para conectar ✅
- Session ID determinístico por chat (SHA1 do chat_id) ✅
- [TelegramClient](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/gateway/telegram_client.go) com `SendMessage` + `NotifyUser` ✅
- [Repository](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/gateway/repository.go) com queries diretas (não usa sqlc — raw pgx) ✅

**Único gap no gateway**: Não implementa streaming progressivo com `editMessageText` (ticker 600ms) como o escopo descreve — envia resposta completa de uma vez. Isso depende do SSE endpoint que também não existe.

### ✅ Flutter Inbox Organize — Totalmente construído (sem backend)

O frontend implementou o fluxo completo:
- [InboxOrganizeSheet](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/widgets/inbox_organize_sheet.dart): Bottom sheet com estados loading/error/plan ✅
- [OrganizationPlan](file:///c:/Users/rigleyc/projects/supanotes/lib/features/agent/domain/organization_plan.dart): Model com `planId` + lista de items com `destinationType` (new_note/existing_note/keep) ✅
- [AgentRepository](file:///c:/Users/rigleyc/projects/supanotes/lib/features/agent/data/agent_repository.dart): Chama `POST /agent/inbox/organize/plan` e `/apply` ✅
- Toggle por item, contagem de selecionados, botão "Aplicar N selecionados" ✅
- Error handling graceful com "Tentar novamente" ✅

O código Flutter **sabe** que o backend ainda não tem esses endpoints — há um comentário explícito (L9-L14) documentando o 404.

### ✅ Flutter Routines UI — Alinhada com escopo apesar do schema diferente

- [BriefScheduleCard](file:///c:/Users/rigleyc/projects/supanotes/lib/features/routines/presentation/widgets/brief_schedule_card.dart): Card com switch de ativação, seletor de dias, picker de horário, botão testar ✅
- [DaySelector](file:///c:/Users/rigleyc/projects/supanotes/lib/features/routines/presentation/widgets/day_selector.dart): Modo `single` (weekly) e `multi` (daily) ✅
- [TimePickerField](file:///c:/Users/rigleyc/projects/supanotes/lib/features/routines/presentation/widgets/time_picker_field.dart): Seletor de horário nativo ✅
- `buildCronExpr()` converte dias+hora para cron expression antes de enviar ao backend ✅
- [BriefHistoryScreen](file:///c:/Users/rigleyc/projects/supanotes/lib/features/routines/presentation/brief_history_screen.dart): Lista histórico de briefs ✅
- Botão "Testar" com dry-run que mostra resultado em bottom sheet ✅

A UI é exatamente como o escopo descreve (seção 22), mesmo usando cron_expr internamente.

### ⚠️ Flutter Settings — Completo

O Flutter tem:
- [SettingsScreen](file:///c:/Users/rigleyc/projects/supanotes/lib/features/settings/presentation/settings_screen.dart) ✅
- [SoulEditorScreen](file:///c:/Users/rigleyc/projects/supanotes/lib/features/settings/presentation/soul_editor_screen.dart) — edição da personalidade do agent ✅
- [ContextsScreen](file:///c:/Users/rigleyc/projects/supanotes/lib/features/settings/presentation/contexts_screen.dart) — gestão de pastas/contextos ✅
- [TelegramLinkScreen](file:///c:/Users/rigleyc/projects/supanotes/lib/features/telegram/presentation/telegram_link_screen.dart) — geração de código + status de vínculo ✅

### ⚠️ Anthropic Client — Detalhes

- Model hardcoded em [anthropic.go L80](file:///c:/Users/rigleyc/projects/supanotes/backend/pkg/llm/anthropic.go#L80): `claude-3-5-sonnet-latest` ao invés de `claude-sonnet-4-20250514`
- System prompt como `string` simples (L51) ao invés de `[]anthropicContent` com `CacheControl` — prompt caching inoperante
- Mock mode quando `apiKey == "mock" || apiKey == ""` — bom para dev ✅
- Tool results mapeados corretamente para role `user` + type `tool_result` na API Anthropic ✅
- Suporta múltiplos tool calls por resposta ✅
