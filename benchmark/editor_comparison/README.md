# Comparação de editores rich text

Mede o custo de digitar, mover a seleção e abrir uma nota em três editores
Flutter, com o mesmo documento e a mesma metodologia:

- `super_editor_poc`: super_editor no commit usado pelo app (`3bb857bc`).
- `quill_poc`: flutter_quill 11.6.0.
- `appflowy_poc`: appflowy_editor (6.2.0 + correção do `main` para Flutter 3.47).

`harness/` define o documento (150 parágrafos e 50 tarefas, multiplicados por
`SCALE`), a interface `EditorDriver` e a medição. Cada tecla e cada mudança de
seleção é medida como trabalho de edição + trabalho do quadro seguinte (build,
layout e paint), sem contar a espera pelo próximo vsync. A semântica fica
desligada, como num aparelho sem leitor de tela.

```bash
cd benchmark/editor_comparison
for d in harness super_editor_poc quill_poc appflowy_poc; do (cd $d && flutter pub get); done
./run_all.sh            # todas as combinações, em sequência
# ou um só: (cd appflowy_poc && flutter test --dart-define=SCALE=5 test/benchmark_test.dart)
# AppFlowy pelo caminho do IME (atalhos de caractere incluídos): --dart-define=IME_PATH=true
```

## Resultados (Linux, modo de teste/JIT, 2 rodadas sequenciais; médias)

| Documento | Medida | super_editor | flutter_quill | appflowy_editor |
|---|---|---|---|---|
| 200 blocos | tecla | 20,2 ms | 46,5 ms | **5,6 ms** |
| 200 blocos | seleção | 10,5 ms | 24,2 ms | 12,5 ms |
| 200 blocos | abrir | 953 ms | 738 ms | **612 ms** |
| 1000 blocos | tecla | 61,6 ms | 117,2 ms | **5,0 ms** |
| 1000 blocos | seleção | 24,8 ms | 72,9 ms | **13,6 ms** |
| 1000 blocos | abrir | 2.218 ms | 1.717 ms | **714 ms** |

Pelo caminho do IME, o AppFlowy custa 5,9 ms por tecla nos dois tamanhos.

Por quê: o AppFlowy renderiza a página com uma lista virtualizada (só os blocos
visíveis são construídos), então o custo por tecla não cresce com a nota. O
super_editor e o Quill montam e diagramam todos os blocos; além disso, o
presenter do super_editor recria o view model de todos os blocos a cada edição.

O pior caso de seleção do AppFlowy (p90 ~25–35 ms) aparece quando a seleção vai
para um bloco fora da tela, que precisa ser construído.
