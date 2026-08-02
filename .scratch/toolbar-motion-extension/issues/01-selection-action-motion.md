# 01 — Motion spring para ações de seleção

**What to build:** As ações Bold, Italic e Strike da toolbar entram e saem com movimento spring quando o usuário seleciona ou limpa um trecho de texto. O grupo mantém o crescimento estrutural atual e os botões usam um motion compartilhado.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] A seleção não vazia exibe as ações inline com entrada suave.
- [ ] Limpar a seleção remove as ações sem corte visual abrupto.
- [ ] O estado ativo de Bold, Italic e Strike anima cor, fundo e escala de forma coordenada.
- [ ] A interação continua disponível durante a transição.
- [ ] Reduced motion desativa ou reduz a animação sem remover as ações.
- [ ] Os testes verificam comportamento visível, sem depender de valores internos do controller.
