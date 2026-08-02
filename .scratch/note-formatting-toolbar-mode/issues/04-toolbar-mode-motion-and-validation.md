# 04 — Motion e validação do modo de formatação

**What to build:** finalizar a experiência da troca entre as duas toolbars com motion consistente, acessibilidade e validação comportamental em mobile e desktop.

**Blocked by:** 01 — Alternância entre toolbar compacta e toolbar de formatação; 02 — Comandos de formatação e estados ativos; 03 — Sessão persistente de formatação.

**Status:** ready-for-agent

- [ ] A troca entre toolbar compacta e toolbar de formatação usa os tokens de spring existentes e mantém a superfície glass.
- [ ] O `motor` anima a mudança de tamanho, ícones, opacidade, escala e estados ativos sem criar um framework novo.
- [ ] `MediaQuery.disableAnimations` reduz ou remove as transições.
- [ ] O layout não apresenta overflow em larguras mobile ou desktop.
- [ ] Os testes verificam os estados visíveis, comandos, seleção, foco, `X`, `Escape` e toque fora.
- [ ] Os testes não dependem de valores internos de controllers, física exata ou contagem de frames.
- [ ] Os testes focados da toolbar, os testes relacionados do editor e o analyze passam.
