# 03 — Caracterizar o ciclo de vida atual da sessão de nota

**What to build:** Criar uma rede de segurança que descreva o comportamento observável de abrir, editar, sincronizar, fechar e reabrir uma nota antes da mudança de ownership.

**Blocked by:** None — can start immediately.

**Status:** done

- [x] Abrir uma nota cria um documento visível a partir do snapshot e da outbox.
- [x] Editar persiste operações locais antes de depender da rede.
- [x] Fechar durante o debounce preserva as operações confirmadas na interface.
- [x] Reabrir durante um fechamento em andamento identifica qualquer trabalho da sessão anterior.
- [x] Falhas em cada etapa da abertura demonstram quais recursos precisam de cleanup.
- [x] Logout durante abertura, sincronização e fechamento não deixa trabalho associado ao usuário anterior.
- [x] Duas notas podem progredir sem bloquear uma à outra.
- [x] Duas tentativas concorrentes na mesma nota expõem o comportamento atual da serialização.
- [x] Os testes usam Drift em memória para snapshot, outbox e sessão persistida.
- [x] Este ticket não altera a arquitetura nem corrige os comportamentos caracterizados.
