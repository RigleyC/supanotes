# Dados do backend

- `migrations/` define a evolução do schema PostgreSQL. Cada alteração de
  persistência começa aqui.
- `queries/` contém SQL fonte para o sqlc.
- O código em `internal/db/sqlcgen/` é gerado a partir dessas queries. Nunca o
  edite para corrigir uma query; ajuste a fonte e regenere.

Para REST/OT, schema, query e service devem concordar sobre snapshot, revisão,
operações e transação. Consulte [noteoperations](../internal/noteoperations/README.md).
