# Recorrencias por ocorrencia

Tarefas recorrentes permanecem templates no YDoc. Ao concluir pelo editor, a
bridge calcula a ocorrencia mais recente ate o momento atual e grava um evento
em `taskCompletions/<taskId>:<scheduledAt>`, sem mover a data ancora.

O snackbar carrega `scheduledAt` ate o undo, que remove exatamente o mesmo
evento. SQLite e PostgreSQL reconciliam as completions recorrentes a partir do
YDoc, removendo projeções que desapareceram em um undo.

O banco local foi atualizado para schema 20 com `scheduled_at` e unicidade por
`task_id + scheduled_at`. O backend agora persiste `has_time` e `reminder` pelo
contrato REST e aceita `due_date` em data simples ou RFC3339.

O checkbox presente na nota representa a ocorrencia mais recente ate hoje. Uma
lista visual que mostre varias ocorrencias atrasadas simultaneamente ainda
precisa de uma tela/read model de tarefas dedicado.
