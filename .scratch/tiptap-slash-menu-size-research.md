# Tiptap slash menu: pesquisa de dimensões

Data da pesquisa: 2026-08-07  
Escopo: somente documentação oficial do Tiptap e o repositório oficial `ueberdosis/tiptap-ui-components`.  
Commit do repositório consultado: [`799929b`](https://github.com/ueberdosis/tiptap-ui-components/tree/799929bea4804c73767562b69f8acc2acdb8ac86)

## Conclusão curta

O Tiptap documenta o comportamento e o limite de altura do menu, mas não publica uma especificação completa de dimensões para o slash item. A recomendação oficial mais precisa disponível para o menu é:

- altura máxima: **384 px**;
- card com `CardBody` de **6 px** de padding;
- label de grupo: **12 px**, peso **600**, com **12 px** acima, **8 px** nas laterais e **4 px** abaixo;
- card: borda de **1 px** e raio calculado de **18 px** com a escala padrão de 16 px;
- sombra: token `--tt-shadow-elevated-md`, detalhado abaixo;
- largura, altura mínima, altura da linha do item e tamanho do ícone do slash menu: **não documentados**.

Os valores de 32 px para linha e 16 px para ícone abaixo são apenas uma **inferência de baseline** do primitive `Button`; não são uma especificação comprovada do slash menu.

## Valores documentados pelo Tiptap

| Propriedade | Valor | Classificação | Fonte |
|---|---:|---|---|
| Altura máxima do menu | **384 px** | Documentado como default de `SuggestionMenu` e como `--suggestion-menu-max-height` | [`Suggestion Menu`, props e CSS custom property](https://tiptap.dev/docs/ui-components/utils-components/suggestion-menu#props) |
| Overflow vertical | `overflow-y: auto` | Documentado no exemplo de estilo; o texto também diz que o menu rola quando excede o máximo | [`Suggestion Menu`, Styling](https://tiptap.dev/docs/ui-components/utils-components/suggestion-menu#styling) |
| Largura do card/menu | **Sem valor** | Não documentado | A documentação define `maxHeight`, mas não define `width`, `min-width` ou `max-width` ([props](https://tiptap.dev/docs/ui-components/utils-components/suggestion-menu#props)) |
| Altura mínima | **Sem valor** | Não documentado | Não há propriedade `minHeight`/`min-height` na documentação consultada |
| Altura da linha do slash item | **Sem valor** | Não documentado | `SuggestionItem` documenta dados (`title`, `subtext`, `badge`, `group`, `keywords`), não dimensões ([types](https://tiptap.dev/docs/ui-components/utils-components/suggestion-menu#types)) |
| Caixa do ícone/badge | **Sem valor** | Não documentado | `badge` é documentado como conteúdo de ícone/badge, sem tamanho ([`SuggestionItem`](https://tiptap.dev/docs/ui-components/utils-components/suggestion-menu#suggestionitem)) |
| Grupos | `group` opcional; labels são suportadas | Documentado | [`SuggestionItem`](https://tiptap.dev/docs/ui-components/utils-components/suggestion-menu#suggestionitem) e exemplo de agrupamento ([Grouped Items](https://tiptap.dev/docs/ui-components/utils-components/suggestion-menu#with-grouped-items)) |
| Mostrar labels de grupos no slash dropdown | `showGroups: true` por default | Documentado | [`SlashMenuConfig`](https://tiptap.dev/docs/ui-components/components/slash-dropdown-menu#configuration) |
| Raio no exemplo genérico de estilo | `8 px` | Documentado como exemplo, não como default | [Exemplo CSS do Suggestion Menu](https://tiptap.dev/docs/ui-components/utils-components/suggestion-menu#example-styling) |
| Sombra no exemplo genérico de estilo | `0 2 px 8 px rgba(0, 0, 0, 0.15)` | Documentado como exemplo, não como default | [Exemplo CSS do Suggestion Menu](https://tiptap.dev/docs/ui-components/utils-components/suggestion-menu#example-styling) |

> O exemplo da documentação aparece com espaços em `8 px`; ele deve ser tratado como exemplo visual, não como um token CSS normativo.

## Valores medidos ou calculados no source oficial

O source público atual contém o primitive `Card`, mas não contém arquivos `slash-dropdown-menu` ou `suggestion-menu`. O README avisa que o repositório pode não conter a versão mais recente dos componentes e recomenda instalar pelo CLI ([README oficial](https://github.com/ueberdosis/tiptap-ui-components#installation)). A árvore do commit consultado pode ser verificada pela [API oficial do GitHub](https://api.github.com/repos/ueberdosis/tiptap-ui-components/git/trees/799929bea4804c73767562b69f8acc2acdb8ac86?recursive=1).

### Card e grupos

Fonte: [`card.scss`](https://raw.githubusercontent.com/ueberdosis/tiptap-ui-components/799929bea4804c73767562b69f8acc2acdb8ac86/apps/web/src/components/tiptap-ui-primitive/card/card.scss).

| Propriedade | Source | Valor calculado | Classificação |
|---|---|---:|---|
| Padding interno do card | `--padding: 0.375rem` | **6 px** em uma raiz de 16 px | Inferido do CSS |
| Borda | `border: 1px solid ...` | **1 px** | Explícito no source |
| Raio do card | `calc(var(--padding) + var(--tt-radius-lg))` | **18 px** = 6 + 12 | Inferido do CSS; `--tt-radius-lg` é `0.75rem` / 12 px |
| Padding do `CardBody` | `padding: 0.375rem` | **6 px** em cada lado | Inferido do CSS |
| Gap de grupo vertical | Nenhum `gap` declarado | **Não definido** | Não inferir um espaçamento inexistente |
| Gap de grupo horizontal | `gap: 0.25rem` | **4 px** | Explícito/calculado do CSS; aplica somente a orientação horizontal |
| Label: padding-top | `0.75rem` | **12 px** | Inferido do CSS |
| Label: padding-left/right | `0.5rem` | **8 px** | Inferido do CSS |
| Label: padding-bottom | `0.25rem` | **4 px** | Inferido do CSS |
| Label: tamanho | `font-size: 0.75rem` | **12 px** | Inferido do CSS |
| Label: peso | `font-weight: 600` | **600** | Explícito no source |
| Label: line-height | `normal` | Dependente do navegador/fonte | Explícito, sem altura em px |
| Label: transformação | `text-transform: capitalize` | Capitalização | Explícito no source |

### Sombra e tokens de raio

Fonte: [`_variables.scss`](https://raw.githubusercontent.com/ueberdosis/tiptap-ui-components/799929bea4804c73767562b69f8acc2acdb8ac86/apps/web/src/styles/_variables.scss).

- `--tt-radius-lg: 0.75rem` (**12 px** no comentário do source).
- `--tt-shadow-elevated-md` no tema claro:

  ```css
  0px 16px 48px 0px rgba(17, 24, 39, 0.04),
  0px 12px 24px 0px rgba(17, 24, 39, 0.04),
  0px 6px 8px 0px rgba(17, 24, 39, 0.02),
  0px 2px 3px 0px rgba(17, 24, 39, 0.02)
  ```

- No tema escuro, o mesmo token é substituído por:

  ```css
  0px 16px 48px 0px rgba(0, 0, 0, 0.5),
  0px 12px 24px 0px rgba(0, 0, 0, 0.24),
  0px 6px 8px 0px rgba(0, 0, 0, 0.22),
  0px 2px 3px 0px rgba(0, 0, 0, 0.12)
  ```

O card usa esse token diretamente em `box-shadow: var(--tt-shadow-elevated-md)`. Portanto, a sombra acima é uma medida do primitive `Card`, mas ainda não prova que a implementação fechada/mais recente do slash dropdown usa exatamente esse card.

### Baseline do primitive Button — não é especificação do slash item

Fonte: [`button.scss`](https://raw.githubusercontent.com/ueberdosis/tiptap-ui-components/799929bea4804c73767562b69f8acc2acdb8ac86/apps/web/src/components/tiptap-ui-primitive/button/button.scss).

O primitive define estes valores úteis para comparação:

- altura padrão: **2 rem = 32 px**;
- largura mínima: **2 rem = 32 px**;
- padding: **0.5 rem = 8 px** em cada direção;
- gap entre conteúdo: **0.25 rem = 4 px**;
- ícone padrão: **1 rem = 16 px**;
- ícone grande: **1.125 rem = 18 px**;
- ícone pequeno: **0.875 rem = 14 px**.

Esses valores não devem ser chamados de “medidas do slash menu”: o source público consultado não mostra um `SuggestionItem` ou `SlashDropdownMenu` compondo esse botão.

### Preview oficial atual do SlashDropdownMenu

Além do repositório público, o preview oficial atual do componente foi consultado em [`template.tiptap.dev`](https://template.tiptap.dev/preview/tiptap-ui/slash-dropdown-menu). A implementação gerada compõe cada item com o primitive `Button`, mostrando o badge/ícone e o título em uma única linha. O CSS gerado usa a baseline do `Button` acima: **32 px** de altura, **8 px** de padding horizontal, **4 px** de gap e **16 px** de ícone.

No breakpoint desktop (`min-width: 480px`), o CSS gerado define `min-width: 15rem` para o card do slash menu, equivalente a **240 px**. Esse valor é uma referência do preview atual, não uma API documentada; por isso, o SupaNotes usa **256 px** como largura fixa compacta, preservando uma margem para labels longos sem voltar aos 300 px anteriores.

## Comportamento de filtro e teclado

| Comportamento | Especificação oficial |
|---|---|
| Abrir | Menu flutuante acionado por um caractere configurável; o slash dropdown usa `/` ([overview](https://tiptap.dev/docs/ui-components/components/slash-dropdown-menu)) |
| Filtrar | Digitação filtra os itens ([keyboard navigation](https://tiptap.dev/docs/ui-components/components/slash-dropdown-menu#keyboard-navigation)) |
| Campos pesquisados | `title`, `subtext` e `keywords` ([filterSuggestionItems](https://tiptap.dev/docs/ui-components/utils-components/suggestion-menu#filtering-logic)) |
| Comparação | Case-insensitive; matches exatos e por prefixo têm prioridade ([filtering logic](https://tiptap.dev/docs/ui-components/utils-components/suggestion-menu#filtering-logic)) |
| Query vazia | Retorna todos os itens ([filtering logic](https://tiptap.dev/docs/ui-components/utils-components/suggestion-menu#filtering-logic)) |
| Navegação | Arrow Up/Down navega; Enter seleciona; Escape fecha; Tab fecha e continua a digitação ([slash dropdown keyboard navigation](https://tiptap.dev/docs/ui-components/components/slash-dropdown-menu#keyboard-navigation)) |
| Acessibilidade | `role="listbox"`, `aria-label="Suggestions"`, navegação por setas/Enter/Escape e preservação do foco do editor ([accessibility](https://tiptap.dev/docs/ui-components/utils-components/suggestion-menu#accessibility)) |
| Altura dinâmica | A implementação deve rolar o conteúdo quando passar de 384 px ([props](https://tiptap.dev/docs/ui-components/utils-components/suggestion-menu#props)) |

## Implicação para a comparação com o SupaNotes

Para uma comparação fiel, usar **384 px como teto**, **6 px de padding do card**, **12/8/4 px no label**, **1 px de borda**, raio calculado do `Card` e a sombra do token. Para linha e ícone, **32 px / 16 px são apenas uma hipótese baseada no Button primitive**; o relatório não encontrou uma medida oficial do slash item para justificar esses valores como obrigatórios.
