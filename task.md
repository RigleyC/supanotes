# Task: ocorrências por recorrência e histórico esparso

- [x] Criar `TaskOccurrence` domain model + `buildOccurrences()` com status pending/overdue/completed
- [x] Cobrir todos os tipos de recorrência e bordas (diário, semanal, mensal, dias úteis, hasTime)
- [x] Corrigir IsolateMerge (`_mergeRemoteStatesAndProjectIsolate`) para propagar completions
- [x] Remover `catchUpDueDate` do fluxo legado (`TasksDao.updateTask`, `TasksDao.catchUpRecurringTasks`)
- [x] Adicionar migração na projeção para gerar completion sintético para tarefas recorrentes legadas com `lastCompletedAt`
- [x] Corrigir undo na note_editor_screen para não modificar template de tarefas recorrentes
- [x] Atualizar testes para refletir o novo comportamento (dueDate como âncora, sem catch-up)
