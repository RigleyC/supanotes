# Contrato do Super Editor para ocultar tasks concluídas

Data: 2026-08-02  
Escopo: investigação somente de leitura. Não alterei código de produção nesta pesquisa. O working tree já continha alterações não commitadas em `task_exit_animator.dart` e `note_editor_screen_test.dart`; elas foram preservadas.

## Resumo executivo

O repositório usa o `super_editor` no commit `3bb857bc423240b61dc0fb799f3c269e71feb24a`, conforme o lockfile:

- [pubspec.lock:1365-1373](../../pubspec.lock#L1365-L1373)
- [commit fixado no GitHub](https://github.com/Flutter-Bounty-Hunters/super_editor/tree/3bb857bc423240b61dc0fb799f3c269e71feb24a)

A implementação atual de tasks concluídas ocultas não respeita totalmente o contrato do Super Editor. O problema principal é este:

1. `CustomTaskComponent` é um `ProxyDocumentComponent` que encaminha operações para o `TextComponent` filho.
2. `TaskExitAnimator`, depois da animação, troca toda a subárvore por `SizedBox`.
3. O layout do Super Editor ainda mantém o componente da task porque o `TaskNode` continua no `Document`.
4. O proxy permanece registrado, mas o `GlobalKey` do filho deixa de apontar para um `DocumentComponent`.
5. Qualquer consulta encaminhada que não tenha sido sobrescrita pode falhar, por exemplo `getEndPosition`, `getBeginningPosition`, seleção, caret ou `ProxyTextComposable`.

O override de `getPositionAtOffset` que retorna `null` é correto para impedir que um ponto de mouse sobre uma task oculta produza uma posição. Porém, ele é apenas uma proteção de seleção por offset; não corrige o ciclo de vida do filho do proxy.

## O que o Super Editor considera um componente

### `ComponentBuilder`

No commit fixado, `ComponentBuilder` tem duas responsabilidades explícitas:

- `createViewModel` produz o view model para um `DocumentNode`, ou retorna `null` quando aquele builder não se aplica ao node.
- `createComponent` cria o widget visual para o view model, e o widget retornado deve ser um `StatefulWidget` que implemente `DocumentComponent`.

Fontes:

- [código oficial `_presenter.dart:7-24`](https://github.com/Flutter-Bounty-Hunters/super_editor/blob/3bb857bc423240b61dc0fb799f3c269e71feb24a/super_editor/lib/src/default_editor/layout_single_column/_presenter.dart#L7-L24)
- [código oficial `_presenter.dart:332-351`](https://github.com/Flutter-Bounty-Hunters/super_editor/blob/3bb857bc423240b61dc0fb799f3c269e71feb24a/super_editor/lib/src/default_editor/layout_single_column/_presenter.dart#L332-L351)
- [API pública de `ComponentBuilder`](https://pub.dev/documentation/super_editor/latest/super_editor/ComponentBuilder-class.html)

O presenter padrão percorre todos os nodes do `Document` e tenta criar um view model para cada um. Se nenhum builder produzir um view model, ele lança uma exceção. Portanto, retornar `null` para uma task concluída não é um mecanismo seguro para esconder nodes no `ComponentBuilder` padrão.

- [código oficial `_presenter.dart:146-181`](https://github.com/Flutter-Bounty-Hunters/super_editor/blob/3bb857bc423240b61dc0fb799f3c269e71feb24a/super_editor/lib/src/default_editor/layout_single_column/_presenter.dart#L146-L181)

Isso também significa que `ComponentBuilder` não deve ser usado como filtro de conteúdo. O conteúdo continua pertencendo ao `Document`; o builder escolhe como esse conteúdo é representado visualmente.

### `DocumentLayout`

`DocumentLayout` é a fonte de verdade da tradução entre posições lógicas do documento e posições visuais. Ele pode retornar `null` quando não há conteúdo visual em um offset, e `getComponentByNodeId` também pode retornar `null` quando não existe um componente visual correspondente.

- [código oficial `document_layout.dart:32-100`](https://github.com/Flutter-Bounty-Hunters/super_editor/blob/3bb857bc423240b61dc0fb799f3c269e71feb24a/super_editor/lib/src/core/document_layout.dart#L32-L100)
- [API pública de `DocumentLayout`](https://pub.dev/documentation/super_editor/latest/super_editor/DocumentLayout-class.html)

No entanto, o `SingleColumnDocumentLayout` usa os view models produzidos pelo presenter para manter a ordem, as chaves e o mapeamento dos componentes. O fluxo normal para uma alteração estrutural é o presenter informar componentes adicionados, movidos, alterados e removidos, e o layout refazer o fluxo quando necessário.

- [código oficial `_presenter.dart:189-321`](https://github.com/Flutter-Bounty-Hunters/super_editor/blob/3bb857bc423240b61dc0fb799f3c269e71feb24a/super_editor/lib/src/default_editor/layout_single_column/_presenter.dart#L189-L321)
- [código oficial `_layout.dart:123-137`](https://github.com/Flutter-Bounty-Hunters/super_editor/blob/3bb857bc423240b61dc0fb799f3c269e71feb24a/super_editor/lib/src/default_editor/layout_single_column/_layout.dart#L123-L137)

Não encontrei, no commit fixado nem na documentação oficial, uma API de alto nível chamada “hide node” que remova um node do layout sem também definir como seleção, caret, navegação e operações devem tratar esse node. Filtrar diretamente a lista de view models exigiria validar esses contratos em todos os caminhos de interação.

## Contrato de `DocumentComponent` e `ProxyDocumentComponent`

`DocumentComponent` é um contrato completo. Ele não é apenas um callback para descobrir a posição sob o mouse. O componente deve responder a operações como:

- posição em um offset;
- offset para uma posição;
- geometria do caret;
- início e fim do node;
- seleção dentro do node;
- suporte a seleção visual;
- cursor desejado.

- [código oficial `document_layout.dart:102-280`](https://github.com/Flutter-Bounty-Hunters/super_editor/blob/3bb857bc423240b61dc0fb799f3c269e71feb24a/super_editor/lib/src/core/document_layout.dart#L102-L280)
- [API pública de `DocumentComponent`](https://pub.dev/documentation/super_editor/latest/super_editor/DocumentComponent-mixin.html)

`ProxyDocumentComponent` existe para wrappers que mantêm outro `DocumentComponent` montado. Ele obtém o filho pelo `GlobalKey` e encaminha praticamente todos os métodos para esse filho.

- [código oficial `document_layout.dart:328-367`](https://github.com/Flutter-Bounty-Hunters/super_editor/blob/3bb857bc423240b61dc0fb799f3c269e71feb24a/super_editor/lib/src/core/document_layout.dart#L328-L367)
- [código oficial `document_layout.dart:369-469`](https://github.com/Flutter-Bounty-Hunters/super_editor/blob/3bb857bc423240b61dc0fb799f3c269e71feb24a/super_editor/lib/src/core/document_layout.dart#L369-L469)
- [API pública de `ProxyDocumentComponent`](https://pub.dev/documentation/super_editor/latest/super_editor/ProxyDocumentComponent-mixin.html)

O contrato pressupõe que `childDocumentComponentKey.currentState` continue sendo um `DocumentComponent` quando o proxy for consultado. O código oficial faz um cast direto do estado do filho; ele não trata um filho removido como um estado válido.

## Comparação com a implementação atual

### O que está correto

Em [custom_task_component.dart:279-283](../../lib/features/notes/editor/presentation/widgets/custom_task_component.dart#L279-L283), retornar `null` em `getPositionAtOffset` quando a task está oculta é uma resposta coerente ao contrato desse método: o contrato permite retornar `null` quando o offset não contém conteúdo.

Também é coerente ignorar eventos de ponteiro para uma task oculta em [custom_task_component.dart:380-389](../../lib/features/notes/editor/presentation/widgets/custom_task_component.dart#L380-L389). A task continua no documento, portanto não deve ser apagada ou transformada apenas porque uma preferência visual está ativa.

### O que está incorreto

O componente usa `ProxyDocumentComponent` e `ProxyTextComposable` em [custom_task_component.dart:174-176](../../lib/features/notes/editor/presentation/widgets/custom_task_component.dart#L174-L176), com `_textKey` como filho em [custom_task_component.dart:246-251](../../lib/features/notes/editor/presentation/widgets/custom_task_component.dart#L246-L251).

Depois da animação, [task_exit_animator.dart:96-104](../../lib/features/notes/editor/presentation/widgets/task_exit_animator.dart#L96-L104) retorna `SizedBox` quando `_fullyHidden` é verdadeiro. Isso remove o `TextComponent` que o proxy precisa consultar, mas não remove o `TaskNode` do documento nem necessariamente remove o componente pai do layout.

Os overrides atuais de geometria em [custom_task_component.dart:253-277](../../lib/features/notes/editor/presentation/widgets/custom_task_component.dart#L253-L277) reduzem alguns sintomas, mas não cobrem os métodos encaminhados restantes. Além disso, `childTextComposable` ainda faz cast direto do estado do filho em [custom_task_component.dart:249-251](../../lib/features/notes/editor/presentation/widgets/custom_task_component.dart#L249-L251).

Esse é um estado inconsistente: o layout conhece o node, o componente pai ainda existe, mas o filho que implementa o contrato de texto não existe mais.

## `Visibility` e `SizeTransition`

Esses widgets são mecanismos de composição do Flutter, não APIs de remoção de nodes do Super Editor.

### `Visibility`

A documentação oficial do Flutter informa que:

- alterar dinamicamente flags de manutenção além de `visible` pode reconstruir a subárvore e descartar estado;
- sem flags de manutenção, o widget substitui o filho por `SizedBox.shrink()`;
- `maintainState` mantém os objetos de estado, enquanto `maintainSize` mantém o espaço;
- `IgnorePointer`, `ExcludeSemantics`, `Offstage` e `Opacity` cobrem aspectos diferentes de “esconder”.

- [documentação oficial de `Visibility`: linhas 12-20](https://api.flutter.dev/flutter/widgets/Visibility-class.html#L12-L20)
- [documentação oficial de `Visibility`: linhas 37-101](https://api.flutter.dev/flutter/widgets/Visibility-class.html#L37-L101)

Para um `ProxyDocumentComponent`, `Visibility(visible: false)` com a configuração padrão é inadequado porque substitui/remonta o filho. `Visibility.maintain` pode manter o estado, mas não resolve sozinho o contrato de layout, seleção e geometria. Portanto, não deve ser aplicado como correção isolada.

### `SizeTransition`

`SizeTransition` anima o tamanho recortado do filho através de `sizeFactor`. A documentação destaca que ele precisa estar em um contexto que permita mudança de tamanho; um container com tamanho fixo impede o efeito.

- [documentação oficial de `SizeTransition`: linhas 12-15](https://api.flutter.dev/flutter/widgets/SizeTransition-class.html#L12-L15)
- [documentação oficial de `SizeTransition`: linhas 40-90](https://api.flutter.dev/flutter/widgets/SizeTransition-class.html#L40-L90)

Para este caso, `SizeTransition` é adequado como animação visual enquanto o `TextComponent` continua montado. O erro está em trocar a subárvore inteira por `SizedBox` ao final, e não no uso do `SizeTransition` em si.

## `DeleteNodeRequest` e `ReplaceNodeRequest`

### `DeleteNodeRequest`

`DeleteNodeRequest` representa uma alteração estrutural real: o comando procura o node pelo ID, remove-o do `Document` e registra um `NodeRemovedEvent`.

- [código oficial `multi_node_editing.dart:1419-1454`](https://github.com/Flutter-Bounty-Hunters/super_editor/blob/3bb857bc423240b61dc0fb799f3c269e71feb24a/super_editor/lib/src/default_editor/multi_node_editing.dart#L1419-L1454)
- [API pública de `DeleteNodeCommand`](https://pub.dev/documentation/super_editor/latest/super_editor/DeleteNodeCommand-class.html)

Ele é correto quando o usuário realmente apaga uma task. Não é correto para “ocultar tasks concluídas”, pois destruiria o conteúdo canônico e quebraria a possibilidade de reabrir a task.

### `ReplaceNodeRequest`

`ReplaceNodeRequest` substitui um node por outro e registra a remoção do node antigo e a inserção do novo.

- [código oficial `multi_node_editing.dart:605-637`](https://github.com/Flutter-Bounty-Hunters/super_editor/blob/3bb857bc423240b61dc0fb799f3c269e71feb24a/super_editor/lib/src/default_editor/multi_node_editing.dart#L605-L637)

Ele é correto para uma transformação de tipo ou conteúdo, por exemplo converter uma task em parágrafo. Não é uma operação de visibilidade. Substituir uma task oculta por um parágrafo vazio seria perda ou mutação indevida do documento.

## Recomendação aplicada ao caso

### Comportamento desejado

“Ocultar tasks concluídas” deve ser tratado como uma preferência visual da tela, não como uma mutação do `Document`:

- manter o `TaskNode` no documento;
- manter o `CustomTaskComponent` e o `TextComponent` filho montados enquanto o node estiver no layout;
- animar a redução visual com `SizeTransition` e `FadeTransition`;
- bloquear ponteiro e semântica quando a task estiver efetivamente oculta;
- retornar `null` em `getPositionAtOffset` para não criar uma seleção a partir de um offset invisível;
- retornar `false` em `isVisualSelectionSupported` enquanto estiver oculta, para que seleção por região não use a task como início ou fim;
- retornar `null` em `getDesiredCursorAtOffset` quando estiver oculta;
- preservar a capacidade de reabrir a task e de renderizá-la novamente quando o filtro for desligado.

### Ajuste recomendado

O primeiro ajuste deve ser no ciclo de vida do animator: ele não deve retornar `SizedBox` no estado `_fullyHidden` enquanto o `CustomTaskComponent` continuar registrado no layout. A subárvore deve permanecer montada com `SizeTransition(sizeFactor: 0)` ou com um componente visual equivalente que não destrua o `TextComponent` filho. A alteração não commitada atualmente presente em [task_exit_animator.dart:96-104](../../lib/features/notes/editor/presentation/widgets/task_exit_animator.dart#L96-L104) já segue essa parte da recomendação ao manter o `SizeTransition`; ainda é necessário validar os guards de seleção, cursor e semântica descritos acima.

Depois disso, os guards de interação e seleção devem ser tratados como parte do contrato de `DocumentComponent`, e não como tratamento de exceção genérico. Os `try/catch` que retornam `Rect.zero` ou `Offset.zero` em [custom_task_component.dart:253-277](../../lib/features/notes/editor/presentation/widgets/custom_task_component.dart#L253-L277) devem ser reavaliados: eles podem mascarar uma chamada inválida e produzir geometria falsa.

### Quando remover de verdade

Se no futuro o produto precisar apagar a task, a ação deve passar pelo editor com `DeleteNodeRequest` e seguir o fluxo de operações do documento. Se precisar converter a task em outro bloco, deve usar `ReplaceNodeRequest`. Nenhuma dessas operações deve ser usada para implementar apenas o filtro “ocultar concluídas”.

## Testes exigidos antes da alteração ser considerada correta

1. Task concluída oculta como primeiro node: clicar acima dela não lança exceção e não seleciona a task.
2. Task concluída oculta como último node: consultar `findLastSelectablePosition()` não lança exceção e não retorna posição da task oculta.
3. Durante a animação: hover, clique, seleção por região e cálculo de cursor não acessam um filho desmontado.
4. Depois da animação: `childDocumentComponentKey.currentState` continua sendo um `DocumentComponent` enquanto o `TaskNode` estiver no documento.
5. Desligar “ocultar concluídas”: a mesma task volta a ter tamanho, texto, checkbox e seleção válidos.
6. Reabrir a task: o node continua o mesmo e a operação de conteúdo segue o caminho normal do editor.

## Conclusão

A forma recomendada para este caso não é apagar ou substituir o node. Também não é remover o filho de um `ProxyDocumentComponent` e tentar neutralizar chamadas com vários `null-checks`.

A correção alinhada ao contrato é manter o componente document-aware montado e controlar visibilidade, interação e participação na seleção explicitamente. `SizeTransition` pode permanecer como mecanismo de animação; o branch que desmonta o filho após a animação deve ser removido ou substituído por uma estratégia que preserve o `DocumentComponent` enquanto o node existir no documento.
