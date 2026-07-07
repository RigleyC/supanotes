# CRDT LF Source Code Audit Notes

This document records the pre-test source code audit findings for the `crdt_lf` package, specifically focusing on reference reuse (aliasing) and causal order processing.

## Audit Findings

### 1. Aliasing & Reference Reuse
No mutable reference leaks or aliasing bugs were found between independent client/document instances. Each `CRDTDocument` and `CRDTFugueTextHandler` instance owns its local `FugueTree` and `_nodes` map. Changes are serialized to bytes on export and deserialized as new objects on import (using the operation body decoders like `_FugueTextInsertOperation.fromBodyBytes`), ensuring no object references are shared.

### 2. Causal Ordering
The package requires causal dependencies. During `importChanges`, the changes are topologically sorted. If a change is imported whose causal dependencies are missing (not present in the DAG and not covered by the latest snapshot), the document throws a `CausallyNotReadyException`. This exception is caught in the `importChanges` loop, and the change is skipped (not applied). The caller/sync layer must track skipped changes and retry once the missing dependencies arrive.
