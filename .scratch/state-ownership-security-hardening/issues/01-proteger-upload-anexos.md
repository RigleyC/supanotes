# 01 — Proteger upload e ciclo de vida de anexos

**What to build:** Garantir que somente o proprietário ou um colaborador com permissão de edição possa anexar arquivos a uma nota. Aplicar limites antes do parsing e durante a leitura. Compensar uploads que não tenham seus metadados persistidos.

**Blocked by:** None — can start immediately.

**Status:** done

- [x] O proprietário da nota pode enviar um anexo válido.
- [x] Um colaborador com permissão `edit` pode enviar um anexo válido.
- [x] Um colaborador com permissão `view` recebe recusa antes do envio ao armazenamento.
- [x] Um usuário sem acesso recebe recusa antes do envio ao armazenamento.
- [x] Nota inexistente ou removida não produz upload.
- [x] A identidade autenticada participa da decisão de autorização no serviço.
- [x] O corpo HTTP é limitado antes do processamento multipart.
- [x] O leitor do arquivo impede que mais bytes que o limite cheguem ao armazenamento.
- [x] Tamanho ausente, negativo ou inconsistente é tratado de forma segura.
- [x] Falha ao persistir metadados após o upload remove o objeto ou registra compensação durável.
- [x] Testes do handler e do serviço cobrem ownership, `edit`, `view`, ausência de acesso e limites.
