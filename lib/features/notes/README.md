# Notes: módulo central do produto

Uma nota é um documento rico, não um texto com campos independentes. Seu
snapshot REST/OT contém blocos de parágrafo, lista, tarefa, imagem, anexo e
link. O módulo foi dividido pelos fluxos que mudam juntos.

| Pasta | Responsabilidade | Quando entrar nela |
| --- | --- | --- |
| `catalog/` | criar, listar, buscar e hidratar notas | mudança na lista ou no ciclo de vida da nota |
| `editor/` | abrir, editar, serializar e sincronizar um documento | mudança no conteúdo ou no protocolo |
| `attachments/` | upload e estado local de arquivos | mudança de anexos |
| `sharing/` | permissões e lista de compartilhamentos | mudança de colaboração por usuário |
| `preferences/` | preferências por nota | favoritos, ocultar concluídas e imagens |

As antigas pastas `data/`, `domain/` e `presentation/` foram removidas após a
migração dos importadores. Novos arquivos devem ficar no submódulo correto.

## Leitura recomendada

1. [catalog](catalog/README.md): como uma nota passa a existir localmente.
2. [editor](editor/README.md): como a edição vira operação REST/OT.
3. [tasks](../tasks/README.md): como tarefas vivem no documento e alimentam
   notificações locais.
4. [backend noteoperations](../../../backend/internal/noteoperations/README.md): como o servidor confirma uma operação.

Para a referência arquivo por arquivo, consulte [Notes: file reference](../../../docs/architecture/notes-file-reference.md).

## Regra de ouro

Para mudar texto ou metadados de uma tarefa, altere o documento através da
sessão do editor. Não existe DAO relacional de tarefas.
