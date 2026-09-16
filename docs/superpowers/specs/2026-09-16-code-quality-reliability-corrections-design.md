# Code quality and reliability corrections design

**Date:** 2026-09-16  
**Status:** approved for implementation  
**Scope:** findings from the layered Luna audit and the subsequent code-level
review

## Intent

Corrigir os problemas concretos encontrados na auditoria, incluindo bugs,
contratos frágeis, estados silenciosos e fronteiras ruins entre UI, aplicação,
domínio, persistência e transporte. A implementação deve reduzir complexidade
sem criar uma nova camada de abstrações apenas para deslocar o problema.

Cada correção deve preservar os invariantes de ownership já documentados:
`TaskNode` continua sendo propriedade do documento REST/OT e `Task` continua
sendo propriedade da tabela/outbox de tasks independentes.

## Principles

- Corrigir primeiro segurança, perda de dados e contratos incompatíveis.
- Preferir apagar callbacks opcionais, flags duplicadas, wrappers finos e
  caminhos mortos.
- Manter handlers finos e mover regras para funções/objetos tipados que possam
  ser testados sem Flutter ou HTTP.
- Não engolir erros: estados parciais devem resultar em erro tipado, retry
  durável ou quarentena explícita.
- Uma fila/serviço deve ter um único dono da ordenação e da transação.
- Nenhum agente deve resetar, fazer checkout ou sobrescrever mudanças não
  relacionadas já presentes no worktree.
- Não alterar comportamento visual como parte desta rodada; testes visuais
  existentes não serão expandidos.

## Corrections by boundary

### Runtime, security and HTTP contracts

- Remover ou proteger o endpoint público de debug de goroutines.
- Fazer configuração insegura falhar fechado quando `ENVIRONMENT` ou segredos
  obrigatórios estiverem ausentes; manter defaults de desenvolvimento apenas
  quando o modo de desenvolvimento estiver explícito.
- Validar assinatura/certificado/timestamp/request ID no endpoint Alexa antes
  de aceitar uma requisição, e tornar a operação idempotente.
- Tipar respostas de upload e propagar falhas de storage/API.
- Validar cursor/limit inválidos em endpoints HTTP em vez de ignorá-los.

### Attachments and lifecycle

- Definir o contrato único do upload entre Flutter e Go, incluindo o campo URL
  e códigos de erro.
- Garantir que falha de upload não pareça sucesso e que o estado local seja
  recuperável.
- Fazer remoção/GC de anexos respeitar delete de nota, falhas intermediárias e
  retries idempotentes, sem apagar objeto ainda referenciado.

### Notes, editor and document model

- Manter `EditorOperationCapture` responsável por ouvir o editor e delegar a
  construção pura de diffs/ops a um componente tipado.
- Transformar `NoteEditorController` em executor de comandos; cálculo de
  recorrência/completion e parsing de metadata ficam fora do controller.
- Remover upload opcional silencioso e tornar a capacidade explícita.
- Reavaliar o split artificial do codec: ou manter o codec coeso, ou extrair
  fronteiras reais de snapshot/node/delta.
- Remover dependência da camada de dados em presentation e consolidar tipos de
  auth duplicados.

### Sync and persistence

- Separar protocolo, reconciliação OT, projeção e persistência atômica no sync.
- Propagar/quarentenar falhas de projeção; nunca aceitar sucesso parcial com
  `catch (_) {}`.
- Definir um único proprietário da ordenação por nota entre sessão e outbox.
- Remover callbacks/flags opcionais do coordinator e separar aplicadores de
  notas e tasks.
- Validar reuso de operation ID com payload diferente.
- Usar operações SQL set-based quando a DAO já está dentro de transação.
- Consolidar resolução de sessão e eliminar duplicação do contrato de auth.

### Independent tasks and recurrence

- Separar parsing HTTP, transição de domínio e persistência no service de
  tasks, preservando o contrato existente.
- Centralizar semântica de recurrence/reminder e distinguir âncora da série da
  ocorrência visível.
- Definir explicitamente o caso sem data de vencimento.
- Expor estado bloqueado/diagnóstico de sync em vez de esconder a causa.
- Remover estado de request duplicado em controllers Riverpod e fazer a sheet
  retornar draft; o owner persiste e trata permissões.

### MCP, sharing and integrations

- MCP começa em modo somente leitura; mutações destrutivas exigem confirmação
  atômica, recuperável e idempotente.
- Corrigir `reopen` para escolher a operação correta, substituir parsing
  genérico por requests tipados e validar enumerações.
- Reduzir escopo de descoberta de ferramentas e remover/limitar `update_note`.
- Redigir URLs/token/sensitive data em logs.

### Presentation and code hygiene

- Alinhar desvios de componentes compartilhados onde isso não muda comportamento
  visual intencional.
- Remover APIs mortas, callbacks sem consumidores e helpers duplicados.
- Reduzir métodos privados que apenas montam trechos simples e extrair apenas
  componentes que realmente tenham responsabilidade reutilizável.
- Atualizar a documentação normativa que contradiz o ownership atual.

## Delegation and sequencing

Os agentes Luna high trabalham no mesmo checkout, sem threads/worktrees, com
escopos de escrita disjuntos. Agentes que dependem de uma mudança de contrato
aguardam o lote correspondente. O Sol low só roda depois que todos os agentes
terminarem e os testes locais forem executados.

1. Backend runtime/security, attachments, MCP/integrations e domínio Go em
   paralelo, sem compartilhar arquivos de entrada.
2. Flutter auth, editor/attachments, tasks e sync em paralelo, também com
   ownership de arquivos explícito.
3. Integração local: revisar diffs, resolver conflitos de contrato, regenerar
   código somente quando necessário e executar testes focados.
4. Sol low valida cada correção contra a evidência original e procura
   regressões, simplificações incompletas e novas duplicações.
5. Corrigir os achados do Sol e executar a verificação final.

## Verification

- `git diff --check` após a integração.
- `go test ./...` e `go vet ./...` para mudanças Go.
- `flutter analyze --no-pub` no conjunto afetado.
- Testes Flutter focados por lote; sem criar testes que validem layout visual.
- Testes de contrato/segurança/rollback/idempotência para as mudanças de
  fronteira.
- Se a máquina não suportar algum gate, registrar o bloqueio com o comando e o
  motivo exatos; não declarar a revisão completa sem evidência.
