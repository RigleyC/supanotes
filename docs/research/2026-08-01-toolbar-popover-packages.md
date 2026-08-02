# Pesquisa: popover fluido para a toolbar

Data: 2026-08-01

## Conclusão

Para o SupaNotes, a melhor composição é:

1. `OverlayPortal` + `CompositedTransformTarget`/`CompositedTransformFollower` para ancorar o menu ao ícone.
2. `motor`, que já existe no projeto, para a mola de abertura, fechamento e mudança de posição.
3. Um componente interno de superfície glass, usando o `BackdropFilter` que a toolbar já usa.
4. Um protótipo isolado com `liquid_glass_widgets` para avaliar se o `GlassMenu` entrega valor suficiente para justificar uma dependência nova.

Não recomendo adicionar um pacote de popover e um pacote de glass antes de testar essa composição. O comportamento é específico: o menu nasce no botão, sobe, muda de tamanho e mantém o vínculo visual com a toolbar. Um pacote de popover resolve posicionamento e dismissal; ele não resolve sozinho o morph líquido.

## Pacotes e APIs avaliados

| Opção | O que resolve | Avaliação para o SupaNotes |
|---|---|---|
| Flutter `OverlayPortal` | Insere o overlay sem ele sobreviver ao widget de origem e preserva a árvore de `InheritedWidget`s da origem. | Melhor base para o ciclo de vida do menu. [Docs](https://api.flutter.dev/flutter/widgets/OverlayPortal-class.html) |
| Flutter `CompositedTransformFollower` | Mantém o painel alinhado ao `LayerLink` do botão e acompanha mudanças de layout. | Melhor base para ancoragem. Exige `CompositedTransformTarget` correspondente e cuidado com hit testing. [Docs](https://api.flutter.dev/flutter/widgets/CompositedTransformFollower-class.html) |
| Flutter `MenuAnchor` | Menu ancorado nativo, children customizados, dismissal externo e animação básica. | Bom fallback funcional, mas o visual e a transição padrão ficam distantes da referência. [Docs](https://api.flutter.dev/flutter/material/MenuAnchor-class.html) |
| `popover` `0.4.0` | Popover cross-platform, seta, direção, barrier, escala e `popoverTransitionBuilder`; tem apenas dependência do Flutter e cerca de 40 mil downloads. | Melhor pacote para um primeiro spike funcional. Não usaria como núcleo do morph final. [Pub.dev](https://pub.dev/packages/popover) · [API](https://pub.dev/documentation/popover/latest/popover/) |
| `animated_to` `0.8.1` | Anima a posição renderizada de um widget quando ela muda; inclui mola, origem inicial e `AnimatedToBoundary`. | Útil para uma transição de posição ou para menus reordenáveis. Não é um sistema de popover nem de morph de tamanho. Tem limitações com slivers e hit testing durante a animação. [Docs](https://pub.dev/documentation/animated_to/latest/index.html) |
| `motor` `1.1.0` | API unificada para curvas e molas, incluindo presets `CupertinoMotion` e animação de `Offset`, `Size` e `Rect`. | Recomendado. Já está no `pubspec.yaml` e aparece em outro componente do app. [Docs](https://pub.dev/documentation/motor/latest/) |
| `liquid_glass_widgets` `0.27.0` | Glass shader, blur, refração, acessibilidade e `GlassMenu` com motor de morph próprio. | Melhor referência visual e candidato a protótipo. A versão subiu várias vezes durante a pesquisa e o publisher foi registrado há poucos dias; é cedo para acoplar o editor a ela. [Pub.dev](https://pub.dev/packages/liquid_glass_widgets) · [motor de morph](https://github.com/sdegenaar/liquid_glass_widgets/blob/main/docs/LIQUID_MORPH_ENGINE.md) |
| `flutter_liquid_glass`, `liquid_glass_flutter`, `liquid_glass_kit` e similares | Variações de glassmorphism, blur e shaders. | Não recomendo agora: há pouca adoção, APIs recentes ou limitações declaradas. Em particular, `liquid_glass_flutter` declara que o blur customizado ainda não está conectado. [Pacote](https://pub.dev/packages/liquid_glass_flutter) |

## O que eu faria

### Fase 1: spike visual sem alterar a toolbar

Criar uma tela de demonstração ou widget de teste com três estados:

- fechado: botão integrado à toolbar;
- abrindo: botão fantasma encolhe enquanto o painel sobe e cresce;
- aberto: painel glass com opções de bloco, como `None`, lista com marcadores, lista numerada e checklist.

O painel deve usar uma única ação `onSelected`, fechar antes de aplicar a operação e devolver o foco ao editor. A seleção continua sendo aplicada pelos comandos existentes do editor; o popover não escreve no documento diretamente.

### Fase 2: componente de produção

Criar um componente dedicado, por exemplo `ToolbarPopoverButton`, composto por:

- `CompositedTransformTarget` no botão;
- `OverlayPortal` para o conteúdo e o detector de toque externo;
- `CompositedTransformFollower` para a posição inicial e o acompanhamento do anchor;
- `motor` para animar `Rect`/`Offset`, escala e opacidade;
- `ClipRRect` + `BackdropFilter` + borda e sombra do tema atual;
- fallback sem blur quando `MediaQuery.disableAnimations` ou uma preferência de transparência reduzida estiver ativa.

O painel deve calcular a posição acima ou abaixo do botão conforme o espaço disponível. A largura deve ser estável para evitar que o conteúdo salte durante a abertura. Em telas estreitas, ele deve respeitar as margens da janela e não depender de coordenadas fixas.

### Fase 3: decisão sobre pacote glass

Testar `liquid_glass_widgets` apenas em um branch ou exemplo local. Medir no iPhone e em desktop:

- primeiro frame após abrir;
- raster time durante abertura e fechamento;
- scroll do editor com o menu aberto;
- redução de movimento/transparência;
- comportamento após rotação, teclado e mudança de janela;
- acessibilidade e hit testing.

Se o ganho visual não compensar o setup global (`initialize`, `wrap`, temas e pipeline shader), manter o glass interno. Se compensar, encapsular o pacote atrás de um widget do SupaNotes para não espalhar tipos externos pela toolbar.

## Decisão resumida

- **Agora:** usar `motor` + APIs nativas de overlay + o glass existente.
- **Para validar rapidamente:** `popover`.
- **Para estudar o efeito exato:** `liquid_glass_widgets`, como experimento controlado.
- **Não usar como solução principal:** `animated_to` sozinho ou pacotes pequenos de liquid glass sem histórico suficiente.

## Estado atual do repositório

- Flutter `3.44.1` e Dart `3.12.1`.
- `motor: ^1.1.0` já está em `pubspec.yaml`.
- A toolbar existente em `lib/features/notes/editor/presentation/widgets/note_toolbar.dart` já usa `BackdropFilter`, `AnimatedSize` e `AnimatedOpacity`.
- A toolbar envia operações por `NoteEditorCommands`; o novo popover deve preservar esse limite.

## Fontes primárias

- [Flutter `OverlayPortal`](https://api.flutter.dev/flutter/widgets/OverlayPortal-class.html)
- [Flutter `CompositedTransformFollower`](https://api.flutter.dev/flutter/widgets/CompositedTransformFollower-class.html)
- [Flutter `MenuAnchor`](https://api.flutter.dev/flutter/material/MenuAnchor-class.html)
- [`popover` no pub.dev](https://pub.dev/packages/popover)
- [`animated_to` na documentação](https://pub.dev/documentation/animated_to/latest/index.html)
- [`motor` na documentação](https://pub.dev/documentation/motor/latest/)
- [`liquid_glass_widgets` no pub.dev](https://pub.dev/packages/liquid_glass_widgets)
- [Documentação do Liquid Morph Engine](https://github.com/sdegenaar/liquid_glass_widgets/blob/main/docs/LIQUID_MORPH_ENGINE.md)
