# 02 — Transição do ícone de lista

**What to build:** O botão de lista reage quando o bloco atual muda entre bullet list, numbered list e checklist. A troca do ícone usa uma transição spring perceptual, sem alterar os comandos do editor.

**Blocked by:** 01 — Motion spring para ações de seleção.

**Status:** ready-for-agent

- [ ] O botão mostra o ícone correspondente ao estado atual do editor.
- [ ] A troca entre os três estados não ocorre como uma substituição brusca.
- [ ] A transição mantém o tamanho, a área de toque, a semântica e o estado ativo atuais.
- [ ] Mudanças rápidas de seleção terminam no estado mais recente.
- [ ] Reduced motion mantém a troca correta com transição reduzida ou imediata.
- [ ] Os testes verificam os três estados e a mudança entre eles.
