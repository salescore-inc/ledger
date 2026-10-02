# Ledger

A standalone Swift CLI for safe, concurrent JSONL append.

```sh
ledger append /mnt/storage/events.jsonl --id <operation-uuid> < record.json
```

Ledger validates one JSON object, wraps it as `{id,hash,data}`, and commits it
using Google Cloud Storage generation preconditions. Competing writers retry
without losing earlier successful appends. Repeating the same UUID and exact
input bytes confirms the original write instead of duplicating it.

The current backend is Google Cloud Storage. Callers read ordinary mounted
paths; Ledger resolves those paths through trusted mount configuration and uses
the REST API for conditional writes. It has no Storage SDK, daemon or database.
Payload meaning and domain schema belong to the caller. POSIX files and other
storage providers are not supported by this backend.

## Configuration

Set `LEDGER_CONFIG` to a trusted configuration file; the default is
`/etc/ledger.json`. Its fields are `mountRoot`, `bucket`, `maxRecordBytes`,
`maxFileBytes`, `maxAttempts` and `timeoutSeconds`. Configuration limits are
positive and bounded as specified in [DESIGN](DESIGN.md). Cloud Run supplies
workload identity through its metadata service. CA certificates are required.
`accessTokenFile` is an explicit short-lived-token option for local verification.
Never commit credentials or allow untrusted callers to replace configuration.

## Build and install

The [Dockerfile](Dockerfile) pins Swift 6.4.0 and its checksummed Static Linux SDK.
It runs native Swift tests and verifies the static Linux amd64 executable without
a Swift installation. [CI](.github/workflows/build.yml) distributes the
`ledger-linux-amd64-<commit-sha>` artifact.

```sh
docker buildx build --platform linux/amd64 --target ledger-binary \
  --output type=local,dest=/tmp/ledger-binary .
tar -czf /tmp/ledger-linux-amd64.tar.gz \
  -C /tmp/ledger-binary ledger ledger.sha256
```

Install a downloaded archive on Linux amd64:

```sh
tar -xzf ledger-linux-amd64.tar.gz
sha256sum --check ledger.sha256
install -m 0755 ledger /usr/local/bin/ledger
ledger --help
```

The installed executable needs no Swift runtime installation. Consumers pin
source commits or commit-named artifacts and verify the checksum before use.

## Verification

`swift test` exercises forced write contention, replay, lost acknowledgments,
JSON validation, bounded HTTP bodies, redirects, timeout and cancellation.
The binary smoke test checks ELF/static linking, execution and malformed-JSON
feedback. These checks do not replace real Cloud Run/GCS integration evidence.
See [DESIGN](DESIGN.md) for guarantees, limits and structured error feedback.

## License

[MIT](LICENSE).
