# 03 — Sessão persistente de formatação

**What to build:** manter a toolbar de formatação aberta durante várias ações e mudanças de seleção, permitindo formatar diferentes trechos sem reabrir o modo.

**Blocked by:** 01 — Alternância entre toolbar compacta e toolbar de formatação; 02 — Comandos de formatação e estados ativos.

**Status:** ready-for-agent

- [ ] A toolbar permanece no modo de formatação depois de aplicar qualquer comando.
- [ ] Selecionar outro trecho atualiza os estados ativos sem fechar a toolbar.
- [ ] Cada comando usa a seleção mais recente e válida do editor.
- [ ] A seleção não é perdida quando o usuário toca em um controle da toolbar.
- [ ] Tocar em `X` retorna à toolbar compacta.
- [ ] `Escape` retorna à toolbar compacta.
- [ ] Tocar fora da toolbar retorna à toolbar compacta.
- [ ] O foco retorna ao editor depois de fechar ou concluir uma ação, conforme o comportamento atual.
- [ ] Mudanças rápidas de seleção não deixam um estado visual obsoleto ativo.
