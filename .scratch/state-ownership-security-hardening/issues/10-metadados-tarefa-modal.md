# 10 — Vincular metadados de tarefa ao ciclo do modal

**What to build:** Tratar os metadados em edição como estado efêmero do modal, com confirmação explícita, cancelamento real e descarte garantido.

**Blocked by:** None — can start immediately.

**Status:** done

- [x] O formulário inicia com os dados atuais da tarefa ao abrir.
- [x] Cancelar ou dispensar o modal não persiste alterações.
- [x] Confirmar inicia a persistência uma única vez.
- [x] O modal fecha somente após sucesso.
- [x] Falha mantém os valores e mostra erro recuperável.
- [x] O estado é descartado ao fechar por qualquer caminho.
- [x] Uma falha no pedido de permissão de notificação não mantém o provider do formulário vivo.
- [x] Duas tarefas abertas em fluxos coexistentes não compartilham estado.
- [x] Abrir e fechar muitas tarefas não acumula famílias de provider.
- [x] Testes cobrem confirmar, cancelar, falhar, tentar novamente e descarte.
