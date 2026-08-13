# Banco local: Drift SQLite

O banco local suporta offline, catálogo, outbox e documentos efetivos. O
documento remoto continua sendo a fonte canônica.

## Tabelas por papel

| Grupo | Tabelas | Por que existem |
| --- | --- | --- |
| Nota local | `notes`, `local_note_documents`, `note_links` | catálogo e snapshots |
| Documento efetivo | `local_note_documents.materialized_*` | edição offline e notificações |
| Outbox REST/OT | `pending_note_operations`, `sync_sessions`, `note_sync_errors` | retry e sync |
| Recursos | `attachments`, `user_note_preferences` | estado local |

`documentJson` é o snapshot confirmado. `materializedDocumentJson` é o
documento confirmado com as operações locais pendentes aplicadas.
