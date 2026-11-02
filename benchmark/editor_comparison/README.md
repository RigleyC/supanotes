# Comparação de editores rich text

Mede o custo de digitar, mover a seleção e abrir uma nota em editores rich
text Flutter nativos, com o mesmo documento e a mesma metodologia:

| Pacote | Editor | Observação |
|---|---|---|
| `super_editor_poc` | super_editor `3bb857bc` (o do app) | |
| `super_editor_latest_poc` | super_editor `main` `9125dd4f` (out/2026) | |
| `quill_poc` | flutter_quill 11.6.0 | |
| `fleather_poc` | fleather 1.28.0 | exige um `Material` do pacote `material_ui` acima do editor |
| `appflowy_poc` | appflowy_editor (6.2.0 + `main` com correção para Flutter 3.47) | |
| `clepit_poc` | clepit_core 0.3.0 | |
| `block_editor_poc` | block_editor 0.0.4-dev.1 | `vendor/` = pacote do pub.dev + `onFocusReceived` (não compila no Flutter 3.47 sem isso) |

Ficaram de fora, por categoria: editores em WebView (`html_editor_enhanced`,
`quill_html_editor`, `tiptap_flutter`, `flutter_blocknote_editor`,
`rich_editor`, `flutter_rte`, `flutter_summernote`), porque blocos de tarefa e
anexos teriam de ser HTML/JS, há o custo de iniciar a WebView e o suporte a
desktop é fraco; editores de código-fonte Markdown (`mawy`,
`live_markdown_editor`, `markdown_editor_plus`); e pacotes muito imaturos
(`editorjs_flutter`, `docsy`, `novel_editor`).

`harness/` define o documento (150 parágrafos e 50 tarefas, multiplicados por
`SCALE`), a interface `EditorDriver` e a medição. Cada tecla e cada mudança de
seleção é medida como trabalho de edição + trabalho do quadro seguinte (build,
layout e paint), sem contar a espera pelo próximo vsync. A semântica fica
desligada, como num aparelho sem leitor de tela.

```bash
cd benchmark/editor_comparison
for d in */; do (cd $d && flutter pub get); done
./run_all.sh            # todas as combinações, em sequência
# ou um só: (cd appflowy_poc && flutter test --dart-define=SCALE=5 test/benchmark_test.dart)
# AppFlowy pelo caminho do IME (atalhos de caractere incluídos): --dart-define=IME_PATH=true
```

## Resultados (Linux, modo de teste/JIT, 2 rodadas sequenciais; médias em ms)

| Editor | tecla 200 | tecla 1000 | seleção 200 | seleção 1000 | abrir 200 | abrir 1000 |
|---|---|---|---|---|---|---|
| **appflowy_editor** | **5,5** | **5,0** | 12,5 | **13,6** | 612 | 714 |
| block_editor | 11,0 | 12,3 | 16,0 | 18,7 | **425** | **409** |
| super_editor (app) | 20,1 | 61,6 | **10,5** | 24,8 | 953 | 2.218 |
| super_editor (`main`) | 20,7 | 61,9 | 11,2 | 24,5 | 929 | 2.214 |
| fleather | 31,8 | 93,8 | 15,1 | 46,0 | 714 | 1.396 |
| flutter_quill | 46,5 | 117,2 | 24,2 | 72,8 | 738 | 1.717 |
| clepit_core | 61,1 | 56,6 | n/c* | n/c* | 537 | 638 |

\* O driver do clepit precisa rolar a lista até blocos fora da tela antes de
selecioná-los, então a seleção dele não é comparável.

Pelo caminho do IME (atalhos incluídos), o AppFlowy custa 5,9 ms por tecla nos
dois tamanhos.

Por quê: AppFlowy, block_editor e clepit usam lista virtualizada (só os blocos
visíveis existem), por isso abrir e digitar não crescem com a nota. O clepit
reconstrói o editor inteiro a cada tecla, o que anula a vantagem. super_editor,
Quill e Fleather montam e diagramam todos os blocos; o presenter do
super_editor ainda recria o view model de todos os blocos a cada edição, também
no `main` mais recente.

O pior caso de seleção dos editores virtualizados aparece quando a seleção vai
para um bloco fora da tela, que precisa ser construído.

## Adequação ao SupaNotes (lido no código-fonte de cada pacote)

| | Bloco de tarefa com metadados | Operações para sync | Ocultar bloco | Alças de seleção mobile | Maturidade |
|---|---|---|---|---|---|
| appflowy_editor | sim (BlockComponentBuilder + atributos) | Transaction/Operation; remoto sem eco nem undo | não nativo (bloco customizado vazio) | sim (estilo configurável) | ativo; release no pub atrasado |
| block_editor | sim (BlockPlugin + atributos) | só snapshot do documento; sem ops | não | **não tem** | pré-release, "não use em produção" |
| clepit_core | não (tipos de bloco fechados) | mutações por bloco inteiro; bug: texto remoto não aparece no bloco montado | não | nativas do TextField | 0.3.0, recente |
| fleather | não (sem hook de linha; atributos fechados) | Delta com origem; remoto entra no undo | não | sim | ativo, estável |
| flutter_quill | parcial (checkbox customizado + embed inline) | Delta com origem; remoto entra no undo | não | sim | ativo, muito usado |
