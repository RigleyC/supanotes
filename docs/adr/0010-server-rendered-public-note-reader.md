# Render public note links with the Go backend

SupaNotes uses one canonical HTTPS **Share Link** that an installed native app may claim through Universal Links or App Links and that otherwise opens a browser destination. The browser destination is server-generated HTML with small CSS and only necessary JavaScript. The Go backend reads the canonical document model and produces the responsive read-only page; it does not load Flutter Web or a separate client framework because fast first load and access without an installed app are primary requirements.

## Consequences

- The public renderer must support the canonical block and inline-attribution contract.
- The public page and its assets must remain independent of the Flutter Web runtime.
- The public domain must publish platform association metadata for the native applications.
- The response must prevent search indexing and safely escape all note content.
