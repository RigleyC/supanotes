# 📋 NOTES AGENT — Escopo Técnico v3.0

## 1. VISÃO GERAL

App de notas com IA proativa. Markdown como núcleo, agent contextual com memória, rotinas recorrentes e busca semântica. Produto pessoal com arquitetura preparada para escala multi-usuário.

Referências: Granola, Mem, Motion — com foco em **IA proativa**, não só reativa.

---

## 2. PRINCÍPIOS DE DESIGN

- **Markdown como formato, banco como fonte da verdade** — o conteúdo da nota é Markdown, mas entidades estruturadas (tasks, metadados) vivem no banco. O editor renderiza cada elemento como widget interativo; o Markdown é output, não input
- **IA proativa** — agent age sem ser perguntado (rotinas, sugestões, briefs)
- **LLM gerenciado pelo backend** — o produto controla modelos, prompt caching, custos e segurança das chaves
- **Metadados separados do conteúdo** — markdown puro no `content`, todo o resto em colunas
- **Gateway como client** — Telegram e qualquer outra interface consomem o mesmo endpoint de agent
- **Local-first para notas e tasks** — o app lê e escreve em SQLite local (Drift). Sync com o servidor acontece em background. Features de IA (agent, busca semântica, rotinas) exigem conexão
- **Sem over-engineering no v1** — sem microserviços, Redis, CQRS, event sourcing

---

## 3. STACK

| Camada | Tecnologia | Motivo |
|--------|-----------|--------|
| Mobile/Desktop | Flutter | Cross-platform, já conhecido |
| Editor | super_editor (dev version) | Editor Flutter extensível, com controle fino sobre documento e Markdown |
| Backend | Go + Echo | Performance, simplicidade, goroutines |
| Queries | sqlc | Type-safe, sem ORM pesado |
| Driver PostgreSQL | pgx | Melhor driver Go pra Postgres |
| Migrations | golang-migrate | Simples, versionado (migrations incrementais) |
| Cron | robfig/cron | Rotinas agendadas |
| Hot reload | air | Dev experience |
| Banco | PostgreSQL | Relacional, confiável (rodando via Docker Compose local no dev) |
| Busca semântica | pgvector | Embeddings no Postgres |
| Busca full-text | tsvector (Postgres nativo) | FTS sem dependência extra |
| Embeddings | OpenAI text-embedding-3-small | Custo baixo, qualidade boa |
| LLM | Multi-provider gerenciado | Claude Sonnet (agentic) + DeepSeek V4 Flash (rotinas) |
| Push | Firebase Cloud Messaging | Flutter + Go |
| Infra | Railway | Simples, ~$10-15/mês |
| Storage futuro | Cloudflare R2 | Attachments |
| Gateway | Módulo Go integrado | Telegram integrado ao backend Go |
| Banco local (app) | Drift (SQLite) | Type-safe, reativo com streams, espelha schema do PostgreSQL |
| Logger | zerolog | Structured logger para performance |

---

## 4. ESTRUTURA DO PROJETO

```
notes-agent/
│
├── backend/                        # Go
│   ├── cmd/
│   │   └── api/
│   │       └── main.go             # Entry point
│   ├── internal/
│   │   ├── notes/
│   │   │   ├── handler.go
│   │   │   ├── service.go
│   │   │   └── repository.go
│   │   ├── agent/
│   │   │   ├── handler.go          # POST /api/v1/agent/chat
│   │   │   ├── loop.go             # Agent loop principal
│   │   │   ├── context.go          # Tiered context builder
│   │   │   ├── tools.go            # Definição + execução de tools
│   │   │   └── soul.go             # Carrega SOUL do banco
│   │   ├── routines/
│   │   │   ├── handler.go
│   │   │   ├── service.go
│   │   │   ├── repository.go
│   │   │   └── runner.go           # Cron runner
│   │   ├── embeddings/
│   │   │   ├── service.go          # Gera embeddings via OpenAI
│   │   │   └── repository.go       # Salva/busca no pgvector
│   │   ├── search/
│   │   │   ├── handler.go
│   │   │   └── service.go          # Busca híbrida (FTS + semântica)
│   │   ├── memories/
│   │   │   ├── service.go
│   │   │   └── repository.go
│   │   ├── auth/
│   │   │   ├── handler.go
│   │   │   ├── service.go          # JWT + refresh token (Argon2id)
│   │   │   └── middleware.go
│   │   ├── notifications/
│   │   │   └── fcm.go              # Firebase Cloud Messaging
│   │   ├── gateway/                # Telegram (módulo integrado)
│   │   │   ├── bot.go              # Telegraf ou telebot
│   │   │   ├── whisper.go          # STT (v3, voz)
│   │   │   └── bridge.go           # Liga as rotas do Echo ao agent
│   │   └── attachments/
│   │       ├── handler.go
│   │       └── service.go          # Upload → R2 (futuro)
│   ├── db/
│   │   ├── migrations/             # golang-migrate
│   │   └── queries/                # SQL puro → sqlc gera código
│   │       ├── notes.sql
│   │       ├── agent.sql
│   │       ├── routines.sql
│   │       └── memories.sql
│   │       └── search.sql
│   ├── pkg/
│   │   ├── llm/                    # Wrapper plugável de LLM
│   │   │   ├── client.go           # Interface comum
│   │   │   ├── anthropic.go        # Claude
│   │   │   └── openai.go           # OpenAI
│   │   └── config/
│   │       └── config.go
│   └── sqlc.yaml
│
└── app/                            # Flutter (Riverpod + Go Router + Dio + Drift)
    ├── lib/
    │   ├── main.dart
    │   ├── core/
    │   │   ├── api/                # HTTP client (Dio) — chamadas online
    │   │   ├── database/           # Drift database + DAOs (SQLite local)
    │   │   ├── sync/               # SyncService + ConnectivityMonitor
    │   │   ├── di/                 # Dependency injection
    │   │   └── router/             # Go Router
    │   ├── features/
    │   │   ├── notes/
    │   │   │   ├── data/
    │   │   │   │   ├── local/      # Lê/escreve do Drift (fonte primária)
    │   │   │   │   └── remote/     # API calls (sync only)
    │   │   │   ├── domain/
    │   │   │   └── presentation/
    │   │   ├── tasks/              # Feature de tasks (local-first)
    │   │   ├── agent/              # Online-only
    │   │   ├── routines/           # Online-only
    │   │   ├── search/             # Online-only
    │   │   └── settings/
    │   └── shared/
    │       ├── widgets/
    │       └── theme/
```

---

## 5. BANCO DE DADOS

### Schema completo

```sql
-- Usuários
CREATE TABLE users (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email       TEXT NOT NULL UNIQUE,
  name        TEXT,
  password_hash TEXT NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Configurações por usuário
CREATE TABLE user_settings (
  user_id         UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  timezone        TEXT DEFAULT 'America/Fortaleza',
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Auth
CREATE TABLE refresh_tokens (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID REFERENCES users(id) ON DELETE CASCADE,
  token_hash  TEXT NOT NULL,
  expires_at  TIMESTAMPTZ NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE device_tokens (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID REFERENCES users(id) ON DELETE CASCADE,
  token       TEXT NOT NULL,              -- FCM token
  platform    TEXT,                       -- 'android' | 'ios'
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Vínculo Telegram (um bot oficial do produto, muitos usuários)
CREATE TABLE telegram_links (
  user_id          UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  telegram_user_id BIGINT NOT NULL UNIQUE,
  telegram_chat_id BIGINT NOT NULL,
  username         TEXT,
  linked_at        TIMESTAMPTZ DEFAULT NOW()
);

-- Códigos temporários para conectar conta do app ao Telegram
CREATE TABLE telegram_link_codes (
  code       TEXT PRIMARY KEY,
  user_id    UUID REFERENCES users(id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at    TIMESTAMPTZ
);

-- Contextos (pastas)
CREATE TABLE contexts (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID REFERENCES users(id) ON DELETE CASCADE,
  slug        TEXT NOT NULL,
  name        TEXT NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, slug)
);

-- Notas
CREATE TABLE notes (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID REFERENCES users(id) ON DELETE CASCADE,
  context_id      UUID REFERENCES contexts(id) ON DELETE SET NULL,
  title           TEXT,
  content         TEXT NOT NULL,           -- markdown puro
  excerpt         TEXT,                    -- primeiros ~200 chars
  is_inbox        BOOLEAN DEFAULT FALSE,   -- rascunho/braindump único do usuário
  favorite        BOOLEAN DEFAULT FALSE,
  archived        BOOLEAN DEFAULT FALSE,
  embedding_status TEXT DEFAULT 'pending'   -- 'pending' | 'done' | 'failed'
    CHECK (embedding_status IN ('pending', 'done', 'failed')),
  search_vector   TSVECTOR,               -- FTS atualizado via trigger
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW(),
  deleted_at      TIMESTAMPTZ,             -- soft delete (sync local-first)
  CHECK (is_inbox = false OR archived = false)
);

-- Índices de busca
CREATE INDEX notes_fts_idx ON notes USING GIN (search_vector);
CREATE INDEX notes_user_idx ON notes (user_id, archived, created_at DESC);
CREATE INDEX notes_active_idx ON notes (user_id, deleted_at)
  WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX notes_one_inbox_per_user_idx
  ON notes (user_id)
  WHERE is_inbox = true AND deleted_at IS NULL;

-- A inbox note é criada por padrão no registro do usuário.
-- Ela não pode ser deletada nem arquivada pela aplicação.
-- Ela não aparece em listagens comuns, busca, embeddings, RAG ou notas relacionadas.

-- Trigger: atualiza search_vector automaticamente
-- Usa 'simple' em vez de 'portuguese' para suportar notas em qualquer idioma
CREATE OR REPLACE FUNCTION notes_search_vector_update() RETURNS trigger AS $$
BEGIN
  NEW.search_vector := to_tsvector('simple',
    COALESCE(NEW.title, '') || ' ' || COALESCE(NEW.content, '')
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER notes_search_vector_trigger
  BEFORE INSERT OR UPDATE ON notes
  FOR EACH ROW EXECUTE FUNCTION notes_search_vector_update();

-- Trigger: gera excerpt automaticamente (primeiros 200 chars sem markdown)
CREATE OR REPLACE FUNCTION notes_excerpt_update() RETURNS trigger AS $$
BEGIN
  NEW.excerpt := LEFT(REGEXP_REPLACE(NEW.content, '[#*`\[\]_>]', '', 'g'), 200);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER notes_excerpt_trigger
  BEFORE INSERT OR UPDATE ON notes
  FOR EACH ROW EXECUTE FUNCTION notes_excerpt_update();

-- Tags
CREATE TABLE tags (
  id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  name    TEXT NOT NULL,
  UNIQUE(user_id, name)
);

CREATE TABLE note_tags (
  note_id UUID REFERENCES notes(id) ON DELETE CASCADE,
  tag_id  UUID REFERENCES tags(id) ON DELETE CASCADE,
  PRIMARY KEY (note_id, tag_id)
);

-- Relações entre notas
CREATE TABLE note_links (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source_id UUID REFERENCES notes(id) ON DELETE CASCADE,
  target_id UUID REFERENCES notes(id) ON DELETE CASCADE,
  relation  TEXT NOT NULL DEFAULT 'related'
    CHECK (relation IN ('related', 'part_of', 'references')),
  UNIQUE(source_id, target_id)  -- evita links duplicados
);

-- Índice bidirecional: busca "o que essa nota linka" e "o que linka pra essa nota"
CREATE INDEX note_links_source_idx ON note_links (source_id);
CREATE INDEX note_links_target_idx ON note_links (target_id);

-- Cleanup de mensagens antigas (política: manter 90 dias)
-- Executado como rotina interna semanal
-- DELETE FROM messages WHERE created_at < NOW() - INTERVAL '90 days';

-- Attachments (metadados; arquivo vai pro R2 futuramente)
CREATE TABLE attachments (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  note_id    UUID REFERENCES notes(id) ON DELETE CASCADE,
  filename   TEXT NOT NULL,
  mime_type  TEXT,
  size_bytes INTEGER,
  url        TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Embeddings semânticos (um por nota, sem chunking no v1)
CREATE TABLE note_embeddings (
  note_id    UUID PRIMARY KEY REFERENCES notes(id) ON DELETE CASCADE,
  embedding  VECTOR(1536) NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX note_embeddings_idx ON note_embeddings
  USING ivfflat (embedding vector_cosine_ops);

-- SOUL (personalidade do agent, singleton por usuário)
CREATE TABLE souls (
  user_id    UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  content    TEXT NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Histórico de mensagens do agent
CREATE TABLE messages (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID REFERENCES users(id) ON DELETE CASCADE,
  session_id UUID NOT NULL,               -- agrupa mensagens por conversa
  role       TEXT NOT NULL,               -- 'user' | 'assistant' | 'tool'
  content    TEXT NOT NULL,
  tool_name  TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX messages_user_idx ON messages (user_id, session_id, created_at DESC);

-- Memórias de longo prazo
CREATE TABLE memories (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID REFERENCES users(id) ON DELETE CASCADE,
  content    TEXT NOT NULL,               -- fato sobre o usuário
  embedding  VECTOR(1536),               -- para retrieval semântico
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX memories_embedding_idx ON memories
  USING ivfflat (embedding vector_cosine_ops);

CREATE INDEX memories_user_idx ON memories (user_id);

-- Tasks (entidades no banco — substituem checklist items e hábitos)
CREATE TABLE tasks (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  note_id       UUID NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title         TEXT NOT NULL,
  status        TEXT NOT NULL DEFAULT 'open'
                  CHECK (status IN ('open', 'done')),
  position      INTEGER NOT NULL DEFAULT 0,       -- ordem dentro da nota
  due_date      DATE,                              -- opcional
  completed_at  TIMESTAMPTZ,                       -- quando foi concluída pela última vez
  recurrence    TEXT                                -- 'daily', 'weekdays', 'weekly', 'monthly' ou NULL
                  CHECK (recurrence IN ('daily', 'weekdays', 'weekly', 'monthly')
                         OR recurrence IS NULL),
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW(),
  deleted_at    TIMESTAMPTZ              -- soft delete (sync local-first)
);

CREATE INDEX tasks_note_idx ON tasks (note_id, position);
CREATE INDEX tasks_user_open_idx ON tasks (user_id, status, due_date)
  WHERE status = 'open' AND deleted_at IS NULL;
CREATE INDEX tasks_user_due_idx ON tasks (user_id, due_date)
  WHERE due_date IS NOT NULL AND status = 'open' AND deleted_at IS NULL;
CREATE INDEX tasks_active_idx ON tasks (user_id, deleted_at)
  WHERE deleted_at IS NULL;

-- Histórico de conclusões (especialmente útil para repeating tasks)
CREATE TABLE task_completions (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id       UUID NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  completed_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  due_date      DATE,                              -- a due_date que foi cumprida
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX task_completions_task_idx ON task_completions (task_id, completed_at DESC);

-- Rotinas agendadas
CREATE TABLE routines (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID REFERENCES users(id) ON DELETE CASCADE,
  brief_type  TEXT NOT NULL CHECK (brief_type IN ('daily', 'weekly')),
  name        TEXT NOT NULL,
  days_of_week SMALLINT[] NOT NULL,        -- daily: 1+ dias; weekly: exatamente 1 dia; 0=domingo ... 6=sabado
  time_of_day TIME NOT NULL,
  enabled     BOOLEAN DEFAULT TRUE,
  last_run_at TIMESTAMPTZ,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  CHECK (
    (brief_type = 'daily' AND cardinality(days_of_week) >= 1) OR
    (brief_type = 'weekly' AND cardinality(days_of_week) = 1)
  ),
  UNIQUE(user_id, brief_type)
);

-- Histórico de execuções de rotinas
CREATE TABLE routine_logs (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  routine_id  UUID REFERENCES routines(id) ON DELETE CASCADE,
  output      TEXT NOT NULL,
  telegram_sent_at TIMESTAMPTZ,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
```

---

## 6. API ENDPOINTS

```
Auth
POST   /api/v1/auth/register
POST   /api/v1/auth/login
POST   /api/v1/auth/refresh
POST   /api/v1/auth/logout

Settings
GET    /api/v1/settings
PUT    /api/v1/settings

Telegram (v1)
GET    /api/v1/telegram/link          status do vínculo
POST   /api/v1/telegram/link-code     gera código temporário para /start no bot
DELETE /api/v1/telegram/link          remove vínculo com Telegram
POST   /api/v1/gateway/telegram/webhook endpoint público chamado pelo Telegram

Notes
POST   /api/v1/notes
GET    /api/v1/notes              ?context_id= &has_tasks= &favorite= &limit= &cursor=
GET    /api/v1/notes/:id
PATCH  /api/v1/notes/:id
DELETE /api/v1/notes/:id
GET    /api/v1/notes/inbox
POST   /api/v1/notes/inbox/append
POST   /api/v1/notes/inbox/organize/plan   gera plano de organização sem editar notas
POST   /api/v1/notes/inbox/organize/apply   aplica plano confirmado e remove trechos organizados do inbox

Contexts
GET    /api/v1/contexts
POST   /api/v1/contexts
DELETE /api/v1/contexts/:id

Tags
GET    /api/v1/tags
POST   /api/v1/tags

Search
POST   /api/v1/search             { query, mode: "fts" | "semantic" | "hybrid" }

Agent
POST   /api/v1/agent/chat         { content, session_id? }
POST   /api/v1/agent/chat/stream  { content, session_id? } -> SSE stream
GET    /api/v1/agent/messages     ?limit=
DELETE /api/v1/agent/messages     limpa histórico

Soul
GET    /api/v1/soul
PUT    /api/v1/soul

Memories
GET    /api/v1/memories
DELETE /api/v1/memories/:id

Tasks
GET    /api/v1/tasks              ?note_id= &status= &due_before= &due_after= &limit= &cursor=
POST   /api/v1/tasks              { note_id, title, due_date?, recurrence? }
PATCH  /api/v1/tasks/:id          { title?, due_date?, recurrence?, position? }
DELETE /api/v1/tasks/:id
POST   /api/v1/tasks/:id/complete completa task (se recorrente, reabre com nova due_date)
POST   /api/v1/tasks/:id/reopen   reabre task manualmente
GET    /api/v1/tasks/today         tasks com due_date = hoje ou atrasadas
GET    /api/v1/notes/:id/tasks     tasks de uma nota específica (ordenadas por position)

Sync (local-first)
POST   /api/v1/sync/pull          { last_synced_at } → retorna registros com updated_at > last_synced_at (inclui soft-deleted)
POST   /api/v1/sync/push          { changes[] } → recebe mudanças do app, resolve conflitos por timestamp (last-write-wins)

Routines
GET    /api/v1/routines
GET    /api/v1/routines/logs        lista briefs gerados para leitura no app
PATCH  /api/v1/routines/daily       ajusta dias, horário e enabled do brief diário
PATCH  /api/v1/routines/weekly      ajusta dia, horário e enabled do brief semanal
POST   /api/v1/routines/daily/test  dry-run do brief diário, sem salvar nem notificar
POST   /api/v1/routines/weekly/test dry-run do brief semanal, sem salvar nem notificar
```

---

## 7. AGENT LOOP (Go)

```go
// internal/agent/loop.go

func (a *Agent) Chat(ctx context.Context, userID uuid.UUID, message string) (string, error) {
    // 1. Salva mensagem do usuário
    a.repo.SaveMessage(ctx, userID, "user", message)

    // 2. Monta tiered context
    agentCtx, err := a.contextBuilder.Build(ctx, userID, message)

    // 3. Chama LLM com tools
    messages := agentCtx.Messages // cópia inicial — será acumulada no loop

    response, err := a.llm.Complete(ctx, llm.Request{
        System:   agentCtx.System,
        Messages: messages,
        Tools:    AllTools,
    })

    // 4. Loop de tool calling (máximo 5 iterações para evitar loops infinitos)
    //    Acumula mensagens a cada iteração para que o Claude veja
    //    resultados de tools anteriores em chamadas multi-step
    const maxToolIterations = 5
    iterations := 0

    for response.StopReason == "tool_use" && iterations < maxToolIterations {
        iterations++

        // Acumula a resposta do assistant (com tool_use)
        messages = append(messages, Message{Role: "assistant", Content: response.Raw})

        toolResult, err := a.executeTool(ctx, userID, response.ToolUse)

        // Acumula o resultado da tool
        messages = append(messages, Message{
            Role:      "user",
            ToolUseID: response.ToolUse.ID,
            Content:   toolResult,
        })

        response, err = a.llm.Complete(ctx, llm.Request{
            System:   agentCtx.System,
            Messages: messages,
            Tools:    AllTools,
        })
    }

    // 5. Salva resposta
    a.repo.SaveMessage(ctx, userID, "assistant", response.Text)

    return response.Text, nil
}
```

### Error handling

O `llm.Complete` usa retry com backoff exponencial para erros transientes (429, 500, 503). Máximo 3 tentativas com backoff de 1s, 2s, 4s. Se todas falharem, retorna mensagem amigável ao usuário. Não tenta fallback para outro provider no v1.

```go
// pkg/llm/retry.go

func withRetry(fn func() (*Response, error)) (*Response, error) {
    backoff := []time.Duration{1 * time.Second, 2 * time.Second, 4 * time.Second}
    var lastErr error
    for i := 0; i <= len(backoff); i++ {
        resp, err := fn()
        if err == nil {
            return resp, nil
        }
        if !isRetryable(err) {
            return nil, err
        }
        lastErr = err
        if i < len(backoff) {
            time.Sleep(backoff[i])
        }
    }
    return nil, lastErr
}

func isRetryable(err error) bool {
    var apiErr *APIError
    if errors.As(err, &apiErr) {
        return apiErr.StatusCode == 429 || apiErr.StatusCode == 500 || apiErr.StatusCode == 503
    }
    return false
}
```

### Session management

O `session_id` define o escopo de uma conversa no agent chat:

- O **client** (Flutter) gera um UUID ao abrir a tela de chat
- Todas as mensagens naquela conversa usam o mesmo `session_id`
- Nova sessão quando: (a) o usuário toca "Nova conversa", ou (b) o app ficou em background por 30+ minutos
- O **servidor é stateless** — só agrupa mensagens pelo `session_id` recebido
- O `GetRecent` no context builder (Tier 1) filtra pelo `session_id` atual

Mesmo modelo usado por ChatGPT e Claude.

---

## 8. TIERED CONTEXT

O context builder monta o system prompt em camadas, respeitando um token budget explícito.

```go
// internal/agent/context.go

func (b *ContextBuilder) Build(ctx context.Context, userID uuid.UUID, query string) (*Context, error) {

    // Tier 0 — SOUL (fixo, sempre presente)
    soul := b.soulRepo.Get(ctx, userID)

    // Tier 1 — Conversa recente (últimas 10 mensagens)
    history := b.messageRepo.GetRecent(ctx, userID, 10)

    // Tier 2 — Contexto estruturado (sempre incluso, leve)
    //   → tasks abertas (query direta no banco, sem regex)
    //   → tasks com due_date = hoje ou atrasadas (inclui repeating tasks)
    //   → notas das últimas 48h
    //   → stats gerais do vault
    openTasks    := b.taskRepo.GetOpen(ctx, userID, 10)
    todayTasks   := b.taskRepo.GetDueToday(ctx, userID)
    overdueTasks := b.taskRepo.GetOverdue(ctx, userID, 5)
    recentNotes  := b.noteRepo.GetRecent(ctx, userID, 48*time.Hour, 5)
    stats        := b.noteRepo.GetVaultStats(ctx, userID)

    // Tier 3 — RAG semântico (baseado na query atual; exclui inbox note)
    //   → top 6 notas por similaridade de embedding
    semanticNotes := b.embeddingRepo.Search(ctx, userID, query, 6)

    // Tier 4 — Notas relacionadas
    //   → notas linkadas às recuperadas no Tier 3
    relatedNotes := b.noteRepo.GetLinked(ctx, semanticNotes.IDs(), 3)

    // Tier 5 — Memórias relevantes
    //   → top 5 memórias por similaridade semântica
    memories := b.memoryRepo.Search(ctx, userID, query, 5)

    // Tier 6 — Meta
    now := time.Now().In(userTimezone)

    system := buildSystemPrompt(soul, openTasks, todayTasks, overdueTasks, recentNotes, stats,
        semanticNotes, relatedNotes, memories, now)

    return &Context{
        System:   system,
        Messages: history,
    }, nil
}
```

### Token budget

Detalhes e código na seção 15 (Token Budget Explícito). Total: ~7.900 tokens de contexto, bem abaixo do limite de 200k do Claude Sonnet.

### Para rotinas

O prompt fixo do brief diário ou semanal substitui a query do usuário no Tier 3, e o histórico de conversa (Tier 1) é omitido.

```go
func (b *ContextBuilder) BuildForRoutine(ctx context.Context, userID uuid.UUID, routine Routine) (*Context, error) {
    // Tier 1 omitido (sem histórico de conversa)
    // Tier 3 usa routinePrompt(routine.BriefType) como query de embedding
}
```

---

## 9. SOUL (Personalidade)

Singleton por usuário no banco. Seed automático no registro.

### Conteúdo padrão

```markdown
# Personalidade
- Tom conversacional, direto, sem ser robótico
- Respostas curtas quando a tarefa é simples
- Proativo: se notar algo relevante, menciona sem ser solicitado
- Não pergunta mais de uma coisa por vez

# Regras
- Ao criar ou editar nota, confirma em uma linha o que foi feito
- Prefere append ao invés de sobrescrever para preservar histórico
- Usa save_memory quando o usuário revela preferências ou fatos relevantes
- Se não souber em qual nota adicionar, pergunta antes de agir

# Formato das notas
- Markdown sempre
- Tasks como entidades com título, due_date e recurrence quando relevante
- Datas em DD/MM/YYYY
```

### Tools do agent

```
get_soul()            → retorna soul atual
update_soul(content)  → substitui o soul
```

---

## 10. MEMÓRIAS

Dois tipos complementares:

| Tipo | Tabela | Função |
|------|--------|--------|
| **Curto prazo** | `messages` | Últimas 10 mensagens no contexto |
| **Longo prazo** | `memories` | Fatos sobre o usuário, com embedding |

### Como memórias são criadas

O agent usa a tool `save_memory` quando detecta:
- Preferências explícitas ("prefiro resumos curtos")
- Fatos recorrentes ("tenho standup toda segunda às 9h")
- Padrões de comportamento ("sempre quer checklist items separados por área")

### Como memórias são recuperadas

Via busca semântica no Tier 5 do context builder — só as mais relevantes para a query atual entram no contexto, não todas.

```go
// Busca semântica nas memórias
SELECT content
FROM memories
WHERE user_id = $1
ORDER BY embedding <=> $2   -- cosine similarity
LIMIT 5
```

### Tools do agent

```
save_memory(content)    → salva novo fato
list_memories()         → lista todas as memórias
delete_memory(id)       → remove memória específica
```

---

## 11. TOOLS DO AGENT

```go
var AllTools = []Tool{
    // Notas
    {Name: "add_note",          Description: "Cria uma nova nota."},
    {Name: "get_notes",         Description: "Lista notas com filtros opcionais."},
    {Name: "search_notes",      Description: "Busca notas por similaridade semântica."},
    {Name: "append_to_note",    Description: "Adiciona conteúdo ao final de uma nota existente."},
    {Name: "update_note",       Description: "Substitui o conteúdo de uma nota. Usar só quando explicitamente solicitado."},
    {Name: "link_notes",        Description: "Cria relação entre duas notas."},
    {Name: "get_vault_context", Description: "Retorna sumário do vault: contextos, stats, notas recentes."},
    {Name: "get_inbox_note",    Description: "Retorna o rascunho/braindump do usuário."},
    {Name: "append_to_inbox",   Description: "Adiciona captura rápida ao rascunho do usuário."},
    {Name: "plan_inbox_organization", Description: "Analisa o rascunho e propõe como distribuir trechos em notas existentes ou novas, sem editar nada."},
    {Name: "apply_inbox_organization", Description: "Aplica um plano confirmado e remove do rascunho apenas os trechos organizados."},

    // Tasks
    {Name: "add_task",           Description: "Cria uma task dentro de uma nota. Suporta due_date e recurrence opcionais."},
    {Name: "complete_task",      Description: "Completa uma task. Se recorrente, reabre com nova due_date."},
    {Name: "get_open_tasks",     Description: "Retorna tasks abertas do usuário, opcionalmente filtradas por nota."},
    {Name: "get_today_tasks",    Description: "Retorna tasks com due_date de hoje ou atrasadas."},
    {Name: "update_task",        Description: "Edita título, due_date ou recurrence de uma task."},

    // Memória
    {Name: "save_memory",       Description: "Salva fato importante sobre o usuário para uso futuro."},
    {Name: "list_memories",     Description: "Lista memórias salvas."},
    {Name: "delete_memory",     Description: "Remove uma memória."},

    // Soul
    {Name: "get_soul",          Description: "Retorna a personalidade atual do agent."},
    {Name: "update_soul",       Description: "Atualiza a personalidade do agent."},

    // Rotinas
    {Name: "list_routines",     Description: "Lista rotinas do usuário."},
    {Name: "set_daily_brief_schedule",  Description: "Ajusta dias, horário e status do brief diário pré-criado."},
    {Name: "set_weekly_brief_schedule", Description: "Ajusta dia, horário e status do brief semanal pré-criado."},
    {Name: "test_daily_brief",       Description: "Executa o brief diário em modo dry-run, sem salvar nem notificar."},
    {Name: "test_weekly_brief",      Description: "Executa o brief semanal em modo dry-run, sem salvar nem notificar."},
}
```

### Ownership validation

Toda tool que opera sobre um recurso específico valida que ele pertence ao usuário antes de executar. Nunca depende só do filtro da query.

```go
func (t *UpdateNoteTool) Execute(ctx context.Context, userID uuid.UUID, input UpdateNoteInput) (string, error) {
    note, err := t.repo.GetByID(ctx, input.NoteID)
    if err != nil || note.UserID != userID {
        return "nota não encontrada", nil // não revela se existe mas não é do usuário
    }
    // executa...
}
```

Regra aplicada em: `append_to_note`, `update_note`, `link_notes`, `apply_inbox_organization`, `delete_memory`, `set_daily_brief_schedule`, `set_weekly_brief_schedule`, `test_daily_brief`, `test_weekly_brief`, `add_task`, `complete_task`, `update_task`.

Todas as ~20 tools são enviadas a cada request. Com descrições curtas, isso ocupa ~800 tokens extras — irrelevante dentro do budget de 200k do Claude Sonnet. Enviar sempre evita que o agent fique "cego" a uma capacidade por falha de matching. Se no futuro a lista crescer acima de ~50 tools, a abordagem correta é usar o próprio LLM para classificar intent, não keywords fixas.

---

## 12. ROTINAS

Rotinas são limitadas a dois briefs pré-criados por usuário: diário e semanal. O usuário não configura o conteúdo do brief nem cria rotinas personalizadas; ele só ajusta agenda, horário e ativação. A rotina gera texto, salva o resultado para leitura no app e envia pelo Telegram quando o usuário tiver vínculo ativo.

O brief diário aceita múltiplos dias da semana. O brief semanal aceita exatamente um dia da semana.

O conteúdo e formato de cada brief serão definidos em arquivos Markdown dedicados, um para o brief diário e outro para o semanal. O runner usa esses arquivos como especificação do que gerar para cada `brief_type`. O brief diário deve incluir um resumo do progresso e listar as tasks pendentes do dia (incluindo repeating tasks).

### Rotinas padrão (seed no registro)

```go
var DefaultRoutines = []Routine{
    {
        BriefType:  "daily",
        Name:       "Daily Brief",
        DaysOfWeek: []int{1, 2, 3, 4, 5},
        TimeOfDay:  "08:00",
        Enabled:    true,
    },
    {
        BriefType:  "weekly",
        Name:       "Weekly Brief",
        DaysOfWeek: []int{1},
        TimeOfDay:  "09:00",
        Enabled:    true,
    },
}
```

### Runner

```go
// internal/routines/runner.go

var runningRoutines sync.Map // lock por routine_id para evitar execução concorrente

func (r *Runner) Start() {
    c := cron.New()

    c.AddFunc("* * * * *", func() {
        routines, _ := r.repo.GetEnabled()
        for _, routine := range routines {
            user, _ := r.userRepo.Get(routine.UserID)

            // Avalia dias/horário no timezone do usuário, não do servidor
            loc, _ := time.LoadLocation(user.Timezone)
            localNow := time.Now().In(loc)
            if !scheduleMatches(routine.DaysOfWeek, routine.TimeOfDay, localNow) { continue }

            // Lock por rotina: evita execução dupla se LLM demorar > 1min
            if _, running := runningRoutines.LoadOrStore(routine.ID, true); running {
                continue
            }

            go func(rt Routine, u User) {
                defer runningRoutines.Delete(rt.ID)

                ctx := r.contextBuilder.BuildForRoutine(context.Background(), u.ID, rt)
                result, err := r.agent.RunRoutine(ctx, rt)
                if err != nil { return }

                // Salva histórico para leitura no app
                log := r.repo.SaveLog(rt.ID, result)

                // Entrega por Telegram quando houver vínculo ativo
                if link, ok := r.telegramLinks.GetByUserID(u.ID); ok {
                    r.telegram.Send(link.ChatID, result)
                    r.repo.MarkTelegramSent(log.ID)
                }

                // Notifica o app de que há um novo brief para leitura
                r.notifier.Send(u.ID, "Novo brief disponível")
                r.repo.UpdateLastRun(rt.ID)
            }(routine, user)
        }
    })

    c.Start()
}
```

O runner também executa cleanup semanal (domingo 3h): `DELETE FROM messages WHERE created_at < NOW() - INTERVAL '90 days'`.

### Histórico de execuções

Mantém registro de cada execução na tabela `routine_logs` (definida no schema, seção 5) e é exposto no app para leitura posterior. Telegram é canal de entrega; `routine_logs` é a fonte do histórico exibido dentro do app.

### Testar brief

O usuário pode executar o brief diário ou semanal em modo dry-run para ver o output sem salvar log nem enviar notificação. Disponível via tool do agent e via endpoint:

```
POST /routines/daily/test    → executa o brief diário, sem salvar nem notificar
POST /routines/weekly/test   → executa o brief semanal, sem salvar nem notificar
```

```go
// internal/routines/service.go

func (s *RoutineService) Test(ctx context.Context, userID uuid.UUID, briefType string) (string, error) {
    routine := s.repo.GetByType(ctx, userID, briefType)

    // Monta contexto igual ao runner real
    agentCtx := s.contextBuilder.BuildForRoutine(ctx, userID, routine)

    // Chama LLM sem salvar log nem enviar notificação
    result, err := s.llm.Complete(ctx, llm.Request{
        System:   agentCtx.System,
        Messages: []Message{{Role: "user", Content: routinePrompt(routine.BriefType)}},
    })

    return result.Text, err
}
```

Via agent, o usuário pode testar assim:

```
"testa meu morning brief"
→ test_daily_brief()
→ agent retorna o output no chat, sem disparar notificação
```

### Pipeline completo

```
cron trigger
    ↓
busca daily/weekly briefs enabled
    ↓
avalia dias e horário no timezone do usuário
    ↓
lock por routine_id (evita duplicata)
    ↓
BuildForRoutine (tiered context sem histórico de conversa)
    ↓
RAG: embeddings/search baseado no prompt fixo do brief
    ↓
LLM gerenciado pelo backend
    ↓
salva em routine_logs
    ↓
Telegram message se houver vínculo + FCM "novo brief disponível" para o app
```

---

## 13. EMBEDDINGS ASSÍNCRONOS

Não bloqueia o endpoint. Nota aparece instantaneamente, embedding chega em segundo plano via cron de processamento. Falhas são rastreadas e re-tentadas — nenhuma nota fica invisível no RAG.

### Create e Update marcam como pending

```go
// internal/notes/service.go

func (s *NoteService) Create(ctx context.Context, note Note) (*Note, error) {
    // embedding_status já nasce como 'pending' pelo DEFAULT da coluna
    created, err := s.repo.Create(ctx, note)
    if err != nil { return nil, err }
    return created, nil
}

func (s *NoteService) Update(ctx context.Context, id uuid.UUID, content string) (*Note, error) {
    updated, err := s.repo.Update(ctx, id, content)
    if err != nil { return nil, err }

    if updated.IsInbox {
        // Inbox note nunca tem embedding
        s.embedRepo.Delete(ctx, updated.ID)
        return updated, nil
    }

    // Marca como pending — o cron processa; funciona como debounce natural
    // Se o editor faz auto-save a cada 2s, só a última versão será processada
    s.repo.SetEmbeddingStatus(ctx, updated.ID, "pending")
    return updated, nil
}
```

### Cron de processamento (a cada 10 minutos)

```go
// internal/embeddings/worker.go

// Roda junto com o cron runner, processa notas pendentes ou falhadas
c.AddFunc("*/10 * * * *", func() {
    // Busca notas com embedding_status = 'pending' ou 'failed' há mais de 5 min
    // Exclui inbox notes
    notes, _ := repo.GetPendingEmbeddings(ctx, 20)
    for _, note := range notes {
        truncated := truncateToTokens(note.Content, 500)
        embedding, err := embedder.Embed(ctx, truncated)
        if err != nil {
            repo.SetEmbeddingStatus(ctx, note.ID, "failed")
            log.Warn().Err(err).Str("note_id", note.ID.String()).Msg("embedding failed")
            continue
        }
        embedRepo.Upsert(ctx, note.ID, embedding)
        repo.SetEmbeddingStatus(ctx, note.ID, "done")
    }
})
```

### Por que não goroutine direta

- Goroutines soltas engolem erros silenciosamente — a nota fica invisível no RAG sem ninguém saber
- Auto-save do editor dispararia dezenas de chamadas à OpenAI por minuto para a mesma nota
- O cron de 10 min funciona como debounce natural e garante retry de falhas

---

## 14. MULTI-PROVIDER LLM

API gerenciada pelo backend — usuário nunca configura chave. Dois providers usados estrategicamente:

```
Agentic (chat, tool calling, raciocínio)  → Claude Sonnet 4.6 (Anthropic)
Generativo simples (daily/weekly briefs)   → DeepSeek V4 Flash
```

O SOUL é compartilhado entre os dois. O usuário configura a personalidade uma vez e o agent se comporta de forma consistente, independente do modelo/provider executando.


### Implementação

A `LLMFactory` abstrai o provider. Trocar de modelo é uma linha de código.

```go
// pkg/llm/factory.go

type TaskType string

const (
    TaskAgentic  TaskType = "agentic"   // chat, tool calling
    TaskGenerate TaskType = "generate"  // daily/weekly briefs, resumos
)

func (f *LLMFactory) For(task TaskType) llm.Client {
    switch task {
    case TaskAgentic:
        // Claude Sonnet — melhor tool calling do mercado
        return f.newAnthropicClient("claude-sonnet-4-20250514")
    default:
        // DeepSeek V4 Flash — 10x mais barato que Haiku para geração simples
        // API compatível com OpenAI (mesmo SDK, troca base_url)
        return f.newDeepSeekClient("deepseek-v4-flash")
    }
}
```

```go
// Agent loop — Claude Sonnet
func (a *Agent) Chat(ctx context.Context, userID uuid.UUID, msg string) (string, error) {
    client := a.llmFactory.For(TaskAgentic)
    // soul injetado normalmente
}

// Routine runner — DeepSeek V4 Flash, mesmo SOUL
func (r *Runner) runRoutine(ctx context.Context, routine Routine, user User) (string, error) {
    client := r.llmFactory.For(TaskGenerate)
    // mesmo soul.Content no system prompt
}
```

### Fronteira entre os providers

```
Claude Sonnet 4.6:               DeepSeek V4 Flash:
├── Chat com o agent             ├── Daily brief
├── Tool calling                 ├── Weekly brief
└── Onboarding conversacional    └── Resumos automáticos
```

### Escalar com economia

Se o custo subir com mais usuários, basta trocar `TaskAgentic` para `deepseek-v4-pro` na factory — economia de 59% sem mudar nenhum outro código. Outros modelos compatíveis: Gemini 2.5 Flash ($0.84/mês), Qwen 3.6 ($0.30/M input).

As chaves ficam em variáveis de ambiente do servidor, nunca expostas ao cliente.

```bash
# .env
ANTHROPIC_API_KEY=sk-ant-...     # Claude (chat agentic)
DEEPSEEK_API_KEY=sk-...          # DeepSeek (rotinas)
OPENAI_API_KEY=sk-...            # embeddings e Whisper
```

---

## 15. TOKEN BUDGET EXPLÍCITO

O context builder respeita um limite máximo de tokens. Se notas longas chegarem, são truncadas — nunca estouram o budget.

```go
// internal/agent/context.go

const (
    MaxContextTokens    = 8_000
    SoulBudget          = 500
    HistoryBudget       = 1_500
    StructuredBudget    = 800
    MemoriesBudget      = 500
    MetaBudget          = 100
    // Restante (~4.600) vai para RAG semântico + notas relacionadas
)

func (b *ContextBuilder) Build(ctx context.Context, userID uuid.UUID, query string) (*Context, error) {
    soul    := b.soulRepo.Get(ctx, userID)
    history := b.messageRepo.GetRecentBySession(ctx, userID, 10)
    openTasks := b.taskRepo.GetOpen(ctx, userID, 10)
    todayTasks := b.taskRepo.GetDueToday(ctx, userID)
    overdueTasks := b.taskRepo.GetOverdue(ctx, userID, 5)
    recent  := b.noteRepo.GetRecent(ctx, userID, 48*time.Hour, 5)
    stats   := b.noteRepo.GetVaultStats(ctx, userID)
    memories := b.memoryRepo.Search(ctx, userID, query, 5)

    ragBudget := MaxContextTokens - SoulBudget - HistoryBudget -
                 StructuredBudget - MemoriesBudget - MetaBudget

    // Notas semânticas + relacionadas respeitam o budget restante e excluem a inbox note
    semanticNotes := b.embeddingRepo.Search(ctx, userID, query, 6)
    relatedNotes  := b.noteRepo.GetLinked(ctx, semanticNotes.IDs(), 3)
    fittedNotes   := fitNotesInBudget(semanticNotes, relatedNotes, ragBudget)

    // ...monta system prompt
}

func fitNotesInBudget(semantic, related []Note, budget int) []Note {
    var result []Note
    used := 0
    for _, note := range append(semantic, related...) {
        tokens := estimateTokens(note.Content)
        if used+tokens > budget { break }
        result = append(result, note)
        used += tokens
    }
    return result
}
```

---

## 16. BUSCA HÍBRIDA

```go
// internal/search/service.go

func (s *SearchService) Search(ctx context.Context, userID uuid.UUID, query string, mode string) ([]Note, error) {
    switch mode {
    case "fts":
        return s.fullTextSearch(ctx, userID, query)
    case "semantic":
        return s.semanticSearch(ctx, userID, query)
    default: // "hybrid"
        return s.hybridSearch(ctx, userID, query)
    }
}

func (s *SearchService) hybridSearch(ctx context.Context, userID uuid.UUID, query string) ([]Note, error) {
    // 1. FTS com ranking
    ftsResults, _ := s.repo.FTSSearch(ctx, userID, query, 20)

    // 2. Semântica com similaridade
    embedding, _ := s.embedder.Embed(ctx, query)
    semanticResults, _ := s.repo.SemanticSearch(ctx, userID, embedding, 20)

    // 3. Reciprocal Rank Fusion (RRF) — combina os rankings
    return rrf(ftsResults, semanticResults, 10), nil
}
```

```sql
-- FTS query
SELECT id, title, excerpt,
       ts_rank(search_vector, query) as rank
FROM notes, plainto_tsquery('simple', $1) query
WHERE user_id = $2
  AND search_vector @@ query
  AND archived = false
  AND is_inbox = false
ORDER BY rank DESC
LIMIT 20;

-- Semântica query
SELECT n.id, n.title, n.excerpt,
       1 - (ne.embedding <=> $1) as similarity
FROM note_embeddings ne
JOIN notes n ON n.id = ne.note_id
WHERE n.user_id = $2
  AND n.archived = false
  AND n.is_inbox = false
ORDER BY ne.embedding <=> $1
LIMIT 20;
```

---

## 17. LLM CLIENT (Anthropic gerenciado)

API gerenciada pelo backend. Chaves ficam em variáveis de ambiente do servidor, nunca expostas ao cliente. O modelo é selecionado via `LLMFactory` baseado no tipo de tarefa — veja seção 14.

```go
// pkg/llm/client.go

type Client interface {
    Complete(ctx context.Context, req Request) (*Response, error)
}

type Request struct {
    Model    string    // injetado pela factory
    System   string
    Messages []Message
    Tools    []Tool
}

// OrganizationPlan e OrganizationPlanItem vivem em internal/notes/types.go
// (tipos de domínio de notas, não do LLM client)

type Response struct {
    Text       string
    StopReason string
    ToolUse    *ToolUse
    Usage      Usage
}

type Usage struct {
    InputTokens         int
    OutputTokens        int
    CacheCreationTokens int
    CacheReadTokens     int
}

// pkg/llm/anthropic.go

type AnthropicClient struct {
    APIKey string
    http   *http.Client
}

func (c *AnthropicClient) Complete(ctx context.Context, req Request) (*Response, error) {
    // Prompt caching: SOUL + contexto estruturado + notas RAG cacheados por 5min
    // ~85% de economia no contexto estático dentro da mesma sessão

    payload := anthropicRequest{
        Model:     req.Model,
        MaxTokens: 1024,
        System: []anthropicContent{
            {
                Type:         "text",
                Text:         req.System,
                CacheControl: &anthropicCache{Type: "ephemeral"}, // ← ponto de cache
            },
        },
        Messages: buildMessages(req.Messages),
        Tools:    buildTools(req.Tools),
    }

    body, _ := json.Marshal(payload)

    httpReq, _ := http.NewRequestWithContext(ctx, "POST",
        "https://api.anthropic.com/v1/messages",
        bytes.NewReader(body),
    )
    httpReq.Header.Set("x-api-key", c.APIKey)
    httpReq.Header.Set("anthropic-version", "2023-06-01")
    httpReq.Header.Set("anthropic-beta", "prompt-caching-2024-07-31")
    httpReq.Header.Set("content-type", "application/json")

    resp, err := c.http.Do(httpReq)
    if err != nil { return nil, err }
    defer resp.Body.Close()

    var result anthropicResponse
    json.NewDecoder(resp.Body).Decode(&result)

    logUsage(result.Usage) // debug e controle de custo

    return &Response{
        Text:       result.extractText(),
        StopReason: result.StopReason,
        ToolUse:    result.extractToolUse(),
        Usage: Usage{
            InputTokens:         result.Usage.InputTokens,
            OutputTokens:        result.Usage.OutputTokens,
            CacheCreationTokens: result.Usage.CacheCreationInputTokens,
            CacheReadTokens:     result.Usage.CacheReadInputTokens,
        },
    }, nil
}
```

---

## 18. GATEWAY TELEGRAM (v1)

O gateway consome o mesmo backend. Não tem lógica de agent — só traduz entre Telegram e a API.

O produto usa um bot oficial compartilhado, por exemplo `@notes_agent_bot`. O token do BotFather fica em variável de ambiente do backend/gateway e nunca é configurado pelo usuário no app.

### Identidade e vínculo

O token do bot identifica o bot, não o usuário final. Cada mensagem recebida do Telegram vem com `from.id`; o gateway resolve esse `telegram_user_id` para um `user_id` interno antes de chamar o agent.

Fluxo de conexão:

```
usuário logado abre Settings > Telegram
    ↓
app chama POST /telegram/link-code
    ↓
backend gera código temporário (ex: AB12CD)
    ↓
usuário manda /start AB12CD para @notes_agent_bot
    ↓
gateway recebe from.id e chat.id pelo webhook
    ↓
backend valida código e salva telegram_links(user_id, telegram_user_id, telegram_chat_id)
    ↓
mensagens futuras do Telegram resolvem user_id por telegram_user_id
```

Se uma mensagem chega de um `telegram_user_id` sem vínculo, o bot responde pedindo para conectar pelo app.

### Streaming de texto

Telegram suporta edição progressiva de mensagens via `editMessageText`, o que permite simular streaming. Editar a cada token seria spam na API — um ticker de 600ms equilibra fluidez e rate limit.

```go
// gateway/telegram/bot.go

bot.Handle(telebot.OnText, func(c telebot.Context) error {
    userID, err := linkRepo.ResolveUserID(ctx, c.Sender().ID)
    if err != nil {
        return c.Send("Conecte sua conta pelo app antes de usar o bot.")
    }

    // 1. Envia placeholder imediatamente
    msg, _ := c.Bot().Send(c.Recipient(), "...")

    // 2. Consome SSE do backend
    stream, _ := apiClient.AgentChatStream(userID, c.Text())
    defer stream.Close()

    var accumulated string
    ticker := time.NewTicker(600 * time.Millisecond)
    defer ticker.Stop()

    for {
        select {
        case chunk, ok := <-stream.Chunks():
            if !ok {
                // Stream encerrado — edita com texto final
                c.Bot().Edit(msg, accumulated)
                return nil
            }
            accumulated += chunk

        case <-ticker.C:
            if accumulated != "" {
                c.Bot().Edit(msg, accumulated)
            }
        }
    }
})
```

O usuário ativa o gateway nas settings do app gerando um código temporário e enviando `/start CODIGO` para o bot oficial. O app mostra o status do vínculo e permite desconectar.

---

## 19. AUTH

```
Registro → Argon2id hash da senha
Login    → JWT access token (15min) + refresh token (30 dias, hash no banco)
Refresh  → troca refresh token por novo par
Logout   → invalida refresh token
```

Sem OAuth externo no v1. Email + senha.

---

## 20. PUSH NOTIFICATIONS (FCM)

```go
// internal/notifications/fcm.go

func (n *Notifier) Send(userID uuid.UUID, message string) {
    tokens, _ := n.repo.GetDeviceTokens(userID)
    for _, token := range tokens {
        n.fcm.Send(&messaging.Message{
            Token: token,
            Notification: &messaging.Notification{
                Title: "Notes Agent",
                Body:  message[:min(len(message), 200)],
            },
        })
    }
}
```

---

## 21. STREAMING (v1)

Backend Go expõe SSE (Server-Sent Events) no endpoint de chat:

```
POST /api/v1/agent/chat/stream
→ Content-Type: text/event-stream
→ data: {"delta": "trecho da resposta"}
→ data: {"done": true}
```

O gateway Telegram e o app Flutter consomem SSE em tempo real. O Telegram usa essa resposta progressiva com um ticker de 600ms para editar mensagens e simular streaming. No Flutter, SSE é consumido via `Dio` com `ResponseType.stream` + parser manual (~30 linhas).

---

## 22. SIMPLICIDADE DE USO

### SOUL nas settings avançadas

O usuário nunca precisa saber que o SOUL existe para usar o app. Fica em settings avançadas — presente para quem quiser customizar, invisível para quem não liga.

```
Settings
├── Conta
├── Notificações
└── Avançado
    ├── Personalidade do agent   ← SOUL aqui
    ├── Contextos
    └── Dados
```

O agent funciona com o SOUL padrão desde o primeiro uso. Nenhuma configuração obrigatória.

---

### Agenda dos briefs

O usuário ajusta apenas a agenda dos dois briefs pré-criados: diário e semanal. A UI não expõe cron expression, prompt ou criação de rotina personalizada; mostra controles simples de dias, horário, teste e ativação.

```
Brief diário
[ ] Ativo
Dias: Seg Ter Qua Qui Sex
Horário: 08:00
[Testar]

Brief semanal
[ ] Ativo
Dia: Segunda
Horário: 09:00
[Testar]
```

Via agent, o usuário também pode pedir mudanças na agenda desses dois briefs, por exemplo "ativa meu brief diário às 8h nos dias úteis". O agent usa `set_daily_brief_schedule` ou `set_weekly_brief_schedule`; ele não altera o conteúdo do brief nem cria rotinas arbitrárias.

---

### Captura rápida

O caso mais frequente é "preciso anotar isso agora". Menos atrito = mais uso.

O usuário tem uma única nota especial chamada rascunho/inbox. Ela funciona como braindump contínuo: o usuário anota sem classificar, depois clica em "Organizar" para o agent distribuir os trechos em notas existentes ou novas.

### Organizar rascunho

O fluxo de organização é explícito e confirmado pelo usuário:

```
usuário escreve no rascunho
    ↓
clica "Organizar"
    ↓
agent gera Organization Plan
    ↓
usuário revisa e confirma
    ↓
backend aplica o plano
    ↓
trechos aplicados são removidos do rascunho
```

O plano pode propor:
- anexar trecho a uma nota existente;
- criar nova seção em uma nota existente;
- criar nova nota;
- manter trecho no rascunho quando o destino for ambíguo.

No v1, o agent não organiza o rascunho automaticamente sem confirmação. Após aplicar o plano, apenas os trechos organizados são removidos da inbox; trechos ambíguos continuam no rascunho.

A aplicação do plano deve ser transacional: cria/atualiza notas e remove trechos do rascunho no mesmo commit. Se qualquer escrita falhar, o rascunho fica intacto.

```go
// internal/notes/service.go

func (s *NoteService) ApplyOrganizationPlan(ctx context.Context, userID uuid.UUID, plan OrganizationPlan) error {
    return s.db.WithTx(ctx, func(tx pgx.Tx) error {
        for _, item := range plan.Items {
            switch item.Action {
            case "append_to_note":
                if err := s.repo.AppendContentTx(ctx, tx, item.TargetNoteID, item.ProposedText); err != nil {
                    return err // rollback automático
                }
            case "create_note":
                if err := s.repo.CreateWithTx(ctx, tx, userID, item.TargetTitle, item.ProposedText); err != nil {
                    return err
                }
            case "create_section":
                if err := s.repo.AppendSectionTx(ctx, tx, item.TargetNoteID, item.SectionHeading, item.ProposedText); err != nil {
                    return err
                }
            // "keep_in_inbox" → não faz nada, trecho permanece
            }
        }
        // Remove apenas os trechos organizados do inbox
        return s.repo.RemoveInboxSectionsTx(ctx, tx, userID, plan.OrganizedSections())
    })
}
```

**Widget na home screen (iOS/Android)**
- Campo de texto direto
- Salva no rascunho/inbox automaticamente

**Atalho no lock screen**
- Segurar botão de ação → grava áudio → Whisper transcreve → salva no rascunho/inbox

**Dentro do app**
- FAB (floating action button) sempre visível
- Tap → campo de texto imediato, sem navegar pra nenhuma tela

O usuário captura primeiro, organiza depois — ou deixa o agent organizar.

---

## 23. ARQUITETURA LOCAL-FIRST

O app é local-first para notas e tasks: toda leitura e escrita acontece no SQLite local (via Drift), e a sincronização com o servidor PostgreSQL ocorre em background, sem bloquear a UI. A inspiração é o Apple Notes.

### Escopo offline vs online

| Feature | Funciona offline? |
|---------|:-:|
| Criar/editar/deletar notas | ✅ |
| Criar/editar/completar tasks | ✅ |
| Listar notas e tasks | ✅ |
| Agent chat | ❌ |
| Busca semântica/FTS | ❌ |
| Rotinas/Briefs | ❌ |
| Configurações | ❌ |

O app exibe um indicador visual sutil (badge/banner) quando está offline, e desabilita as features que exigem conexão.

### Banco local (Drift)

O schema Drift no Flutter espelha as tabelas do PostgreSQL para `notes`, `tasks`, `contexts` e `tags`. Cada tabela local inclui uma coluna extra `isDirty` (boolean) que marca registros criados ou editados offline que ainda não foram sincronizados.

```dart
class LocalNotes extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get contextId => text().nullable()();
  TextColumn get title => text().nullable()();
  TextColumn get content => text()();
  TextColumn get excerpt => text().nullable()();
  BoolColumn get isInbox => boolean().withDefault(const Constant(false))();
  BoolColumn get favorite => boolean().withDefault(const Constant(false))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  BoolColumn get isDirty => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
```

### Fluxo de dados

```
┌──────────────────────────────────────────────────────┐
│                    Flutter App                        │
│                                                      │
│  UI (Riverpod) ←──stream──→ Drift (SQLite local)     │
│       │                          ↑                   │
│       │                     isDirty=true              │
│       │                          │                   │
│       └──── cria/edita ──────────┘                   │
│                                                      │
│  SyncService (background)                            │
│       │                                              │
│       ├── push (dirty → servidor)                    │
│       └── pull (servidor → local)                    │
│                                                      │
└──────────────┬───────────────────────────────────────┘
               │
               ▼
        API Go (PostgreSQL)
```

**Leitura**: sempre do Drift local (instantâneo)
**Escrita**: grava no Drift local → marca `isDirty=true` → SyncService envia em background
**Sync**: ao abrir o app, ao reconectar, e periodicamente (cada 30s enquanto online)

### Sync incremental

A sync usa cursor baseado em `updated_at`:

1. **Push**: app envia registros com `isDirty=true` para `POST /api/v1/sync/push`. O servidor atribui `updated_at = NOW()` — timestamps são definidos pelo servidor, não pelo client. Isso elimina problemas de relógio desincronizado entre dispositivos
2. **Pull**: app pede registros com `updated_at > último_sync` via `POST /api/v1/sync/pull`. Suporta `limit` + `cursor` para paginação (importante na primeira abertura)
3. **Resolução de conflitos**: last-write-wins **por registro** — o registro com `updated_at` mais recente (atribuído pelo servidor) vence inteiro. Field-level merge fica para v2+ se necessário
4. **Primeira abertura**: full sync paginado (pull com cursor, não baixa tudo de uma vez)

> **Por que LWW por registro e não por campo?** LWW por campo requer timestamps individuais por coluna ou CRDTs — complexidade desproporcional para o v1. Como tasks são entidades separadas (não embarcadas no Markdown da nota), o caso mais comum de conflito (editar nota + completar task) já é resolvido naturalmente: são registros diferentes.

### Soft delete

Deleções usam soft delete (`deleted_at` no banco). Quando o usuário deleta offline:

1. O registro é marcado com `deleted_at` e `isDirty=true` no SQLite local
2. Na próxima sync, o servidor recebe e marca `deleted_at` também
3. Registros com `deleted_at` não aparecem na UI mas são sincronizados
4. Um job periódico no servidor faz hard delete após 30 dias

Todas as queries (sqlc) no backend filtram por `WHERE deleted_at IS NULL` para não retornar registros deletados. Isso inclui as queries do agent (RAG, context builder, tools).

---

## 24. ROADMAP

### v1 — Core funcional (8-10 semanas)
- [ ] Setup Go + Echo + Docker Compose + zerolog + Argon2id
- [ ] Migration 001: users + user_settings + refresh_tokens + device_tokens
- [ ] Auth: register, login, refresh, logout (Argon2id + JWT)
- [ ] Migration 002: notes + tags + note_tags + note_links + inbox_note seed
- [ ] CRUD de notas + inbox note + contextos (banco, sem UI)
- [ ] Migration 003: note_embeddings + souls + memories
- [ ] Migration 004: tasks + task_completions
- [ ] CRUD de tasks + lógica de recorrência (complete → reopen com nova due_date)
- [ ] Embeddings assíncronos ao criar/atualizar nota
- [ ] SOUL seed no registro (default hardcoded no backend)
- [ ] Agent loop (Tiered context + tool calling + max 5 iterações + retry com backoff)
- [ ] SSE endpoint `/api/v1/agent/chat/stream`
- [ ] Migration 005: routines + routine_logs
- [ ] Rotinas: runner + timezone + lock + entrega Telegram + FCM push
- [ ] Gateway Telegram integrado (módulo no backend Go)
- [ ] Busca híbrida (FTS + semântica + RRF)
- [ ] FCM push notifications
- [ ] Endpoints de sync: POST /api/v1/sync/pull e /api/v1/sync/push (LWW por registro, server timestamps)
- [ ] Flutter: Drift database local (schema espelhado do PostgreSQL)
- [ ] Flutter: SyncService + ConnectivityMonitor (push dirty → pull remoto)
- [ ] Flutter: auth + notas + editor (super_editor com widgets customizados para tasks, headings, listas etc.) + agent chat + captura rápida (FAB) + Go Router + Riverpod + Dio

---

## 25. ESTIMATIVA DE CUSTO

### Por usuário/mês (LLM)

Premissas: 10 msgs/dia, ~1.5 tool calls/turno, prompt caching ativo.

```
Chat (Claude Sonnet 4.6, 300 turnos):
  Input:  ~1.035M tokens × $3.00/M  = $3.11
  Output: ~180K tokens   × $15.00/M = $2.70
  Subtotal: $5.81

Rotinas (DeepSeek V4 Flash, 26 briefs):
  Input:  ~104K tokens × $0.14/M = $0.01
  Output: ~20.8K tokens × $0.28/M = $0.01
  Subtotal: $0.02

Embeddings (OpenAI text-embedding-3-small):
  ~65K tokens/mês × $0.02/M ≈ $0.00

──────────────────────────────
Total LLM: ~$5.83/usuário/mês
```

### Infra (Railway)

```
PostgreSQL:     ~$5/mês
Go backend:     ~$5/mês
─────────────────────
Total infra:    ~$10/mês
```

### Total consolidado

```
1 usuário:   ~$15.83/mês (infra + LLM)
10 usuários: ~$70.30/mês (infra $12 + LLM $58.30)
```

### Alternativas mais baratas (se precisar escalar)

| Cenário | Total LLM/mês | vs atual |
|---------|------------|----------|
| Claude Sonnet + DeepSeek Flash (atual) | $5.83 | baseline |
| DeepSeek V4 Pro + Flash | $2.45 | -58% |
| Gemini 2.5 Flash (tudo) | $0.84 | -86% |
| DeepSeek V4 Flash (tudo) | $0.21 | -96% |

A `LLMFactory` permite trocar de provider com uma linha de código.

---

## 26. FUTURO (v2+)

Features e melhorias planejadas após o v1. A arquitetura atual suporta todas sem quebrar.

### v2 — Polish (3-4 semanas)

- [ ] **Notas compartilhadas (read-only)** — compartilhar nota com outro usuário; agent do destinatário enxerga no contexto e age proativamente. Schema: tabela `note_shares` com `permission`. Write permission em v3 (requer conflict resolution)
- [ ] **Wikilinks entre notas** — referências bidirecionais dentro do Markdown
- [ ] **Attachments** — upload local → Cloudflare R2
- [ ] **Notas relacionadas na UI** — exibir links e notas similares por embedding
- [ ] **Widget home screen** — campo de texto direto para captura rápida (iOS/Android)
- [ ] **Contexts na UI** — expor pastas/contextos que já existem no banco

### v3 — Expansão (2-3 semanas)

- [ ] **Voz no Telegram** — STT via Whisper, TTS para respostas em áudio, preferência configurável (`mirror`/`text`/`voice` em `user_settings`)
- [ ] **OAuth (Google, Apple)** — login social além de email/senha
- [ ] **Subagents** — agentes internos especializados para tarefas complexas
- [ ] **Insights proativos em background** — proatividade além de rotinas/briefs
- [ ] **Revisions/history de notas** — versionamento de conteúdo

### Sem previsão (escala futura)

- Microserviços, Redis
- Event sourcing / CQRS
- Colaboração realtime
- Sync distribuído / CRDTs
- Billing / planos pagos
