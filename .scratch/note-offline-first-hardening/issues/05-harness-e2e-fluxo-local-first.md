# 05 — Harness E2E do fluxo local-first

**What to build:** Criar um teste de ponta a ponta que use o app real, a rota real da nota, o banco local real e um servidor HTTP controlável. O teste deve provar que a tela abre do local sem esperar a rede e que uma edição offline sobrevive ao reinício.

**Blocked by:** 01 — Persistência atômica da nota local; 03 — Coordenador único de persistência e sincronização por nota.

**Status:** ready-for-agent

- [ ] O teste monta o app autenticado e abre a tela real da nota.
- [ ] Com snapshot local e HTTP lento, o conteúdo aparece antes da resposta remota.
- [ ] A tela não depende de um fetch remoto para exibir conteúdo já confirmado localmente.
- [ ] Uma edição offline aparece imediatamente no editor e é gravada na outbox.
- [ ] Fechar e recriar a sessão usando o mesmo banco restaura conteúdo e operação pendente.
- [ ] Ao reconectar, a operação é aceita uma vez e a outbox é esvaziada.
- [ ] O teste não instancia diretamente o adapter para representar a experiência principal do usuário.
