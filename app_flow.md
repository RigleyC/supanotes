# SupaNotes — Fluxo do App (v1)

Documento de referência do fluxo alvo do app, definido em sessão de entrevista. Define o **core loop**, navegação, comportamento de cada feature, e o que entra/sai da v1.

> **Status**: alvo. Mudanças aqui descrevem o que o app deve ser após o ajuste. Diff de implementação fica em outros artefatos.

---

## Core Loop

**App de notas + agent assistente proativo.**

- **Notas** são o centro (criar, ler, editar, organizar).
- **Agent** é o assistente que age proativamente: organiza inbox, gera briefs, salva memórias, sem precisar de chat dedicado na v1.
- **Tasks** vivem dentro de notas (sem visão agregada).
- **Telegram** é um canal paralelo (conversa + briefs).

---

## Decisões Macro

| Tema | Decisão |
|---|---|
| **Plataformas** | Android, iOS, Windows |
| **Idioma** | PT-BR (sem i18n na v1) |
| **Auth** | Email + senha. Sem OAuth, sem biometria, sem reset de senha. |
| **Logout** | Manual em Configurações + auto-logout após 30 dias sem uso |
| **Privacidade** | Padrão (HTTPS + Argon2id). Sem E2E, sem app lock |
| **Onboarding** | Nenhum. Vai direto pra home |
| **Tema** | Toggle manual em Configurações (claro / escuro / auto) |
| **Compartilhar notas** | v2 (estilo Superlist: ver/editar + audit log) |
| **Chat dedicado no app** | v2 |
| **Tags** | Deferido |
| **Contexto (pastas)** | Deferido |
| **Arquivamento** | Não tem |
| **Seleção múltipla** | Não tem |
| **Filtros na home** | Sem filtros, ordenado por atualização |

---

## Navegação

**Main shell**: 1 tab só — **Notas**. Sem "Hoje", sem "Chat", sem "Busca" como tabs.

Rotas:
- `/` — Splash
- `/login` — Login
- `/register` — Cadastro
- `/home` — Home (lista de notas, única tab)
- `/notes/:id` — Editor de nota (mobile: tela cheia; Windows: split view)
- `/inbox` — Editor da inbox
- `/search` — Busca (acessada pela lupa na AppBar)
- `/settings` — Configurações
- `/soul` — Editor da SOUL (em Configurações)
- `/routines` — Lista de rotinas (em Configurações)
- `/routines/logs` — Histórico de briefs (em Configurações)
- `/telegram` — Vínculo Telegram (em Configurações)

---

## Home (aba "Notas")

**Estrutura visual:**

```
┌────────────────────────────────────────┐
│ 🔍                  ⋯ (menu)         │   <- AppBar: lupa + menu
├────────────────────────────────────────┤
│ 📥 Inbox (Rascunho)                   │   <- seção fixa, sempre no topo
│    - Card preview                     │
├────────────────────────────────────────┤
│ ⭐ Favoritos                          │   <- só notas com favorite = true
│    - Card preview                     │
├────────────────────────────────────────┤
│ 📝 Notas                              │   <- todas as outras
│    - Card preview                     │
└────────────────────────────────────────┘
                                  [+ Nova]   <- FAB
```

**AppBar:**
- **Lado esquerdo**: lupa (abre `/search`)
- **Lado direito**: menu popup com:
  - Toggle de visualização (lista ↔ cards)
  - "Configurações" (abre `/settings`)

**Visualização:**
- **Lista**: tradicional (título + chip de contexto, sem preview)
- **Cards**: card expandido com preview de conteúdo (estilo Apple Notes). Quando ativa, é a padrão.
- Toggle no menu popup da AppBar

**FAB:**
- Cria nova nota → abre `/notes/:id`
- Aparece sempre na home (mobile + desktop)

**Card da Inbox:**
- Aparece fixo no topo (sempre, mesmo vazio? — ver "estado vazio" abaixo)
- Tap → vai pra `/inbox` (editor em tela cheia)
- Sem distinção visual muito agressiva das outras notas

**Estado vazio (primeiro acesso, sem notas):**
- Empty state genérico: ícone "edit_note" + "Nenhuma nota" + "Toque no botão + para criar sua primeira nota"

**Inbox vazia (clica na inbox, sem conteúdo):**
- Editor pronto, com cursor piscando (comportamento atual)

**Long press numa nota:**
- Bottom sheet com:
  - "Favoritar" / "Desfavoritar"
  - (sem "Mover contexto" — deferido)
  - "Deletar" → **swipe + undo 5s** (NÃO confirmação)

**Filtros e ordenação:**
- Nenhum filtro
- Ordenação: `updated_at DESC` (mais recente primeiro)

---

## Editor de Nota (`/notes/:id`)

**Mobile (Android/iOS):**
- Tela cheia com `SliverAppBar.medium`
- Título editável no topo
- Conteúdo em `super_editor` (markdown)
- Toolbar no rodapé (formatação)
- AppBar actions: `SaveIndicator` + toggle de favorito

**Desktop (Windows):**
- **Split view master-detail**: lista à esquerda (sempre visível), editor à direita
- Selecionar nota na lista atualiza o editor (não empilha)

**Conteúdo:**
- **Markdown** (renderizado por `super_editor`)
- Texto, imagem, vídeo, link (rich inline)
- **Tasks** via `TaskNode` (checkboxes interativos)
- Sem tags, sem contexto (deferidos)
- Sem anexos tipo PDF

**Auto-save:**
- Debounce ~2s
- `SaveIndicator` no AppBar mostra estado (idle / saving / saved)

**Back button (Android):**
- Volta pra `/home`. Auto-save já cuidou.

---

## Inbox (`/inbox`)

- **Rota dedicada**, acessada por tap no card da Inbox na home
- Mesmo editor que nota normal, mas:
  - AppBar com título "Rascunho" (não editável)
  - Sem toggle de favorito
  - Botão "Organizar" no AppBar (só se `hasContent`)
- **Botão "Organizar"**:
  - Abre `InboxOrganizeSheet` (bottom sheet)
  - Agent retorna plano com itens + destinos (new_note, existing_note, keep)
  - Usuário vê switches e pode aceitar/rejeitar cada item
  - Botão "Aplicar N selecionados" aplica apenas os aceitos
  - Comportamento atual mantido

**Após organizar:**
- Snackbar "Rascunho organizado"
- Inbox volta a ficar vazia (conteúdo foi movido/criado notas)

---

## Busca (`/search`)

- Acessada pelo ícone de lupa na AppBar da home
- Tela dedicada com:
  - Search input (debounce)
  - Toggle de modo: FTS / Semântica / Híbrida
  - Resultados em cards (título + excerpt + score)
  - Skeleton loading
- Tap em resultado → abre `/notes/:id`
- Erro: empty state "Erro na busca" + botão "Tentar novamente"
- Online-only (desabilitada offline, mensagem clara)

---

## Configurações (`/settings`)

Tudo centralizado em uma tela, com seções:

**Conta:**
- Email (display, não editável)
- Nome (display, não editável)
- Sair da conta (com confirmação)

**Aparência:**
- Toggle de tema: Claro / Escuro / Automático

**Notificações:**
- Toggle "Receber push" — habilita/desabilita todas

**Avançado:**
- Personalidade do agent (SOUL) → `/soul`
- Rotinas (briefs) → `/routines`
- Telegram → `/telegram`
- Dados (info de última sync)

---

## SOUL (`/soul`)

- Texto livre (markdown)
- Modo Editar ↔ Visualizar (toggle)
- Botão "Restaurar padrão" (com confirmação)
- Botão "Salvar" (com validação: não pode ser vazio)
- Acessado em Configurações → Avançado

---

## Rotinas (Briefs) (`/routines`)

- Lista de rotinas (Daily, Weekly) com toggles e seletores de dia/horário
- Botão "Testar" pra cada rotina (dry-run, mostra o brief gerado sem salvar)
- Botão "Ver histórico" → `/routines/logs`

**Histórico de briefs (`/routines/logs`):**
- Lista de `routine_logs` (data + tipo)
- Tap num log → mostra o brief completo (markdown renderizado)

**Push:**
- "Novo brief disponível" quando o runner gera um novo brief
- Tap na push → abre o brief no app

**Conteúdo do brief:**
- Texto livre (agent decide o que incluir)
- Sem estrutura fixa

---

## Telegram (`/telegram`)

- Tela com status do vínculo
- Se desvinculado: botão "Gerar código" → mostra código de 6 dígitos + instruções pra `/start CODIGO` no bot
- Se vinculado: mostra `@username` + `chat_id` + botão "Desconectar" (com confirmação)
- Acessado em Configurações → Avançado

**Comportamento do bot:**
- Texto livre enviado pelo Telegram → agent responde (via SSE simulado com edits de mensagem)
- Briefs também enviados pelo Telegram quando vinculado

---

## Agent (proativo)

**Ações automáticas:**

1. **Organizar inbox** (sob demanda): quando usuário toca em "Organizar"
2. **Briefs diários/semanais** (via cron): runner no backend gera e salva
3. **Memórias** (transparente): agent cria/apaga memórias de longo prazo automaticamente

**Sem UI dedicada:**
- Memórias: transparentes (sem tela de gerenciamento)
- Chat: v2
- Activity log: v2

**Notificações in-app:** nenhuma por enquanto. Resultado aparece quando o usuário volta pro app.

**Push:**
- "Novo brief disponível"
- "Lembrete de task próxima do vencimento"
- "Insight do agent" (sugestão de organização, etc.)

---

## Tasks

- **Só dentro de notas** (via `TaskNode` no `super_editor`)
- Sem tela agregada (sem "Hoje", sem "Esta semana")
- Sem visão global de pendentes
- Cada task tem: texto + checked/unchecked
- Recorrência, due_date, etc. — deferidos

---

## Sincronização

- **Local-first**: Drift (SQLite) é a fonte primária
- **Sync silencioso**: roda em background (ao abrir, ao reconectar, periodicamente)
- **Offline total**: ler e criar/editar funciona offline. Banner "Offline" no topo
- **Erros**: silenciosos (retry automático, sem snackbar pro usuário)

---

## Multi-dispositivo

- Login em vários dispositivos funciona
- Conflitos: **last-write-wins** (server timestamp) — sem UI de resolução
- Auto-logout após 30d sem uso em qualquer dispositivo

---

## Comportamentos globais

- **Back button (Android)**: volta pra home. Auto-save já salvou
- **Toggle de tema**: claro / escuro / automático
- **Logout**: manual em Configurações + auto após 30d
- **Empty states**: genéricos, com instrução de como proceder
- **Loading states**: CircularProgressIndicator centralizado
- **Error states**: AppErrorView com retry

---

## O que NÃO está na v1

- ❌ Chat dedicado no app
- ❌ Compartilhamento de notas
- ❌ Tags
- ❌ Contexto / pastas
- ❌ Recorrência e due_date em tasks
- ❌ Visão agregada de tasks
- ❌ Notificações in-app (snackbars)
- ❌ Onboarding visual
- ❌ Reset de senha
- ❌ OAuth (Google / Apple)
- ❌ Biometria / app lock
- ❌ E2E encryption
- ❌ Arquivamento
- ❌ Seleção múltipla
- ❌ Filtros na home
- ❌ Outras abas (Hoje, Chat, Busca como tab)
- ❌ i18n (só PT-BR)
- ❌ macOS / Linux / Web

---

## Referências

- [agents.md](agents.md) — convenções do projeto
- [ROADMAP.md](ROADMAP.md) — features do backend
- [implementation_plan.md](implementation_plan.md) — refatoração técnico
