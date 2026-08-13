# Pesquisa documental: indentação de listas no Super Editor

Data da pesquisa: 2026-08-13.

Escopo: documentação oficial do Super Editor e o checkout local em
`C:\Users\rigleyc\AppData\Local\Pub\Cache\git\super_editor-3bb857bc423240b61dc0fb799f3c269e71feb24a\super_editor`.

## Conclusão curta

Sim. `ListItemNode` e `TaskNode` guardam o nível semântico em um campo inteiro
`indent`. O nível raiz é `0`; aumentar ou reduzir esse inteiro altera a
hierarquia. A posição visual do marcador, checkbox e texto é calculada pelos
componentes. Portanto, é possível alinhar visualmente a lista ao parágrafo sem
trocar o tipo do nó, inserir espaços no texto ou alterar a semântica.

## 1. Como os nós armazenam o nível

| Nó | Armazenamento | Evidência local |
| --- | --- | --- |
| `ListItemNode` | `final int indent`, com valor padrão `0`. `type` (ordered/unordered) é outro campo. `copyListItemWith` preserva ou substitui `indent`. | `lib/src/default_editor/list_items.dart:25-80` |
| `TaskNode` | `final int indent`, com valor padrão `0`. O tipo `task` também é registrado no metadata de bloco, mas o nível fica no campo `indent`. `copyTaskWith` preserva ou substitui o nível. | `lib/src/default_editor/tasks.dart:40-80` |

A documentação de `TaskNode` define `0` como “no indent” e limita uma task a
um nível além da task pai. O checkout local aplica essa regra durante as
operações de indentação.

O projeto também já exercita a persistência desses campos no codec: uma lista
com `indent: 2` e uma task com `indent: 3` aparecem no teste de round-trip em
`test/features/notes/domain/ot_document_codec_test.dart:357-378`.

Nota de versão: o checkout local declara `super_editor` `0.3.0-dev.52`
(`super_editor/pubspec.yaml:3`). A página estável mais recente do pub.dev é
`0.2.7`; por isso, as páginas de API abaixo usam explicitamente
`0.3.0-dev.52`, que contém `TaskNode.indent`:
[versões do pacote](https://pub.dev/packages/super_editor/versions),
[`ListItemNode`](https://pub.dev/documentation/super_editor/0.3.0-dev.52/super_editor/ListItemNode-class.html)
e [`TaskNode`](https://pub.dev/documentation/super_editor/0.3.0-dev.52/super_editor/TaskNode-class.html).

## 2. Operações e atalhos oficiais

### Listas ordered/unordered

- `CommonEditorOperations.indentListItem()` executa a indentação; `unindentListItem()` reduz o nível.
- As operações correspondem a `IndentListItemCommand` e `UnIndentListItemCommand`.
- O teclado padrão usa Tab para aumentar, Shift+Tab para reduzir e Backspace no início do item para reduzir. As mesmas ações aparecem na lista padrão de ações de teclado e IME.
- A implementação local limita o aumento a `indent < 6` (`lib/src/default_editor/list_items.dart:982-1006`). Ao reduzir um item raiz, `CommonEditorOperations.unindentListItem()` documenta a conversão para `ParagraphNode` (`lib/src/default_editor/common_editor_operations.dart:2149-2178`).

Fontes oficiais: [`CommonEditorOperations`](https://pub.dev/documentation/super_editor/0.3.0-dev.52/super_editor/CommonEditorOperations-class.html), [`defaultKeyboardActions`](https://pub.dev/documentation/super_editor/0.3.0-dev.52/super_editor/defaultKeyboardActions.html), [`tabToIndentListItem`](https://pub.dev/documentation/super_editor/0.3.0-dev.52/super_editor/tabToIndentListItem.html), [`shiftTabToUnIndentListItem`](https://pub.dev/documentation/super_editor/0.3.0-dev.52/super_editor/shiftTabToUnIndentListItem.html) e [`backspaceToUnIndentListItem`](https://pub.dev/documentation/super_editor/0.3.0-dev.52/super_editor/backspaceToUnIndentListItem.html).

### Tasks

- `IndentTaskCommand` e `UnIndentTaskCommand` aumentam/reduzem um nível.
- `SetTaskIndentCommand` aplica um nível explícito. `SetTaskIndentRequest` não valida o valor; o chamador deve validar a hierarquia.
- Tab aumenta somente quando o item anterior é uma `TaskNode`; o novo nível não pode exceder `previous.indent + 1`.
- Shift+Tab reduz. Backspace no início da task também reduz quando `indent > 0`.
- Ao reduzir uma task, a implementação local reduz em conjunto as subtasks contíguas mais profundas, preservando uma hierarquia válida (`lib/src/default_editor/tasks.dart:950-1068`).

Fontes oficiais: [`IndentTaskCommand`](https://pub.dev/documentation/super_editor/0.3.0-dev.52/super_editor/IndentTaskCommand-class.html), [`UnIndentTaskCommand`](https://pub.dev/documentation/super_editor/0.3.0-dev.52/super_editor/UnIndentTaskCommand-class.html), [`SetTaskIndentRequest`](https://pub.dev/documentation/super_editor/0.3.0-dev.52/super_editor/SetTaskIndentRequest-class.html), [`tabToIndentTask`](https://pub.dev/documentation/super_editor/0.3.0-dev.52/super_editor/tabToIndentTask.html), [`shiftTabToUnIndentTask`](https://pub.dev/documentation/super_editor/0.3.0-dev.52/super_editor/shiftTabToUnIndentTask.html) e [`backspaceToUnIndentTask`](https://pub.dev/documentation/super_editor/0.3.0-dev.52/super_editor/backspaceToUnIndentTask.html).

## 3. Como a distância visual é calculada

O cálculo padrão usa a unidade:

```text
U = (fontSize * 0.60) * 4
```

| Componente | Espaço variável antes do texto | Evidência local |
| --- | --- | --- |
| Parágrafo | `U * indent` | `lib/src/default_editor/paragraph.dart:501-504` |
| Bullet ou número | `U * (indent + 1)` | `lib/src/default_editor/list_items.dart:581-616`, `763-795`, `821-824` |
| Task | `U * indent`, seguido do espaçamento fixo do checkbox (`left: 16`, `right: 4`) | `lib/src/default_editor/tasks.dart:319-322`, `369-389` |

Nos bullets e números, o componente coloca essa largura em um `Container` e
renderiza o texto em um `Expanded`. A coluna inclui o marcador. O estilo do
bullet pode mudar por `dotColor`, `dotShape` e `dotSize`; o número usa
`listNumeralStyle` (`lib/src/default_editor/list_items.dart:350-360`,
`431-434`; `lib/src/core/styles.dart:331-404`).

Consequência importante: no nível raiz (`indent = 0`), parágrafo e task não têm
espaço variável de indentação, mas bullet/número reservam uma unidade `U` para
a coluna do marcador. Assim, o texto de uma lista não começa no mesmo `x` do
parágrafo por padrão. Isso é uma diferença de layout, não uma diferença no
modelo semântico.

Fontes oficiais: [`defaultListItemIndentCalculator`](https://pub.dev/documentation/super_editor/0.3.0-dev.52/super_editor/defaultListItemIndentCalculator.html), [`defaultTaskIndentCalculator`](https://pub.dev/documentation/super_editor/0.3.0-dev.52/super_editor/defaultTaskIndentCalculator.html) e [`style a document`](https://supereditor.dev/super-editor/guides/styling/style-a-document/).

## 4. Forma recomendada de customizar a aparência

A recomendação oficial é manter os nós e customizar a apresentação:

1. Para cor, tamanho, forma, estilo do numeral e padding, estender `defaultStylesheet` com `defaultStylesheet.copyWith(addRulesAfter: [...])`. Os guias oficiais de [listas](https://supereditor.dev/super-editor/guides/built-in-content/list-items/) e [tasks](https://supereditor.dev/super-editor/guides/built-in-content/tasks/) apontam o stylesheet como o ajuste mais simples.
2. Para alterar a geometria horizontal — por exemplo, remover a unidade extra do marcador raiz — usar um `componentBuilder`/componente visual customizado. O componente deve continuar recebendo `indent` e calcular somente a posição visual. O checkout expõe `indentCalculator` nos componentes de lista e no `TaskComponentViewModel` (`list_items.dart:515-553`, `695-735`; `tasks.dart:204-249`).
3. Não representar o nível com espaços, caracteres `•`/`1.` no texto ou metadata paralelo. Isso quebra seleção, atalhos, projeção e persistência do documento.

Para o SupaNotes, a recomendação documental é: manter `indent = 0` na raiz e
usar as operações oficiais para mudar níveis; se o requisito for alinhar o
texto raiz da lista ao parágrafo, alterar apenas a coluna visual do componente
customizado. O documento REST/OT continua com `ListItemNode`/`TaskNode` e o
mesmo `indent`.

## Fontes locais consultadas

- Checkout: `C:\Users\rigleyc\AppData\Local\Pub\Cache\git\super_editor-3bb857bc423240b61dc0fb799f3c269e71feb24a\super_editor`, commit `3bb857bc423240b61dc0fb799f3c269e71feb24a`.
- Listas: `lib/src/default_editor/list_items.dart` e `lib/src/default_editor/common_editor_operations.dart`.
- Tasks: `lib/src/default_editor/tasks.dart`.
- Indentação de blocos: `lib/src/default_editor/blocks/indentation.dart`.
- Estilos: `lib/src/core/styles.dart`.
- Integração do projeto: `pubspec.yaml:21-25`.

## Fontes oficiais consultadas

- [Super Editor — list items](https://supereditor.dev/super-editor/guides/built-in-content/list-items/)
- [Super Editor — tasks](https://supereditor.dev/super-editor/guides/built-in-content/tasks/)
- [Super Editor — style a document](https://supereditor.dev/super-editor/guides/styling/style-a-document/)
- [Super Editor no pub.dev — versões](https://pub.dev/packages/super_editor/versions)
- [API `defaultKeyboardActions`](https://pub.dev/documentation/super_editor/0.3.0-dev.52/super_editor/defaultKeyboardActions.html)
- [API `defaultListItemIndentCalculator`](https://pub.dev/documentation/super_editor/0.3.0-dev.52/super_editor/defaultListItemIndentCalculator.html)
- [API `defaultTaskIndentCalculator`](https://pub.dev/documentation/super_editor/0.3.0-dev.52/super_editor/defaultTaskIndentCalculator.html)
