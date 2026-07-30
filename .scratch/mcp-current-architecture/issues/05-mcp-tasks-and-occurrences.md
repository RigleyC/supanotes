# 05 — Expor tarefas, metadados e ocorrências recorrentes

**What to build:** Um agent deve operar tarefas como blocos de documentos, incluindo metadados, recorrência e conclusão de ocorrências específicas.

**Blocked by:** 04 — Expor edição completa de blocos pelo MCP.

**Status:** ready-for-agent

- [x] Criar tarefa somente dentro de uma nota e como bloco documental.
- [x] Editar texto e metadados de tarefa: data, hora, recorrência, lembrete e estado permitido.
- [x] Listar tarefas por nota e pelos filtros suportados pelo produto atual.
- [x] Concluir ocorrência recorrente usando a data programada da ocorrência.
- [x] Reabrir a ocorrência correta sem apagar histórico válido.
- [ ] Consultar a projeção para confirmar o resultado, sem escrever diretamente nela.
- [ ] Testar tarefa simples, tarefa recorrente, atraso, retry, concorrência e projeção.

**Pending migration:** Os tools legados `create_task`, `update_task`, `complete_task`, `reopen_task` e `delete_task` ainda chamam `tasks.Service` diretamente. Eles devem ser removidos ou migrados para os comandos documentais antes de considerar este ticket concluído.
