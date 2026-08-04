# Pesquisa: comportamento da toolbar do Apple Notes

Data: 2026-08-02

## Escopo e limite da evidência

Esta pesquisa usa documentação oficial da Apple e as diretrizes oficiais de Human Interface Guidelines. A documentação descreve os comandos e as regras de interação, mas não documenta cada detalhe visual da implementação interna da toolbar do Notes. A separação entre fato documentado e inferência de UX está indicada abaixo.

## Comportamentos documentados

### 1. A barra principal é compacta e contextual

No iPhone, a Apple recomenda incluir na área principal da toolbar apenas os itens mais importantes, devido ao espaço limitado, e mover ações adicionais para um menu More. A toolbar deve atuar sobre o conteúdo visível, não funcionar como uma navegação paralela.

Fonte: [HIG — Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars).

No Notes, a escrita começa diretamente no corpo da nota. A primeira linha vira o título. Ações de formatação, checklist e tabela são acionadas durante a edição.

Fonte: [Apple — Create and format notes on iPad](https://support.apple.com/pt-br/guide/ipad/ipad99e3f0bb/ipados).

### 2. Formatação é um grupo de comandos relacionados

O botão de formatação abre estilos como título/cabeçalho, negrito, itálico, destaque e outras opções. Quando existe texto selecionado, a mesma entrada expõe opções inline. A Apple também documenta o toque longo no botão de formatação como atalho para abrir rapidamente as opções.

Fonte: [Apple — Use Notes on your iPhone](https://support.apple.com/en-us/118442).

Inferência de UX: o botão de formatação funciona como um agrupador estável; o conteúdo do agrupador muda conforme a seleção, em vez de a toolbar ficar cheia com todos os comandos visíveis ao mesmo tempo.

### 3. Lista, checklist e tabela são ações diferentes

O Notes oferece checklist e tabela como ações próprias. A documentação também menciona título, cabeçalho e lista com marcadores dentro do fluxo de formatação. A checklist é um tipo de conteúdo que o usuário pode marcar e desmarcar.

Fonte: [Apple — Create and format notes on iPad](https://support.apple.com/pt-br/guide/ipad/ipad99e3f0bb/ipados).

### 4. Anexos usam um menu de captura/importação

O botão de anexos abre opções como escolher foto/vídeo, tirar foto/vídeo, escanear texto, escanear documentos, anexar arquivos e gravar áudio. O documento escaneado é salvo como PDF na nota. A gravação de áudio pode gerar transcrição pesquisável e o texto pode ser adicionado à nota.

Fontes: [Apple — Add photos, video, and more](https://support.apple.com/guide/iphone/add-photos-video-and-more-iph23f4d9aa9/ios), [Apple — Scan text and documents](https://support.apple.com/en-ie/guide/iphone/iph653f28965/ios), [Apple — Record and transcribe audio](https://support.apple.com/en-mide/guide/iphone/iphbe11247b5/ios).

Inferência de UX: anexar é uma intenção única com várias fontes. A toolbar expõe a intenção e deixa as fontes no menu, em vez de transformar cada fonte em botão permanente.

### 5. Desenho possui um modo próprio

O botão de Markup abre uma toolbar especializada para desenho e escrita manual. Ela troca o conjunto de ferramentas conforme a tarefa: caneta, linha, marcador, borracha, laço, régua, lápis, cor e menu Add.

Fonte: [Apple — Write and draw in documents with Markup](https://support.apple.com/en-gb/guide/iphone/iph893c6f8bf/ios).

### 6. Menus e popovers fecham após a ação simples

As diretrizes recomendam menus curtos, agrupados por relação lógica, com separadores entre grupos. Para uma ação simples, o menu fecha ao selecionar um item; se houver múltiplas seleções, permanece aberto até ser dispensado. O popover deve ficar próximo ao controle que o abriu, deve haver um por vez, e o toque fora deve fechá-lo quando não há confirmação explícita.

Fontes: [HIG — Menus](https://developer.apple.com/design/human-interface-guidelines/menus), [HIG — Popovers](https://developer.apple.com/design/human-interface-guidelines/popovers).

### 7. O estado ativo deve ser visível

A Apple recomenda que itens alternáveis comuniquem o estado atual. Para controles de seleção, o botão pode atualizar seu conteúdo para mostrar a opção atual; menus podem usar checkmark ou estado selecionado.

Fonte: [HIG — Pop-up buttons](https://developer.apple.com/design/human-interface-guidelines/pop-up-buttons).

## Modelo comportamental resultante

```text
edição textual
  ├─ ações essenciais: formatação, checklist/lista, tabela, anexar
  ├─ formatação → estilos e atributos inline
  ├─ anexar → fontes: foto, arquivo, scanner, áudio
  ├─ seleção → estados ativos refletem o trecho atual
  └─ desenho/markup → modo especializado, com suas próprias ferramentas
```

O padrão não é “uma barra com todos os comandos”. É uma barra de intenções, com grupos compactos e modos temporários para tarefas que precisam de mais controles.

## Comparação com o SupaNotes atual

O toolbar atual já tem decisões compatíveis com esse padrão:

- usa uma superfície única compacta com rolagem horizontal;
- agrupa formatação em um popover e listas em outro;
- deriva os estados de seleção e do documento atual;
- mostra indentação somente quando o cursor está em item de lista;
- separa imagem e arquivo como entradas de anexo;
- preserva foco e seleção antes de executar comandos;
- usa uma superfície glass com fallback de alto contraste.

Esses pontos estão em `lib/features/notes/editor/presentation/widgets/note_toolbar.dart` e `note_toolbar_menus.dart`.

Diferenças principais:

1. O SupaNotes expõe imagem e arquivo separadamente; o modelo do Apple Notes sugere uma intenção única de anexar com um menu de fontes.
2. A toolbar atual possui divisor como ação permanente; isso parece mais próximo de uma ação de inserção secundária do que de uma ação principal.
3. O SupaNotes tem o popover de formatação, mas o modo dedicado descrito em `docs/superpowers/specs/2026-08-01-note-formatting-toolbar-mode.md` ainda é uma decisão de produto, não uma conclusão desta pesquisa.
4. O Apple Notes tem modos especializados para desenho, scanner e áudio. Isso não implica que o SupaNotes deva implementar todos eles; são domínios com custo de dados, permissões e sincronização.

## Recomendação de produto

Para o SupaNotes, a direção mais fiel é manter uma única superfície contextual:

1. manter `Aa`/formatação, lista/checklist e anexar como intenções principais;
2. colocar bold, italic, tachado, H1/H2/H3 e citação dentro do grupo de formatação;
3. avaliar unificar imagem e arquivo em “Anexar” quando o fluxo de anexos suportar essa abstração;
4. manter o menu de lista curto e com estado ativo explícito;
5. tratar desenho, áudio e scanner como modos ou capacidades próprias;
6. preservar a seleção como fonte de verdade e enviar mudanças pelo fluxo de operações do editor/REST-OT.

Não recomendo copiar a quantidade total de recursos do Apple Notes. O valor principal a copiar é a hierarquia de descoberta: intenção principal na barra, comandos relacionados em menus curtos e modo dedicado para tarefas que mudam o modelo de interação.
