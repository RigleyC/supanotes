# List Indentation Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fazer o nível `indent = 0` de bullets, listas numeradas e tasks começar na mesma borda de conteúdo de um parágrafo. Manter a capacidade de aumentar e reduzir o nível por teclado e pela toolbar, usando os comandos semânticos já fornecidos pelo Super Editor.

**Architecture:** Criar um `ComponentBuilder` local para bullets e listas numeradas. O builder reutiliza os `ViewModel`s e os componentes oficiais do Super Editor, mas fornece uma geometria própria para o slot do marcador e para a indentação. Ajustar o `CustomTaskComponent` existente para usar a mesma unidade de indentação. Centralizar os comandos de indentação da toolbar em métodos que aceitam `ListItemNode` e `TaskNode`. Não alterar o modelo de documento, REST/OT, codec, persistência ou o fork do Super Editor.

**Tech Stack:** Flutter, Dart, `super_editor` já pinado no projeto, `flutter_test`, `Editor`, `DocumentComposer`, `EditRequest` e os comandos oficiais de lista/task.

## Global Constraints

- Preservar as alterações não relacionadas que já existem no worktree.
- Não adicionar dependências.
- Não criar camada de compatibilidade para os nomes antigos dos comandos.
- Não escrever diretamente na tabela `tasks`; a indentação continua sendo uma operação do documento canônico.
- Não alterar `ListItemNode.indent`, `TaskNode.indent`, o codec, a captura OT ou a projeção de tasks.
- Manter as ações oficiais de teclado: `Tab`, `Shift+Tab` e `Backspace` continuam usando as ações padrão do Super Editor.
- O nível visual deve obedecer a esta geometria:
  - `U = fontSize * 0.60 * 4`.
  - marcador no nível `n`: começa em `n * U`.
  - texto no nível `n`: começa em `(n + 1) * U`.
  - portanto, no nível zero o marcador começa na borda do parágrafo, com um slot de marcador antes do texto.
- Para checkbox, manter o pequeno espaçamento interno visual já usado pelo componente. A borda do slot, e não o centro do checkbox, é o alinhamento com o parágrafo.
- Cada tarefa termina com um teste executável e uma verificação focalizada antes de iniciar a próxima.

---

## Contexto e decisões aceitas

O Super Editor já armazena o nível semântico em `ListItemNode.indent` e `TaskNode.indent`. Ele também já oferece operações oficiais para aumentar e reduzir esse nível. O problema está na apresentação: o componente padrão de lista usa um slot com o marcador alinhado à direita, o que deixa o marcador do nível zero afastado da borda do parágrafo.

A solução escolhida é um builder local, pequeno e específico do editor. Ele usa `UnorderedListItemComponent` e `OrderedListItemComponent` oficiais com builders de marcador alinhados à esquerda e com uma calculadora de indentação compartilhada. Isso resolve a posição visual sem manter um fork da biblioteca.

A referência técnica usada para esta decisão está em [docs/research/2026-08-13-super-editor-list-indentation.md](/C:/Users/rigleyc/projects/supanotes/docs/research/2026-08-13-super-editor-list-indentation.md).

## Mapa do código existente

- `lib/features/notes/editor/presentation/widgets/note_editor.dart`
  - Registra `_componentBuilders`.
  - O builder local de lista deve entrar antes de `...defaultComponentBuilders`, para ganhar da implementação padrão.
- `lib/features/notes/editor/presentation/widgets/custom_task_component.dart`
  - Já renderiza checkbox, texto, metadados e `viewModel.indent`.
  - Hoje usa `defaultListItemIndentCalculator` como uma largura única; essa largura precisa ser dividida em deslocamento do nível e slot do marcador.
- `lib/features/notes/editor/presentation/widgets/note_toolbar.dart`
  - Calcula `formattingNodes`.
  - Exibe e aciona os botões de indentação.
- `lib/features/notes/editor/presentation/widgets/note_toolbar_menus.dart`
  - Recebe o booleano que controla os botões de indentação.
- `lib/features/notes/editor/document/note_editor_commands.dart`
  - Hoje `indentListItems` e `unindentListItems` filtram somente `ListItemNode`.
- `test/features/notes/domain/note_editor_commands_test.dart`
  - Já cobre indentação e desindentação de listas.
- `test/features/notes/presentation/widgets/note_toolbar_test.dart`
  - Já cobre a visibilidade dos botões para listas e sua ausência em parágrafos.
- `test/features/notes/domain/ot_document_codec_test.dart`
  - Já cobre a preservação do indent no documento codificado.
- `test/features/notes/domain/editor_operation_capture_test.dart`
  - Já cobre a captura de alterações de indentação de tasks.

## Plano de implementação

### Tarefa 1 — Criar a geometria compartilhada e o builder local de listas

**Arquivos:**

- Criar `lib/features/notes/editor/presentation/widgets/custom_list_item_component.dart`.
- Alterar `lib/features/notes/editor/presentation/widgets/note_editor.dart`.
- Criar ou ampliar `test/features/notes/presentation/widgets/custom_list_item_component_test.dart`.

#### 1.1 Escrever os testes que devem falhar

Adicionar testes unitários para a API de geometria que será usada tanto por listas quanto por tasks:

```dart
test('uses one font-based indent unit', () {
  const textStyle = TextStyle(fontSize: 16);

  expect(noteEditorIndentUnit(textStyle), closeTo(38.4, 0.001));
});

test('starts the marker at the content edge and advances one unit per level', () {
  const textStyle = TextStyle(fontSize: 16);

  expect(noteEditorListIndentCalculator(textStyle, 0), closeTo(38.4, 0.001));
  expect(noteEditorListIndentCalculator(textStyle, 1), closeTo(76.8, 0.001));
});

test('uses the paragraph fallback when the text size is absent', () {
  expect(noteEditorIndentUnit(const TextStyle()), closeTo(38.4, 0.001));
});
```

Adicionar um teste de widget que registra somente o builder local em uma lista de builders e verifica que um documento com `ListItemNode` monta `UnorderedListItemComponent` e `OrderedListItemComponent`. O teste deve executar com um `SuperEditor` mínimo, sem `defaultComponentBuilders`, para provar que o builder local cria os dois componentes oficiais.

#### 1.2 Executar os testes e confirmar a falha

Executar:

```text
rtk flutter test test/features/notes/presentation/widgets/custom_list_item_component_test.dart
```

O teste deve falhar porque `custom_list_item_component.dart`, `noteEditorIndentUnit` e `noteEditorListIndentCalculator` ainda não existem.

#### 1.3 Implementar o builder mínimo

Em `custom_list_item_component.dart`:

- Expor estas assinaturas top-level:

  ```dart
  double noteEditorIndentUnit(TextStyle textStyle);
  double noteEditorListIndentCalculator(TextStyle textStyle, int indent);
  class CustomListItemComponentBuilder extends ListItemComponentBuilder {
    const CustomListItemComponentBuilder();
  }
  ```

- Fazer `noteEditorIndentUnit` usar `fontSize ?? 16` e a fórmula `fontSize * 0.60 * 4`.
- Fazer `noteEditorListIndentCalculator` retornar `noteEditorIndentUnit(textStyle) * (indent + 1)`. O componente oficial usa essa largura para separar o marcador do texto; o builder do marcador é que muda de alinhamento.
- Estender `ListItemComponentBuilder` para reutilizar seu `createViewModel`, cálculo de ordinal, estilos e metadados.
- Sobrescrever `createComponent` com a assinatura oficial:

  ```dart
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  );
  ```

- Para `UnorderedListItemComponentViewModel`, criar `UnorderedListItemComponent` com todos os valores do view model e:
  - `indentCalculator: noteEditorListIndentCalculator`;
  - `dotBuilder: _leftAlignedDotBuilder`.
- Para `OrderedListItemComponentViewModel`, criar `OrderedListItemComponent` com todos os valores do view model e:
  - `indentCalculator: noteEditorListIndentCalculator`;
  - `numeralBuilder: _leftAlignedNumeralBuilder`.
- Retornar `null` para qualquer outro tipo de view model.
- Manter os estilos atuais dos marcadores, incluindo tamanho, forma, cor, numeral e suporte a estilos ordenados. Os builders locais podem copiar somente a formatação do builder oficial, mas devem trocar `Alignment.centerRight` por `Alignment.centerLeft`.
- Não criar uma chave baseada em `nodeId` no marcador: os builders públicos recebem o componente, não o `nodeId`. A prioridade do builder é coberta pelo harness sem `defaultComponentBuilders`, e a posição é coberta pela geometria e pela inspeção visual.

Em `note_editor.dart`:

- Instanciar `const CustomListItemComponentBuilder()` em `_componentBuilders` antes de `...defaultComponentBuilders`.
- Não remover `CustomTaskComponentBuilder`, `CustomDividerComponentBuilder` ou `AttachmentComponentBuilder`.

#### 1.4 Executar os testes

Executar novamente:

```text
rtk flutter test test/features/notes/presentation/widgets/custom_list_item_component_test.dart
```

O teste deve passar e confirmar a geometria e a prioridade do builder local.

#### 1.5 Commit da tarefa

```text
git add lib/features/notes/editor/presentation/widgets/custom_list_item_component.dart lib/features/notes/editor/presentation/widgets/note_editor.dart test/features/notes/presentation/widgets/custom_list_item_component_test.dart
git commit -m "feat(editor): align list markers with paragraph edge"
```

### Tarefa 2 — Fazer o componente de task usar a mesma geometria

**Arquivos:**

- Alterar `lib/features/notes/editor/presentation/widgets/custom_task_component.dart`.
- Ampliar `test/features/notes/presentation/widgets/custom_list_item_component_test.dart`.

#### 2.1 Escrever os testes que devem falhar

Adicionar um teste de widget que monta tasks nos níveis zero e um usando `CustomTaskComponentBuilder`. O teste deve localizar os dois `AppTaskCheckbox` pelos ids das tasks e confirmar que a diferença entre as posições horizontais é uma unidade `U`.

O teste deve também montar uma task de nível zero junto com um parágrafo e confirmar que o limite esquerdo do slot da task coincide com a borda de conteúdo do componente, mantendo o inset interno atual do checkbox.

Executar:

```text
rtk flutter test test/features/notes/presentation/widgets/custom_list_item_component_test.dart --plain-name "task indentation uses the shared list geometry"
```

O teste deve falhar porque o componente ainda usa uma largura única para o nível completo e não cria um deslocamento separado para tasks aninhadas.

#### 2.2 Implementar a alteração mínima

Em `custom_task_component.dart`:

- Importar `custom_list_item_component.dart`.
- Substituir o uso de `defaultListItemIndentCalculator` por:

  ```dart
  final indentUnit = noteEditorIndentUnit(textStyle);
  final levelOffset = indentUnit * widget.viewModel.indent;
  ```

- Reestruturar a primeira parte da `Row` para ter:
  1. `SizedBox(width: levelOffset)`;
  2. `SizedBox(width: indentUnit, child: ...)` contendo `Semantics`, `Align` e `AppTaskCheckbox`;
  3. `Expanded` com a coluna atual de texto e metadados.
- Manter a animação, callbacks, semântica, teclado, badges e checkbox existentes.
- Manter o inset interno de `11` pixels dentro do slot do checkbox.

#### 2.3 Executar os testes

```text
rtk flutter test test/features/notes/presentation/widgets/custom_list_item_component_test.dart
```

O teste deve passar para tasks de nível zero e um, sem alterar o estado semântico do documento.

#### 2.4 Commit da tarefa

```text
git add lib/features/notes/editor/presentation/widgets/custom_task_component.dart test/features/notes/presentation/widgets/custom_list_item_component_test.dart
git commit -m "feat(editor): share list indentation geometry with tasks"
```

### Tarefa 3 — Generalizar os comandos de indentação para listas e tasks

**Arquivos:**

- Alterar `lib/features/notes/editor/document/note_editor_commands.dart`.
- Alterar `test/features/notes/domain/note_editor_commands_test.dart`.

#### 3.1 Escrever os testes que devem falhar

Renomear os grupos atuais de `indentListItems` e `unindentListItems` para refletir a nova API. Adicionar estes casos:

Criar os dois casos usando o mesmo padrão já existente no arquivo: `MutableDocument` com dois `TaskNode`s consecutivos, `MutableDocumentComposer(initialSelection: caretSelection('node-2'))` e `createDefaultDocumentEditor`. No caso de aumento, ambos começam em `indent: 0` e o segundo deve terminar em `1`. No caso de redução, o primeiro começa em `0`, o segundo em `1` e o segundo deve terminar em `0`. Ler o resultado como `(document.getNodeById('node-2') as TaskNode).indent`.

Adaptar os helpers do teste para os construtores já usados no arquivo. Não criar uma nova fábrica de documento só para estes casos.

Executar:

```text
rtk flutter test test/features/notes/domain/note_editor_commands_test.dart --plain-name "selected task"
```

O teste deve falhar porque os métodos novos ainda não existem.

#### 3.2 Implementar a API nova

Em `note_editor_commands.dart`:

- Renomear para:

  ```dart
  static void indentSelectedBlocks(Editor editor, DocumentComposer composer);
  static void unindentSelectedBlocks(Editor editor, DocumentComposer composer);
  ```

- Manter o fluxo atual de obter `_selectedEditableNodes` e retornar cedo quando não houver requests.
- Para cada `ListItemNode`, criar `IndentListItemRequest(nodeId: node.id)` ou `UnIndentListItemRequest(nodeId: node.id)`.
- Para cada `TaskNode`, criar `IndentTaskRequest(node.id)` ou `UnIndentTaskRequest(node.id)`.
- Ignorar parágrafos e outros nós sem criar requests.
- Executar todas as requests em uma única chamada de `editor.execute(...)`, preservando a seleção múltipla atual.
- Remover os métodos antigos; não manter aliases.
- Atualizar os comentários para dizer que os métodos operam sobre blocos indentáveis, não somente sobre listas.

#### 3.3 Executar a suíte de comandos

```text
rtk flutter test test/features/notes/domain/note_editor_commands_test.dart
```

O resultado deve cobrir os casos antigos de listas e os novos casos de tasks.

#### 3.4 Confirmar que o contrato do documento não mudou

```text
rtk flutter test test/features/notes/domain/ot_document_codec_test.dart test/features/notes/domain/editor_operation_capture_test.dart
```

Esses testes devem continuar passando sem qualquer alteração no codec ou na captura.

#### 3.5 Commit da tarefa

```text
git add lib/features/notes/editor/document/note_editor_commands.dart test/features/notes/domain/note_editor_commands_test.dart
git commit -m "feat(editor): indent selected lists and tasks"
```

### Tarefa 4 — Expor a indentação de tasks na toolbar

**Arquivos:**

- Alterar `lib/features/notes/editor/presentation/widgets/note_toolbar.dart`.
- Alterar `lib/features/notes/editor/presentation/widgets/note_toolbar_menus.dart`.
- Alterar `test/features/notes/presentation/widgets/note_toolbar_test.dart`.

#### 4.1 Escrever os testes que devem falhar

Adicionar ao teste da toolbar:

- task selecionada exibe `format_indent_increase` e `format_indent_decrease`;
- tocar em `format_indent_increase` aumenta o indent da task selecionada;
- tocar em `format_indent_decrease` reduz o indent da task selecionada;
- parágrafo selecionado continua sem os botões;
- seleção múltipla contendo tasks continua usando uma única execução dos comandos.

Usar o harness existente de `note_toolbar_test.dart`, adicionando `CustomTaskComponentBuilder` somente se o documento de teste precisar ser renderizado para localizar a seleção. Não criar outro harness global.

Executar:

```text
rtk flutter test test/features/notes/presentation/widgets/note_toolbar_test.dart --plain-name "task"
```

Os testes novos devem falhar porque a toolbar hoje identifica somente `ListItemNode` e chama os métodos antigos.

#### 4.2 Implementar a integração

Em `note_toolbar.dart`:

- Trocar a condição de `isListItem` por uma condição que retorne `true` quando `formattingNodes` contiver `ListItemNode` ou `TaskNode`.
- Renomear os callbacks privados para `_indentSelectedBlocks` e `_unindentSelectedBlocks`.
- Fazer esses callbacks chamar `NoteEditorCommands.indentSelectedBlocks` e `NoteEditorCommands.unindentSelectedBlocks`.
- Manter `_prepareEditorAction`, o feedback háptico e o tratamento de seleção existentes.

Em `note_toolbar_menus.dart`:

- Renomear o parâmetro/campo `isListItem` para `isIndentableBlock`.
- Usar `isIndentableBlock` somente para controlar a presença dos dois botões.
- Manter ícones, tooltips, ordem, `ToolbarDivider` e callbacks.

#### 4.3 Executar os testes

```text
rtk flutter test test/features/notes/presentation/widgets/note_toolbar_test.dart
```

O resultado deve provar que listas e tasks exibem os mesmos controles, enquanto parágrafos não exibem controles de indentação.

#### 4.4 Commit da tarefa

```text
git add lib/features/notes/editor/presentation/widgets/note_toolbar.dart lib/features/notes/editor/presentation/widgets/note_toolbar_menus.dart test/features/notes/presentation/widgets/note_toolbar_test.dart
git commit -m "feat(editor): expose task indentation in toolbar"
```

### Tarefa 5 — Validar o fluxo completo e revisar o diff

**Arquivos:**

- Nenhum arquivo novo nesta tarefa.

#### 5.1 Executar análise estática

```text
rtk dart analyze lib/features/notes/editor/presentation/widgets/custom_list_item_component.dart lib/features/notes/editor/presentation/widgets/custom_task_component.dart lib/features/notes/editor/presentation/widgets/note_editor.dart lib/features/notes/editor/presentation/widgets/note_toolbar.dart lib/features/notes/editor/presentation/widgets/note_toolbar_menus.dart lib/features/notes/editor/document/note_editor_commands.dart test/features/notes/domain/note_editor_commands_test.dart test/features/notes/presentation/widgets/custom_list_item_component_test.dart test/features/notes/presentation/widgets/note_toolbar_test.dart
```

Corrigir todos os erros e warnings introduzidos antes de seguir.

#### 5.2 Executar os testes focados

```text
rtk flutter test test/features/notes/domain/note_editor_commands_test.dart test/features/notes/presentation/widgets/custom_list_item_component_test.dart test/features/notes/presentation/widgets/note_toolbar_test.dart test/features/notes/domain/ot_document_codec_test.dart test/features/notes/domain/editor_operation_capture_test.dart
```

#### 5.3 Executar a suíte Flutter

```text
rtk flutter test
```

Se houver falha fora dos arquivos alterados, registrar o teste, a mensagem e se a falha já estava presente. Não mascarar falhas com novos fallbacks.

#### 5.4 Fazer a inspeção visual mínima

Abrir uma nota com esta sequência:

1. parágrafo;
2. bullet no nível zero;
3. bullet no nível um;
4. lista numerada no nível zero;
5. task no nível zero;
6. task no nível um.

Confirmar que os marcadores do nível zero começam na borda do parágrafo, que cada `Tab` desloca uma unidade, que `Shift+Tab` e `Backspace` reduzem o nível conforme o Super Editor, e que os quatro botões da toolbar mantêm o mesmo comportamento.

#### 5.5 Revisar o diff e o estado do worktree

```text
rtk git diff --check
rtk git status --short
rtk git diff --stat
```

Confirmar que o diff contém somente o builder local, o ajuste de task, a generalização dos comandos, a toolbar e os testes correspondentes. Preservar arquivos sujos não relacionados.

## Critérios de aceite

- Bullet e lista numerada no nível zero começam na mesma borda horizontal de um parágrafo.
- Task no nível zero usa a mesma borda de conteúdo e mantém o pequeno inset interno do checkbox.
- Cada aumento de nível desloca marcador e texto por exatamente uma unidade `U`.
- `Tab`, `Shift+Tab` e `Backspace` continuam usando as ações padrão do Super Editor.
- Os botões de aumentar/reduzir indent aparecem para `ListItemNode` e `TaskNode`.
- A toolbar altera o documento por `EditRequest`; não há escrita direta na tabela `tasks`.
- Listas, tasks, codec, captura OT, projeção e sincronização continuam cobertos pelos testes existentes.
- `dart analyze`, os testes focados e `flutter test` passam, ou qualquer falha preexistente é reportada com evidência.

## Revisão do plano

- A solução não depende de alterar apenas o stylesheet: a posição do marcador é controlada pelo componente, por isso o builder local é necessário.
- A solução não mantém fork da biblioteca: reutiliza os componentes oficiais e altera somente os pontos públicos de geometria.
- O plano cobre apresentação, teclado, toolbar, comandos, testes de documento e validação final.
- Não há caminho de compatibilidade, migração ou abstração especulativa.
