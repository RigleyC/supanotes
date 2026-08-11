# Compartilhamento de notas

Compartilhar é uma alteração de permissão no servidor, não uma alteração no
snapshot do documento.

- `model/` define `ShareModel` e `SharePermission` (`view` ou `edit`).
- `data/SharesRepository` chama os endpoints de compartilhar, listar e revogar.
- `application/` mantém o estado assíncrono por `noteId`; operações antigas não
  podem sobrescrever o resultado de uma operação mais recente.
- `presentation/` contém a sheet e a lista de pessoas com acesso.

## Share Link

O Share Link é uma capability separada do Direct Share. O servidor mantém o
token revogável e autoriza o acesso à nota e aos anexos sem exigir uma conta.

- O navegador abre `/s/:token` com HTML renderizado no servidor.
- O app valida `/s/:token/access` e escolhe o fluxo convidado ou a nota normal.
- Owner, editor e viewer autenticados hidratam a nota no catálogo antes de
  abrir a mesma tela de nota.
- Convidados usam o leitor Super Editor em modo somente leitura.
- Anexos públicos passam pelo token e anexos autenticados passam pelo endpoint
  privado. A revogação bloqueia novos downloads.

As regras de renderização e entrega privada estão em
`docs/adr/0010-server-rendered-public-note-reader.md` e
`docs/adr/0011-authorized-private-attachment-delivery.md`.

O editor observa a nota e desativa captura local quando a permissão passa para
somente leitura. O backend continua sendo a autoridade de autorização.
