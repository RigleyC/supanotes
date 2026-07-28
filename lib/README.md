# Flutter: mapa da camada cliente

`lib/` contém o aplicativo Flutter. A regra prática é: `core` fornece
infraestrutura de aplicativo, `features` contém casos de uso do produto e
`shared` contém UI e tema que não pertencem a uma feature.

## Ordem de execução

1. [main.dart](main.dart) cria o `ProviderScope`, inicializa preferências e
   serviços locais e monta o app.
2. [core/router](core/README.md#router) escolhe a tela conforme autenticação e
   rota.
3. Uma tela observa providers de sua feature.
4. Repositórios e serviços leem/escrevem Drift ou HTTP.

## Guias locais

- [core](core/README.md): banco, DI, API, autenticação atual e sync.
- [features](features/README.md): comportamento de produto.
- [shared](shared/README.md): tema e widgets de uso transversal.

Não crie uma feature nova em `core`, nem coloque regra de negócio em widgets.
