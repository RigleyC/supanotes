# Documentação de arquitetura navegável

## Objetivo

Permitir que uma pessoa nova compreenda o caminho de uma alteração desde a
raiz do projeto até o módulo responsável, sem inferir a arquitetura apenas
pelos nomes dos arquivos.

## Entregas

- `ARCHITECTURE.md` como entrada central e mapa dos fluxos principais.
- `README.md` nas camadas Flutter, backend e submódulos de notes.
- Guias para banco, sync, API, DI, router, features e testes.
- Identificação explícita de documentação Yjs como histórica e REST/OT como
  caminho atual.

## Limite intencional

Os guias explicam os contratos, objetos e métodos de decisão arquitetural. Um
método privado simples não recebe uma página própria; o README da pasta explica
onde ele se encaixa e o arquivo fonte continua sendo a especificação detalhada
de sua implementação.
