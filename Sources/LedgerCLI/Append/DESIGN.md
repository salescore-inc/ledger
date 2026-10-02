# Append

## Purpose and Scope
The internal component of the [CLI package](../../../DESIGN.md). No children.
Owns input framing, path resolution, conditional append and bounded REST I/O.

## Responsibilities and Boundaries
Caller owns JSON meaning. `ObjectStore` owns generation-pinned reads/conditional
writes. A pinned body that disappears returns `CLIError(code: "contention")`;
`read` issues at most one metadata/body pair and never retries internally.
`Appender` owns operation identity, the shared attempt budget, backoff and retry outcomes. `HTTPTransport`
owns a single bounded network request and its cancellation cleanup.

## Related Designs
Parent: [package](../../../DESIGN.md), which owns the public CLI contract.
Used by: executable entry point. Tests: [test target](../../../Tests/LedgerCLITests).

## Architecture
`Command -> Configuration / JSONRecord -> Appender -> ObjectStore -> HTTPTransport`

## Contracts and Invariants
All cloud uploads are generation-conditional. A lost response is uncertain until
confirmed by a receipt. Records are UTF-8 JSON objects with lexical number
preservation and unique keys. Transport redirects never carry credentials.
Per-request mutable networking state and continuation are in one `Mutex`.
Continuations are resumed outside the lock, once; cancellation cancels the task.
The delegate's unchecked Sendable conformance exists only for Foundation's
callback boundary, with all mutable properties inside that mutex.

## Verification and Change Impact
Tests force competing read snapshots, failed acknowledgments, duplicate IDs,
invalid framing, unsafe paths and bounded HTTP bodies. Linux and macOS use the
same logic and synchronization; no Embedded/WASM target is declared.

Diagnostic details are owned by the failing operation and encoded by the entry
point. Appender preserves unknown commit state after ambiguous uploads. JSON
locations never include input fragments. See the parent error-feedback contract.

Completed delegates release response buffers; only the returned response owns
its body. The one-shot process retains request sessions until exit; request count is
bounded by the configured retry budget: at most `3 * maxAttempts + 3`
HTTP requests per invocation, including metadata authentication and final
reconciliation. Each generation-disappearance read consumes an append attempt
and shares the existing deadline/backoff. No separate nested retry limit exists. Each session owns its request delegate
and Mutex state. A task deadline cancels streaming as well as idle requests.
Session invalidation is avoided after a confirmed Static Linux SDK libcurl
teardown abort in dev Cloud Run. Session-level delegates are used because task
delegates did not complete HTTP requests on the tested Static Linux SDK.

Token acquisition checks the invocation budget before either credential path and
before returning a token. Local token-file access is bounded in bytes and uses
cooperative deadline/cancellation checks before and after synchronous I/O;
metadata authentication uses the bounded HTTP transport. No successful token is
returned after a detected deadline or cancellation.

`CloudObjectStoreTests` injects a per-instance HTTP sender to exercise the actual
GCS request construction and status handling. The production sender remains
`HTTPTransport.send`; URLs and credentials are not caller-configurable through
this test seam. Tests cover repeated disappearing generations, recovery,
conditional upload parameters, unknown uploads followed by read conflicts, and
valid/expired/cancelled token reads. All fixtures have isolated actor state and
UUID-named temporary files; no shared mutable test configuration is installed.
