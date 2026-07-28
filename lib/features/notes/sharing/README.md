# Compartilhamento de notas

Compartilhar é uma alteração de permissão no servidor, não uma alteração no
snapshot do documento.

- `model/` define `ShareModel` e `SharePermission` (`view` ou `edit`).
- `data/SharesRepository` chama os endpoints de compartilhar, listar e revogar.
- `application/` mantém o estado assíncrono por `noteId`; operações antigas não
  podem sobrescrever o resultado de uma operação mais recente.
- `presentation/` contém a sheet e a lista de pessoas com acesso.

O editor observa a nota e desativa captura local quando a permissão passa para
somente leitura. O backend continua sendo a autoridade de autorização.
