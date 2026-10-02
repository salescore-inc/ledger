# ContextGraph CLI

Standalone Swift CLI for validated, generation-conditional JSONL append. Agents
read mounted paths and invoke `contextgraph append <absolute-jsonl-path> --id
<operation-uuid>` with one JSON object on stdin. The CLI owns write serialization
and retry feedback; callers own graph semantics. See [DESIGN](DESIGN.md).

## Build and distribution

The [Dockerfile](Dockerfile) pins Swift 6.4.0 and its checksummed Static Linux SDK.
It runs the Swift behavioral tests and verifies the standalone Linux amd64 binary
without a Swift installation. [CI](.github/workflows/build.yml) exports the
`contextgraph-linux-amd64-<commit-sha>` artifact; no moving release is selected.

```sh
docker buildx build --platform linux/amd64 --target contextgraph-binary \
  --output type=local,dest=/tmp/contextgraph-binary .
tar -czf /tmp/contextgraph-linux-amd64.tar.gz \
  -C /tmp/contextgraph-binary contextgraph contextgraph.sha256
```

To install a downloaded artifact on Linux amd64:

```sh
tar -xzf contextgraph-linux-amd64.tar.gz
sha256sum --check contextgraph.sha256
install -m 0755 contextgraph /usr/local/bin/contextgraph
contextgraph --help
```

The Runtime owner supplies CA certificates, workload identity, mounted storage
and `CONTEXTGRAPH_CONFIG`. The executable needs no Swift installation. EI pins
this repository as a submodule, builds with this Dockerfile, verifies the
checksum, and supplies the binary to its Runtime image as a named build context.

## Verification

Swift tests exercise forced write contention, replay, lost acknowledgments,
JSON validation, bounded HTTP bodies, redirects, timeout and cancellation. The
HTTP fixture is test-only. The binary smoke test checks ELF/static linking,
execution and malformed-JSON feedback. These checks do not replace real GCS and
Cloud Run concurrency evidence; platform integration is owned by EI.

## Source provenance

Extracted without production-source changes from `salescore-inc/ei` commit
`f617af442761cc4f09ef994328154733af347fc4`, path `agents/contextgraph-cli`.
The existing standalone HTTP test fixture accompanies its tests. CLI behavior
and the append/error/configuration contracts are unchanged by repository separation.
