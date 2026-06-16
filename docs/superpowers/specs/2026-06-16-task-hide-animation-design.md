# Animação de Ocultação de Tarefas Concluídas

## Visão Geral
Adicionar uma animação suave (Fade Out + Colapso de Altura) quando uma tarefa é marcada como concluída e a opção "Ocultar concluídas" (`hideCompleted`) está ativada. Atualmente, a tarefa desaparece instantaneamente de forma abrupta.

## Escopo
A animação deve ser executada apenas quando:
- O usuário ativa o checkbox de uma tarefa.
- A opção `hideCompleted` está ativa na nota.

A animação aguarda o desenho verde do checkbox terminar (~300ms) e em seguida colapsa a tarefa e faz fade out (~350ms).

## Arquitetura e Fluxo de Dados

1. **Estado Temporário no Builder**: O `CustomTaskComponentBuilder` possuirá um conjunto `_animatingNodeIds` para guardar temporariamente as tarefas que estão no meio da animação.
2. **Ciclo de Vida do Widget**: 
   - Ao clicar no checkbox, interceptamos a ação no `CustomTaskComponentViewModel`.
   - O ID da tarefa é adicionado em `_animatingNodeIds`.
   - O comando `ChangeTaskCompletionRequest` do editor é executado.
   - O `DocumentLayout` do `super_editor` processa a mudança e chama o Builder.
   - O Builder (`createViewModel`) nota que a tarefa foi concluída, mas como o ID está em `_animatingNodeIds`, ele decide renderizar a tarefa temporariamente em vez de retornar `null`.
3. **Animação Visual (`CustomTaskComponent`)**:
   - O componente visual percebe que a tarefa passou a ficar completa.
   - Ele pausa por 300ms (tempo para o checkbox exibir seu ícone).
   - Inicia uma animação com `SizeTransition` e `FadeTransition` simultaneamente, que dura 350ms.
   - Ao atingir `AnimationStatus.completed`, dispara o callback `onAnimationComplete()`.
4. **Remoção Final Limpa**:
   - O Builder recebe o aviso, remove o ID de `_animatingNodeIds` e dispara o `setState` (callback de rebuild da raiz do editor).
   - O layout refaz os nós. Como o ID não está mais no conjunto, o Builder agora retorna `null` imediatamente, expurgando a tarefa do visual sem deixar nós com altura zero na árvore de elementos.

## Arquivos e Componentes Afetados
- `NoteEditor` (`lib/features/notes/presentation/widgets/note_editor.dart`): Passará a instanciar o `CustomTaskComponentBuilder` no `initState` para persistir o estado do builder durante o re-render. Fornecerá um callback para forçar rebuild local.
- `CustomTaskComponentBuilder` (`lib/features/notes/presentation/widgets/custom_task_component.dart`): Controlará o conjunto `_animatingNodeIds` e fará a ponte entre o término da animação do widget e a notificação ao Editor.
- `CustomTaskComponent` e `_CustomTaskComponentState`: Receberá o mixin `TickerProviderStateMixin`, alocará os controllers e usará os widgets animáveis (`SizeTransition`, `FadeTransition`).
- `TaskComponentViewModel`: Incluirá campos adicionais necessários (como `hideCompleted` ou `onAnimationComplete`) para que o state do componente saiba quando deve engatilhar a saída.

## Critérios de Aceitação
- Tarefas já concluídas anteriormente continuam ocultas sem animação indesejada ao abrir ou rolar a nota.
- O clique em um checkbox (com "ocultar" ativado) aciona a animação apenas da tarefa local.
- Sem "ghost nodes" invisíveis atrapalhando o input do usuário e o layout.
