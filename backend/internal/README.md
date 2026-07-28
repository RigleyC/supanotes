# Pacotes internos do backend

`internal/` contém código privado do módulo Go. Um pacote de domínio costuma
ter `handler.go`, `service.go` e `repository.go`.

## Pacotes de domínio

| Pacote | Responsabilidade |
| --- | --- |
| `auth` | registro, login, refresh e middleware JWT |
| `notes` | CRUD, busca e ciclo de vida da nota |
| `noteoperations` | contrato REST/OT, transformação, validação e persistência do snapshot |
| `tasks` | leitura/ações de tarefas convencionais e recorrência |
| `shares` | concessão e revogação de acesso à nota |
| `attachments` | validação, storage S3 e metadados de upload |
| `linkpreview` | busca e sanitização de metadados de links |
| `settings` | configurações de usuário |
| `mcp` | ferramentas MCP e emissão de token pessoal |

## Pacotes de suporte

- `db/sqlcgen`: código gerado; não editar manualmente.
- `dto`: formatos HTTP de entrada/saída.
- `mapper`: conversões de tipos `pgx`/sqlc para tipos de domínio.
- `web`: bind, contexto e respostas HTTP comuns.
- `handler`: health check.
- `utils`: funções puras, como índices fracionários.

O guia mais importante para notas é [noteoperations](noteoperations/README.md).
