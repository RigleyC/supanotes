# 03 — Coordenador único de persistência e sincronização por nota

**What to build:** Cada nota deve ter uma única fronteira serializada para captura local, persistência, projeção, rebase, polling e encerramento. O flush local obrigatório deve ser independente da tentativa de sincronização pela rede.

**Blocked by:** 01 — Persistência atômica da nota local; 02 — Escopo local por conta e compartilhamento.

**Status:** ready-for-agent

- [ ] Uma edição feita durante debounce, escrita lenta, resposta remota ou rebase nunca é descartada.
- [ ] O rebase aplica o snapshot canônico sem apagar uma edição local capturada na mesma janela.
- [ ] Fechar a nota persiste a edição local sem esperar uma requisição de rede lenta.
- [ ] A tentativa de sincronização no encerramento é cancelável ou de melhor esforço e não bloqueia a durabilidade local.
- [ ] Operações pendentes e operações em voo retomam após reinício com os mesmos identificadores.
- [ ] Existe um único owner para polling, projeção e fechamento de cada nota.
- [ ] Testes cobrem corrida de edição/rebase, fechamento durante timeout, reinício e abertura duplicada.
