# Evaluation: terra-firma-labs/yrs-dart

Reviewed revision: `0654ced3d881194d0d77f77329a356ad387d3d94` (2026-07-20).

## Conclusion

`yrs-dart` is a promising replacement candidate for the current pure-Dart
`yjs_dart` port because its CRDT operations are implemented by `yrs`, the
Rust Yjs implementation. It is not ready for a direct production migration:
the repository labels itself experimental and pre-1.0, has two commits, and
its Rust test command reports zero tests.

The current SupaNotes schema can use its maps, nested containers, plain text,
state-vector exchange, v1 updates, update observation, and undo manager. The
current rich text editor cannot migrate unchanged because the binding does not
expose YText formatting attributes, deltas, or embeds.

## Compatibility matrix

| SupaNotes requirement | yrs-dart status | Evidence |
| --- | --- | --- |
| YMap nodes and task metadata | Supported | `YrsMap` has set/get/delete, nested map/array/text, keys and length. |
| YText insert/delete/plain content | Supported | `YrsText` exposes insert, remove, value, and UTF-16 length. |
| Bold and other character attributes | Not supported | Repository roadmap and design explicitly defer formatting/attributes/embeds. |
| CRDT v1 state-vector exchange | Supported API, unverified against SupaNotes backend | `applyUpdate`, `getStateVector`, and `encodeStateAsUpdate` use v1. |
| Local/remote update observation | Supported API, unverified on Android | `observe_update_v1` is bridged as a Dart stream. |
| Undo excluding remote edits | Supported API, unverified in app | Binding assigns distinct local and remote origins. |
| Android build and native distribution | Intended support, unverified here | `yrs_flutter` uses cargokit. |
| Existing production snapshots | Must be a migration gate | No fixture or compatibility test is supplied by the project. |

## Required adoption gate

Do not ship the binding until all of these pass in SupaNotes:

1. Load the captured production snapshot and verify every visible node,
   position, task field, and formatted text against the Go projection.
2. Exchange updates in both directions between the Flutter binding and the Go
   `ygo` backend, including duplicate and out-of-order delivery.
3. Run two-device concurrent edits on the same text, including accents, emoji,
   bold boundaries, deletion, split/merge, task metadata, and reordering.
4. Restart both clients after each scenario and compare canonical YDoc state,
   SQLite projection, and PostgreSQL projection.
5. Exercise Android release builds and lifecycle transitions; verify update
   stream, undo origin behavior, and native library loading.

## Recommendation

Use `yrs-dart` only as the basis of a controlled migration branch. First add
formatting/delta support to the binding or change SupaNotes to store rich-text
attributes in a compatible representation. Then run the adoption gate above
before allowing it to persist production updates.

## Sources

- https://github.com/terra-firma-labs/yrs-dart/tree/0654ced3d881194d0d77f77329a356ad387d3d94
- `packages/yrs/README.md` and `docs/v0.0.2-design.md` in that revision
- `packages/yrs/rust/src/api/yrs_doc.rs`, `yrs_map.rs`, `yrs_array.rs`,
  `yrs_text.rs`, and `yrs_undo.rs` in that revision
