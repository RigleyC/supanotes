# Anexos de notas

`attachments/` mantém a referência local a um arquivo e envia o conteúdo ao
backend. O documento guarda o nó que aponta para o anexo; esta pasta não muda
o documento por conta própria.

- `model/attachment_model.dart` traduz a linha Drift em estado de UI:
  `local`, `uploading`, `synced` ou `failed`.
- `data/local/attachments_local_repository.dart` encapsula o DAO.
- `data/attachments_repository.dart` cria primeiro a linha local, faz upload e
  atualiza URL ou falha. O estado local permite feedback offline/retry.
- Os renderizadores ficam em `editor/presentation/widgets/` porque são
  componentes do SuperEditor e precisam conhecer os nós do documento.

Veja também [editor/document](../editor/README.md) e o endpoint em
[backend attachments](../../../../backend/internal/README.md#pacotes-de-domínio).
