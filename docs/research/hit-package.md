# Pesquisa: package `hit`

Data da pesquisa: 2026-08-04
Escopo: fontes primárias e leitura somente do código de `C:\Users\rigleyc\projects\supanotes`.

## Conclusão executiva

`hit` é plausível para melhorar controles que precisam parecer pequenos, mas devem ter uma área de interação maior. A melhor oportunidade encontrada é `ResizeDragHandle`, que tem apenas 6 px de largura visual e usa `GestureDetector` para arrastar. A segunda oportunidade é o `_ToolbarButton` compacto: hoje ele usa mínimo de 36×36 px quando não está no modo espaçoso, enquanto o pacote pode manter o desenho pequeno e oferecer uma área de hit de 44×44 px.

Não recomendo adicionar o pacote apenas para os demais controles auditados. Muitos já usam `IconButton`, têm dimensões visuais de 44 px ou mais, ou já têm uma área de toque suficientemente ampla. Também não há evidência, nesta leitura, de que `hit` resolva gestos dentro do `SuperEditor`; ele trata o hit-test de widgets Flutter e exige um `HitScope` que cubra fisicamente a área expandida.

**Recomendação:** avaliar um spike isolado em `ResizeDragHandle`, com teste de arrasto nos quatro lados do handle e verificação em desktop e touch. Se o comportamento for estável, avaliar a toolbar compacta. Não incluir `hit` como mudança transversal sem esses testes.

## O que o pacote é

### Fatos confirmados nas fontes

- A versão mostrada no pub.dev durante a pesquisa é `1.2.0`; o pacote é publicado por `zennn.dev`, tem publisher verificado, licença MIT e apenas `flutter` como dependência direta. Fonte: [página do pacote no pub.dev](https://pub.dev/packages/hit).
- O objetivo declarado é separar o tamanho de paint/layout do tamanho usado no hit-test e entregar taps que caem fora dos limites de layout do widget. Fonte: [README oficial](https://github.com/definev/hit/blob/main/README.md).
- A API pública exporta `HitLayer`, `HitScope`, `SliverHitScope`, `HitDefer`, `HitDeferPaint`, `HitLink` e os tipos de suporte. Fonte: [arquivo público `lib/hit.dart`](https://github.com/definev/hit/blob/main/lib/hit.dart).
- `HitLayer` recebe `paintChild` e, opcionalmente, `hitChild`. O layout segue `paintChild`; `hitChild` pode ser maior e é alinhado ao redor do conteúdo visual. Fonte: [implementação de `HitLayer`](https://github.com/definev/hit/blob/main/lib/src/hit_layer.dart).
- Quando a área de hit excede o layout, é necessário um `HitScope` ancestral — ou um `HitLink` explícito — cuja caixa de layout cubra a área expandida. Um `HitScope` apertado, um `ClipRect` acima dele ou um ancestral com caixa menor impede que o evento chegue ao escopo. Fonte: [README, seção de troubleshooting](https://github.com/definev/hit/blob/main/README.md).
- `SliverHitScope` existe para subárvores em `CustomScrollView`; ele não é um wrapper de box comum. Fonte: [README, seção `SliverHitScope`](https://github.com/definev/hit/blob/main/README.md).
- O pacote registra alvos somente quando há overflow. O hit-test diferido percorre os alvos registrados em `O(n)`; a documentação recomenda escopos pequenos e poucos alvos diferidos. Fonte: [README, notas de performance](https://github.com/definev/hit/blob/main/README.md) e [implementação de `HitLayer`](https://github.com/definev/hit/blob/main/lib/src/hit_layer.dart).
- A versão `1.2.0` tem mudança incompatível na API em relação à série `1.1.x`, incluindo a substituição de APIs antigas por `HitDefer` e `HitDeferPaint`. Fonte: [README, migração para 1.2.0](https://github.com/definev/hit/blob/main/README.md).
- O repositório mantém testes próprios para layers, escopos, slivers, semântica, texto rico e performance de overflow. Isso é evidência de que o autor considera esses cenários parte da superfície relevante, mas não prova compatibilidade específica com o SupaNotes. Fonte: [diretório oficial de testes](https://github.com/definev/hit/tree/main/test).

### Inferências para o SupaNotes

- O pacote pode melhorar acessibilidade e tolerância de interação quando aumentar padding real mudaria alinhamento, densidade ou largura de componentes.
- O pacote não substitui semântica, foco, cursor, teclado ou contratos de negócio. `Semantics`, `Focus`, callbacks e operações do SupaNotes continuam necessários.
- Como a área expandida deve estar dentro da caixa de um ancestral, o ganho é mais seguro em um painel/linha que já tenha espaço ao redor do controle. Ele não permite receber eventos através de um `ClipRect` ou fora do viewport.

## Leitura do código do SupaNotes

Esta seção registra fatos observados no código local e a inferência de integração. Nenhum arquivo de código foi alterado.

| Prioridade | Ponto | Evidência local | Integração plausível | Risco / condição |
|---|---|---|---|---|
| Alta | Divisor lateral redimensionável | [`resize_drag_handle.dart`](../../lib/features/notes/catalog/presentation/widgets/resize_drag_handle.dart) cria `MouseRegion` + `GestureDetector`, com `width: 6` e `onHorizontalDragUpdate`. | Usar `HitLayer`: manter um `paintChild` visual de 6 px e fornecer um `hitChild` mais largo, por exemplo 44 px, com o mesmo drag callback. Colocar `HitScope` no ancestral que cobre o divisor e o espaço expandido. | É o caso mais claro de separação entre visual e interação. Deve validar não capturar cliques da lista/sidebar vizinha, manter o cursor correto e funcionar com mouse, touch e drag contínuo. |
| Média | Botões compactos da toolbar | [`note_toolbar_button.dart`](../../lib/features/notes/editor/presentation/widgets/note_toolbar_button.dart) usa mínimo 44×44 no modo espaçoso, mas 36×36 no modo compacto; o ícone visual é 24–28 px. | Para o modo compacto, manter o botão visual/ocupação compacta e usar `HitLayer` com um `hitChild` de 44×44, preservando `Semantics` e `InkWell`/callback. Um `HitScope` deve envolver a faixa da toolbar, com atenção a controles adjacentes. | A área expandida pode sobrepor botões vizinhos. O comportamento de seleção, tap outside, teclado e foco precisa continuar igual; pode ser melhor aumentar o alvo localmente se a densidade não for um problema. |
| Baixa | Ações de anexos | [`attachment_renderers.dart`](../../lib/features/notes/editor/presentation/widgets/attachment_renderers.dart) usa `IconButton` para cancelar/remover e caixas visuais de 44×44 para outros ícones. | Em princípio, não usar `hit` aqui. Só considerar se uma inspeção visual/semântica demonstrar que o `IconButton` efetivo está menor que o alvo esperado. | Risco de duplicar a área de toque que o Material já fornece e criar sobreposição com o texto/pill. |
| Baixa | Checkbox de tarefa no editor | [`custom_task_component.dart`](../../lib/features/notes/editor/presentation/widgets/custom_task_component.dart) já reserva `_taskCheckboxTouchTarget`, usa `Semantics` e `HitTestBehavior.opaque`; o checkbox compartilhado também tem contrato próprio. | Não usar `hit` como primeira opção. O alvo já é explicitamente reservado e o fluxo tem estado de sincronização, semântica e callback próprios. | Trocar o hit-test pode quebrar seleção/long press do editor ou criar duas regiões concorrentes. |
| Baixa | Linhas e cards de notas | [`note_list_row.dart`](../../lib/features/notes/catalog/presentation/widgets/note_list_row.dart) usa uma linha inteira com `InkWell` dentro de `Dismissible`; [`note_card.dart`](../../lib/features/notes/catalog/presentation/widgets/note_card.dart) também usa área de card para tap. | Não há necessidade evidente de expandir um ícone isolado. O pacote só seria relevante para uma futura ação visualmente flutuante, como um botão pequeno fora do card. | `Dismissible`, menu contextual e tap da linha já competem por gestos; uma região diferida pode alterar a prioridade desses gestos. |
| Baixa | Botões do cabeçalho/sidebar | [`notes_sidebar.dart`](../../lib/features/notes/catalog/presentation/widgets/notes_sidebar.dart) usa `IconButton` para nova nota e configurações. | Não usar sem evidência de alvo insuficiente. | `IconButton` já é o componente apropriado para o alvo; expandir por fora pode atingir áreas vizinhas do sidebar. |

## Como seria a integração recomendada

Isto é uma proposta de investigação, não uma alteração aplicada.

1. Adicionar `HitScope` no nível mínimo que cubra o divisor ou a faixa da toolbar. Não usar um `HitScope` global.
2. Para o controle escolhido, separar explicitamente o widget visual (`paintChild`) do widget de interação (`hitChild`). O `hitChild` deve ser superficial e conter o `GestureDetector`/`InkWell` existente.
3. Usar `HitTestBehavior` e `IgnorePointer` de forma deliberada para evitar que o desenho visual receba o gesto duas vezes. O README do pacote recomenda `deferToChild`/`opaque` quando não é necessário produzir hits duplos.
4. Preservar `MouseRegion`, `Semantics`, foco e callbacks existentes. O pacote não deve receber responsabilidade de estado, navegação ou operações de nota.
5. Criar testes widget que toquem/arrastem nas bordas da nova área e também verifiquem que um controle vizinho não é acionado. Para a toolbar, repetir testes de semântica, `Escape`, tap outside e foco existentes.

## Limitações e decisão

- O pacote é novo no pub.dev: a página consultada mostra publicação em agosto de 2026 e versão `1.2.0`. Isso aumenta a necessidade de fixar a versão escolhida e testar antes de adotar.
- A dependência direta é pequena, mas o comportamento depende de render objects e de detalhes do hit-test do Flutter. Uma atualização do Flutter ou do pacote pode afetar o resultado sem alteração no código de negócio.
- Não há base para afirmar ganho de performance no SupaNotes. O próprio pacote documenta custo `O(n)` por escopo; a recomendação deve ser baseada em usabilidade e correção do alvo, não em uma promessa de performance.
- O relatório não recomenda incluir o package agora. Recomenda um spike de baixo escopo no `ResizeDragHandle`; só após evidência positiva avaliar o `_ToolbarButton` compacto.

## Fontes primárias

- [pub.dev: `hit`](https://pub.dev/packages/hit) — versão, publisher, licença, dependência e API/documentação vinculada.
- [GitHub: `definev/hit`](https://github.com/definev/hit) — repositório oficial.
- [README oficial](https://github.com/definev/hit/blob/main/README.md) — modelo mental, instalação, limitações, exemplos e performance.
- [API pública `lib/hit.dart`](https://github.com/definev/hit/blob/main/lib/hit.dart) — exports públicos.
- [Implementação `HitLayer`](https://github.com/definev/hit/blob/main/lib/src/hit_layer.dart) — layout, overflow, registro e hit-test.
- [Testes oficiais](https://github.com/definev/hit/tree/main/test) — cobertura declarada pelo repositório para a superfície do pacote.

## Nota sobre fatos e inferências

Os itens sob “Fatos confirmados nas fontes” descrevem informação diretamente publicada no pub.dev ou no repositório oficial. Os itens sob “Inferências para o SupaNotes”, a coluna “Integração plausível” e a recomendação final são análise baseada nessa documentação e na leitura do código local; não representam comportamento já implementado nem compatibilidade garantida.
