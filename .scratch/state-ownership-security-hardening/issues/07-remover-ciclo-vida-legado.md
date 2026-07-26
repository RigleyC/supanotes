# 07 — Contrair e remover o ciclo de vida legado

**What to build:** Remover os mecanismos antigos depois que todos os consumidores usam a fachada de sessão, deixando uma única autoridade de ownership.

**Blocked by:** 06 — Migrar o editor para a fachada da sessão de nota.

**Status:** done

- [x] Nenhuma tela cria diretamente uma segunda sessão para a mesma nota.
- [x] O registro estático deixa de controlar se uma sessão está ativa.
- [x] A inicialização em duas fases do controller deixa de ser necessária.
- [x] Campos anuláveis usados somente para representar inicialização parcial são removidos ou encapsulados.
- [x] O descarte não é iniciado sem coordenação pelo proprietário da sessão.
- [x] Hooks vazios ou legados de suspensão e retomada são removidos ou recebem comportamento real documentado.
- [x] Não restam providers descartáveis que recriem locks ou filas REST/OT durante a mesma sessão autenticada.
- [x] Testes de caracterização do ticket 03 passam com as novas expectativas de exclusividade.
- [x] Busca estática confirma que os mecanismos de ownership antigos não têm consumidores.
