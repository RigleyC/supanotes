# 08 — Matriz final de validação multiplataforma

**What to build:** Executar e registrar a matriz final dos fluxos de nota local-first, sincronização, compartilhamento e recuperação em Flutter, Windows, Android e iOS. Cada cenário deve apontar para uma asserção automatizada ou para um smoke test manual claramente identificado.

**Blocked by:** 05 — Harness E2E do fluxo local-first; 06 — E2E de duas contas e colaboração; 07 — Catálogo e rede fraca resilientes.

**Status:** ready-for-agent

- [ ] Todos os cenários automatizáveis da matriz têm teste executável e nomeado.
- [ ] O conjunto completo passa em análise estática, testes Flutter, testes de integração Windows e testes Go.
- [ ] Smoke tests cobrem encerramento forçado durante digitação, suspensão/retomada e troca real de Wi-Fi/dados móveis.
- [ ] O resultado registra plataforma, cenário, evidência, falha e condição de reprodução.
- [ ] Falta de espaço em disco e interrupção durante escrita local são tratadas como cenários manuais explícitos.
- [ ] A documentação distingue cobertura automatizada de estados físicos que não podem ser provados por um teste finito.
