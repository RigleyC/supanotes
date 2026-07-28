# Alexa shopping-list backend

## Scope

Add an authenticated application command that finds the user's `Lista de compras` note and adds a task block through the canonical REST/OT document operation flow.

## Contract

`POST /api/v1/integrations/shopping-list/items` with `{ "item": "café" }`.

The command returns distinct errors for an empty item, a missing shopping-list note, and multiple matching notes. It does not create the note automatically and does not write directly to projected task storage.

Alexa request validation, OAuth account linking, and MCP registration are follow-up layers.
