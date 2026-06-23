# SupaNotes — Relatório de Auditoria do Código (Frontend & Backend)

Este documento consolida as descobertas obtidas através da auditoria em paralelo realizada no frontend (Flutter) e backend (Go). As análises focaram em conformidade com as diretrizes do `agents.md` e `RIVERPOD.md`, vazamentos de memória, erros em tempo de execução/compilação, SOLID, duplicação e performance.

---

## 🔍 Resumo Executivo das Principais Falhas

1. **Erro Crítico de Compilação (Backend)**: O backend atualmente **não compila** devido a referências a campos removidos no semeador de dados de usuários (`auth/service.go`).
2. **Vazamento de Memória e Conexões (Backend)**: Conexões SSE no chat de IA não liberam recursos (goroutines/banco de dados) se o cliente desconectar abruptamente.
3. **Falha Crítica de Desempenho e Integridade de Dados (Backend)**: A tabela `note_links` está com a chave primária composta ausente e sem índices adequados nas chaves estrangeiras, gerando scans completos da tabela e permitindo duplicatas.
4. **Desconformidade Geral das Telas (Frontend)**: Praticamente **todas** as telas da aplicação violam a estrutura visual básica exigida no `agents.md` (uso de `CustomScrollView` + `SliverAppBar.medium` + `SliverList`).
5. **Uso de Componentes Banidos (Frontend)**: Frequente utilização de botões nativos do Flutter (`ElevatedButton`, `TextButton`, `FilledButton`) ao invés do componente global unificado `AppButton`.
6. **Vazamento de Sincronização (Frontend)**: O editor de notas (`note_editor.dart`) ignora atualizações recebidas via sync de banco enquanto está aberto.

---

## 🛠️ Detalhes da Auditoria: Backend (Go)

### [CORRECTNESS-01] Bug Crítico de Compilação no Semeador de Usuário Padrão
- **Evidência**: [service.go:L289-L296](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/auth/service.go#L289-L296)
- **Impacto**: **Bloqueia compilação do servidor.** A inicialização da struct `sqlcgen.CreateNoteParams` tenta definir os campos `Favorite` e `Archived`. Contudo, a struct gerada em [notes.sql.go:L141-L148](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/db/sqlcgen/notes.sql.go#L141-L148) não contém mais estes atributos (eles foram movidos para a tabela `user_note_preferences` nas migrações). Como resultado, todo o fluxo de registro e testes está quebrado.
- **Esboço de Correção**: Remover as chaves `Favorite: false` e `Archived: false` da struct literal em `seedUserDefaults`.
- **Esforço**: P (minutos) | **Risco**: BAIXO

### [PERFORMANCE-02] Vazamento de Goroutines e Conexões de Banco de Dados no SSE Chat
- **Evidência**: [handler.go:L116-L123](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/agent/handler.go#L116-L123) (SSE reader) & [loop.go:L40-L44](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/agent/loop.go#L40-L44) (SSE writer)
- **Impacto**: Exaustão do pool de conexões do banco de dados e vazamento de memória. Quando o cliente desconecta no meio do stream do chat, o handler HTTP termina, mas a goroutine em background (`doChat`) continua gerando respostas da LLM. Ao preencher o canal com buffer (`events`), a escrita bloqueia para sempre. A goroutine nunca morre, mantendo a conexão com o banco aberta.
- **Esboço de Correção**: Passar o contexto da requisição até os métodos de envio de eventos (`sendEvent`/`sendStreamEvent`) e usar um bloco `select` para garantir a saída imediata quando o contexto for cancelado:
  ```go
  select {
  case events <- event:
  case <-ctx.Done():
      return
  }
  ```
- **Esforço**: M (algumas horas) | **Risco**: MÉDIO

### [CORRECTNESS-03] Crash de Execução no Banco de Dados na Limpeza Diária (Hard Delete)
- **Evidência**: [repository.go:L126](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/routines/repository.go#L126) & [sync.sql:L27-L30](file:///c:/Users/rigleyc/projects/supanotes/backend/db/queries/sync.sql#L27-L30)
- **Impacto**: O cron job diário de manutenção (`HardDeleteExpired`) falha constantemente. A query `HardDeleteExpiredContexts` tenta ler a coluna `deleted_at` na tabela `contexts`. Porém, conforme a migração [000002_notes.up.sql:L3-L11](file:///c:/Users/rigleyc/projects/supanotes/backend/db/migrations/000002_notes.up.sql#L3-L11), a tabela `contexts` **não possui** a coluna `deleted_at`.
- **Esboço de Correção**: Adicionar `deleted_at TIMESTAMPTZ` na tabela `contexts` através de uma nova migração ou remover a limpeza se não houver soft delete nessa tabela.
- **Esforço**: P (minutos) | **Risco**: BAIXO

### [PERFORMANCE-04] Perda de Desempenho e Integridade Visual em Note Links
- **Evidência**: [000011_scope_gaps.up.sql:L78-L90](file:///c:/Users/rigleyc/projects/supanotes/backend/db/migrations/000011_scope_gaps.up.sql#L78-L90)
- **Impacto**: Queda na performance de busca de conexões entre notas e risco de dados inconsistentes (links duplicados). A migração removeu a chave primária composta `(source_id, target_id)` para criar uma coluna `id`, mas não inseriu nenhum índice secundário ou restrição de unicidade correspondente em `source_id`.
- **Esboço de Correção**: Criar uma migração adicionando a constraint `UNIQUE (source_id, target_id)`, gerando implicitamente o índice necessário.
- **Esforço**: P (1 hora) | **Risco**: BAIXO

### [CORRECTNESS-05] Runner de Rotinas Ignora Edições de Cron e Timezone
- **Evidência**: [runner.go:L135-L137](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/routines/runner.go#L135-L137)
- **Impacto**: Mudanças feitas pelo usuário na recorrência de relatórios diários/semanais são salvas no banco de dados, mas ignoradas em tempo de execução até que o servidor backend seja totalmente reiniciado.
- **Esboço de Correção**: Manter o estado do cron na struct do `Runner` e, ao recarregar, verificar se a expressão do banco difere da em execução. Se sim, atualizar o job no scheduler.
- **Esforço**: M | **Risco**: MÉDIO

### [CORRECTNESS-06] Crash de Sintaxe SQL com Busca Vazia (Apenas caracteres especiais)
- **Evidência**: [service.go:L80-L93](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/search/service.go#L80-L93) & [search.sql:L36](file:///c:/Users/rigleyc/projects/supanotes/backend/db/queries/search.sql#L36)
- **Impacto**: Se o usuário pesquisar algo contendo apenas pontuação (ex: `?!`), `toPrefixTsQuery` retorna `""`. A query repassada ao Postgres (`to_tsquery('')`) falha com erro de sintaxe, resultando em erro HTTP 500 para o aplicativo.
- **Esboço de Correção**: Adicionar uma validação no `search/service.go` retornando uma lista vazia de resultados sem consultar o banco se a query formatada for vazia.
- **Esforço**: P | **Risco**: BAIXO

### [TECH-DEBT-07] Prompt LLM Duplicado e Violação de SOLID (Fat Handler)
- **Evidência**: [handler.go:L292-L326](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/notes/handler.go#L292-L326) vs [notes_tools.go:L356-L375](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/agent/tools/notes_tools.go#L356-L375)
- **Impacto**: Duplicação exata da lógica de orquestração do LLM para organização da caixa de entrada. Além disso, o handler HTTP realiza chamadas diretas de LLM e parsing de string, violando a regra de conter apenas lógica fina de transporte HTTP.
- **Esboço de Correção**: Centralizar a lógica de organização do inbox e chamada da LLM em `notes/service.go`, delegando a ela tanto a API quanto a ferramenta do agente.
- **Esforço**: M | **Risco**: BAIXO

### [PERFORMANCE-08] Índices Redundantes no Banco de Dados
- **Evidência**: [000009_polish.up.sql:L12-L14](file:///c:/Users/rigleyc/projects/supanotes/backend/db/migrations/000009_polish.up.sql#L12-L14)
- **Impacto**: Desperdício de armazenamento e degradação nas escritas no Postgres. `notes_active_idx` sobre `notes(user_id, updated_at DESC) WHERE deleted_at IS NULL` é redundante com `idx_notes_user_updated`. Similarmente, `tasks_user_due_idx` duplica a funcionalidade de `tasks_user_open_idx`.
- **Esboço de Correção**: Remover índices redundantes em uma nova migração.
- **Esforço**: P | **Risco**: BAIXO

### [SECURITY-09] Vazamento de Informações Internas em Erros 500
- **Evidência**: [notes/handler.go:L423](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/notes/handler.go#L423) e outros handlers.
- **Impacto**: O backend responde para o cliente com `err.Error()` em erros 500, o que pode vazar schemas de banco de dados, nomes de colunas, IPs internos ou dados de credenciais em produção.
- **Esboço de Correção**: Retornar mensagens genéricas em erros de servidor (ex: `{"error": "Internal server error"}`), enquanto se registra o erro original via log estruturado (`slog`).
- **Esforço**: P | **Risco**: BAIXO

---

## 🎨 Detalhes da Auditoria: Frontend (Flutter)

### 1. Desconformidade Visual de Telas (`agents.md`)
O projeto exige que todas as telas usem um layout baseado em `CustomScrollView` + `SliverAppBar.medium` + `SliverList`. Diversas telas violam essa convenção usando `Scaffold.appBar` padrão com listas aninhadas simples:
* [memories_screen.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/memories/presentation/memories_screen.dart#L28-L29)
* [inbox_screen.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/inbox_screen.dart#L109-L112)
* [note_editor_screen.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/note_editor_screen.dart#L92-L95)
* [notes_list_screen.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/notes_list_screen.dart#L112-L114) (Usa `AppBar` padrão).
* [routines_screen.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/routines/presentation/routines_screen.dart#L22-L24)
* [brief_history_screen.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/routines/presentation/brief_history_screen.dart#L22-L24)
* [telegram_link_screen.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/telegram/presentation/telegram_link_screen.dart#L46-L47)
* [contexts_screen.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/settings/presentation/contexts_screen.dart#L39-L40)
* [soul_editor_screen.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/settings/presentation/soul_editor_screen.dart#L126-L128)

*Além disso:* Em [soul_editor_screen.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/settings/presentation/soul_editor_screen.dart#L239-L259), ações do rodapé são renderizadas no corpo do formulário ao invés de usar o slot `Scaffold.bottomNavigationBar`.

### 2. Violação de Convenção do Riverpod
* **Falta de `.autoDispose`**:
  * [contexts_controller.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/settings/presentation/controllers/contexts_controller.dart#L6): `contextsProvider` é declarado como `FutureProvider` sem `autoDispose`. Como os contextos só são usados nas configurações, manter isso em memória indefinidamente gera vazamentos.
* **Checagem manual de estado de `AsyncValue`**:
  * [inbox_screen.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/inbox_screen.dart#L87-L99): Faz checagens do tipo `if (asyncValue.isLoading)` manuais ao invés de usar a sintaxe obrigatória `.when(data:loading:error:)`.
  * [note_editor_screen.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/note_editor_screen.dart#L71-L86): Desempacota o valor da nota usando `.asData?.value` diretamente em meio ao `build()`.
* **Utilização de Flags de Estado de Requisição Locais (`setState`)**:
  * O projeto proíbe o uso de booleanos locais como `_isLoading` ou `_isSaving` para requisições de rede. No entanto, são amplamente usados:
    * `_isSaving` em [soul_editor_screen.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/settings/presentation/soul_editor_screen.dart#L72)
    * `_waitingForLink` em [telegram_link_screen.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/telegram/presentation/telegram_link_screen.dart#L23)
    * `_submitting` em [new_context_sheet.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/settings/presentation/widgets/new_context_sheet.dart#L18)
    * `_saving` em [task_edit_sheet.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/tasks/presentation/widgets/task_edit_sheet.dart#L71)

### 3. Componentes Banidos e Falta de Uso de Componentes Globais
* **Botões Nativos**: O `agents.md` proíbe o uso direto de `ElevatedButton`, `TextButton`, `FilledButton` ou `OutlinedButton`, exigindo o uso de `AppButton`. Há violações nos arquivos:
  * `TextButton` em: [settings_screen.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/settings/presentation/settings_screen.dart#L170), [inbox_organize_sheet.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/widgets/inbox_organize_sheet.dart#L277), [task_edit_sheet.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/tasks/presentation/widgets/task_edit_sheet.dart#L161).
  * `OutlinedButton` em: [new_context_sheet.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/settings/presentation/widgets/new_context_sheet.dart#L94), [telegram_code_card.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/telegram/presentation/widgets/telegram_code_card.dart#L66).
  * `FilledButton` em: [routines_screen.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/routines/presentation/routines_screen.dart#L95), [brief_schedule_card.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/routines/presentation/widgets/brief_schedule_card.dart#L157), [new_context_sheet.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/settings/presentation/widgets/new_context_sheet.dart#L103).
  * *Melhoria*: O componente `AppButton` atual não suporta ícones ou botões puramente textuais. Deve ser estendido com suporte a `icon` e nova variante `AppButtonVariant.text`.
* **Falta de Uso do `showConfirmDialog`**:
  * [memories_screen.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/memories/presentation/memories_screen.dart#L50-L52) deleta memórias imediatamente ao toque, sem dialog de confirmação.
* **Uso de Dialogs Locais ao invés dos Globais**:
  * [task_edit_sheet.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/tasks/presentation/widgets/task_edit_sheet.dart#L151-L171) usa `showDialog` + `AlertDialog` inline ao invés de delegar ao `showConfirmDialog`.
  * [settings_screen.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/settings/presentation/settings_screen.dart#L164-L176) usa `showDialog` com builder local.
  * [share_note_dialog.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/widgets/share_note_dialog.dart#L22-L27) usa `showDialog` no método estático de exibição.
* **Uso de BottomSheet inline**:
  * [brief_schedule_card.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/routines/presentation/widgets/brief_schedule_card.dart#L240-L287) usa `showModalBottomSheet` inline ao invés do helper global `showAppBottomSheet`.

### 4. Métodos Auxiliares Privados de UI (`_buildBody`, `_buildHeader`)
O `agents.md` condena a quebra de layouts em métodos privados do widget (ex: `Widget _buildBody()`). A recomendação é construir tudo inline no `build` ou extrair em classes `StatelessWidget` separadas (ex: `class _FooWidget extends StatelessWidget`). Ocorrem violações graves em:
* [soul_editor_screen.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/settings/presentation/soul_editor_screen.dart#L143-L259): Contém `_buildBody`, `_modeBanner`, `_editor`, `_preview`, `_footerActions`.
* [notes_list_screen.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/notes_list_screen.dart#L197-L220): Contém `_buildNotesBody`.
* [inbox_organize_sheet.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/widgets/inbox_organize_sheet.dart#L191-L289): Contém `_buildBody`, `_buildPlanItems`, `_buildFooter`.
* [agent_chat_view.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/agent/presentation/widgets/agent_chat_view.dart#L368-L409): Contém `_buildActionTimelineCard`, `_buildEmptyStateList`, `_buildEmptyStateItem`.

### 5. Duplicação de Componentes (Snackbars)
* **Duplicação**: O arquivo `error_snackbar.dart` (`showErrorSnackBar`) realiza exatamente a mesma função que `AppMessenger.showError` em `app_snackbar.dart`, porém de forma procedural. O widget `brief_schedule_card.dart` usa o primeiro, enquanto o restante do app usa o segundo.
* *Melhoria*: Mesclar a opção de `onRetry` para `AppMessenger.showError` e deletar `error_snackbar.dart`.

### 6. Violacões Gerais de Lógica de Negócios / UX
* **Visual Mode Toggle Banido**:
  * [soul_editor_screen.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/settings/presentation/soul_editor_screen.dart#L135) possui um toggle de tela para visualização vs edição. O `agents.md` explicitamente proíbe esse tipo de visualização em separado: *"PROIBIDO: modo visualização/edição. Telas devem usar apenas modo edição."*
* **Vazamento de Sincronização Local (Editor)**:
  * [note_editor.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/widgets/note_editor.dart#L112): No método `didUpdateWidget`, o editor simplesmente ignora a mudança do parâmetro `widget.content`. Se o sync receber novidades do servidor em segundo plano e atualizar a base local, o editor permanecerá travado no estado desatualizado em tela.

---

## 📋 Ordem Recomendada de Implementação

Se você desejar que eu implemente as correções, recomendo dividir o trabalho da seguinte forma:

### Fase 1: Correções Críticas (Backend & Compilação)
1. **[CORRECTNESS-01]** Corrigir semeador de notas no backend para destravar compilação local.
2. **[CORRECTNESS-03]** Corrigir coluna inexistente na query `HardDeleteExpiredContexts`.
3. **[PERFORMANCE-02]** Corrigir vazamento de goroutines e conexões em SSE.

### Fase 2: Banco de Dados & Concorrência (Backend)
1. **[PERFORMANCE-04]** Adicionar constraint de unicidade e índice em `note_links`.
2. **[CORRECTNESS-06]** Tratar query de busca vazia no serviço de busca.
3. **[PERFORMANCE-08]** Remover índices redundantes no Postgres.
4. **[CORRECTNESS-05]** Atualizar cron de rotinas dinamicamente ao editar horários.

### Fase 3: Refatoração de Código Comum e SOLID (Frontend & Backend)
1. **[TECH-DEBT-07]** Desduplicar prompts de inbox e mover para camada de serviço.
2. **[SECURITY-09]** Ocultar erros internos do backend em respostas HTTP.
3. **Frontend**: Unificar `error_snackbar.dart` e `app_snackbar.dart` em `AppMessenger`.
4. **Frontend**: Estender `AppButton` para aceitar ícones e tipo texto, removendo botões nativos.

### Fase 4: Adequação Visual das Telas e Riverpod (Frontend)
1. Ajustar layouts das telas que violam a estrutura `Scaffold` + `CustomScrollView` + `SliverList`.
2. Remover métodos privados `_build...` e criar subclasses privadas de `StatelessWidget`.
3. Resolver conformidades do Riverpod (`AsyncValue.when` e remoção de flags booleanas de requisição).
