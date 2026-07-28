# Preferências por nota

Esta pasta contém preferências que não mudam o conteúdo canônico: favorito,
ocultar tarefas concluídas e colapsar imagens.

`UserNotePreferencesRepository` persiste preferências do usuário por nota.
`NotePreferenceMutationController` serializa mutações rápidas e só faz rollback
quando a falha ainda pertence à versão mais recente daquele campo. Isto evita
que uma resposta velha desfaça uma escolha nova.

Não use este módulo para metadados de tarefa; esses pertencem ao documento e
ao [editor](../editor/README.md).
