# 03 — Motion do estado selecionado no pop-up

**What to build:** O pop-up de listas anima o checkmark e o estado ativo das opções quando o usuário escolhe Bullet List, Numbered List ou Checklist. A seleção do editor, o fechamento e o retorno de foco continuam funcionando.

**Blocked by:** 01 — Motion spring para ações de seleção.

**Status:** ready-for-agent

- [ ] A opção ativa apresenta checkmark com entrada spring curta.
- [ ] A troca de opção atualiza o checkmark sem deixar dois estados ativos.
- [ ] Selecionar uma opção preserva a seleção correta do editor.
- [ ] O pop-up fecha e devolve o foco ao editor após a seleção.
- [ ] Clique fora e Escape continuam fechando o pop-up durante a animação.
- [ ] Reduced motion não bloqueia seleção, fechamento ou foco.
- [ ] Os testes verificam os estados ativo e inativo das três opções.
