# 01 — Persistência atômica da nota local

**What to build:** Quando o app recebe uma nota ou documento remoto, o snapshot canônico, o catálogo local e as projeções da nota devem ser salvos como um único estado local. Uma interrupção não pode deixar uma nota parcialmente hidratada ou invisível offline.

**Blocked by:** None — can start immediately.

**Status:** done

- [ ] A primeira hidratação de uma nota remota preserva conteúdo, título, excerpt, metadados e tarefas no catálogo local.
- [ ] Snapshot, catálogo e projeções são confirmados juntos ou nenhum deles fica publicado.
- [ ] Uma falha entre duas escritas não deixa snapshot órfão nem uma nota sem conteúdo.
- [ ] Depois de reiniciar sem rede, a nota continua abrindo com o mesmo conteúdo local.
- [ ] Testes cobrem primeira hidratação, falha durante a persistência e reabertura offline.
