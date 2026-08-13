# Notes catalog

Este submódulo trata catálogo, criação local, remoção, busca e hidratação
remota. `watchNoteById` é a porta para detalhe; não existe join relacional de
tasks.

`NoteCatalogSync` calcula somente `content` e `excerpt`. O snapshot confirmado
e o snapshot efetivo local são mantidos pelo fluxo de sync do documento.
