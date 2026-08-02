# 04 — Validação integrada da toolbar

**What to build:** Validar a linguagem de motion completa da toolbar no editor, incluindo seleção de texto, estados de lista, pop-up, desktop, foco, acessibilidade e reduced motion.

**Blocked by:** 02 — Transição do ícone de lista; 03 — Motion do estado selecionado no pop-up.

**Status:** ready-for-agent

- [ ] A toolbar exibe o motion consistente em mobile e desktop.
- [ ] A entrada e saída das ações de seleção não deslocam o restante da toolbar de forma inesperada.
- [ ] O botão de lista e o pop-up permanecem alinhados ao trigger.
- [ ] A navegação por teclado, Escape, clique fora e retorno de foco continuam funcionando.
- [ ] Os testes comportamentais da toolbar passam sem asserções sobre implementação interna.
- [ ] Os testes relacionados do editor passam.
- [ ] `flutter analyze` não apresenta problemas introduzidos pelos tickets.
