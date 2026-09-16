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

## Contrato de upload

`POST /api/v1/attachments/upload` deve retornar um objeto com `id`, `note_id`,
`filename`, `download_url`, `mime_type`, `size_bytes` e `created_at`. O cliente
valida esse objeto e marca a linha local como `failed` antes de propagar
qualquer erro.

O backend atual gera o ID remoto durante o upload. O documento mantém o ID
estável do nó/local para preservar o estado offline e grava o `download_url`
autenticado retornado; a entrega autenticada prioriza essa URL. Se o backend
deixar de fornecer uma URL de download autenticada ou mudar esse formato, será
necessário um contrato de reconciliação de IDs antes de alterar o cliente.

Veja também [editor/document](../editor/README.md) e o endpoint em
[backend attachments](../../../../backend/internal/README.md#pacotes-de-domínio).
