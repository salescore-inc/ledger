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

The binary producer uses Swift 6.4.0. Linux amd64 uses the matching checksummed
Static Linux SDK and is tested without a Swift installation. macOS arm64 is built
and executed on macOS 15. [CI](.github/workflows/build.yml) packages both targets,
checks their identities and publishes tested artifacts when a `vX.Y.Z` tag is pushed.
`VERSION` must match the tag. Existing releases are never replaced.

Each release contains versioned archives, `release.json` with source/target/archive
and executable SHA-256 identities, and a generated binary-only `ledger.rb` Formula.
Consumers pin those identities instead of compiling Swift during their deployment.

### Linux / Docker

Download the exact `ledger-vX.Y.Z-linux-amd64.tar.gz` release asset, verify the
archive checksum against your committed release pin, unpack it, verify
`ledger.sha256`, and install `ledger` on PATH during image assembly. The binary
needs CA certificates and trusted `LEDGER_CONFIG`; it needs no Swift compiler or
runtime package. Runtime startup does not download or build tools.

### Homebrew

The generated Formula is committed to `Formula/ledger.rb` when promoting a tested
release. It installs the same archive used by other consumers, with a fixed URL
and SHA-256. Supported targets are Linux amd64 and macOS 15+ on Apple Silicon.

```sh
brew tap salescore-inc/ledger https://github.com/salescore-inc/ledger.git
brew install salescore-inc/ledger/ledger
brew test salescore-inc/ledger/ledger
```

### Release process

Update `VERSION`, review the source, and run the binary CI. To publish an approved
release, tag that exact tested source and push the tag. The release workflow tests
and assembles all target artifacts before publication. It publishes a draft with
all assets before making the release public, using GitHub CLI's release creation
transaction. Copy the verified `ledger.rb` asset into `Formula/ledger.rb` for the
Homebrew tap update; this metadata update does not rebuild or change the CLI.
For initial release promotion, the same verified CI artifacts may be attached to
the release without rebuilding, with the release tag pointing to their exact
recorded source SHA.

## Verification

`swift test` exercises forced write contention, replay, lost acknowledgments,
JSON validation, bounded HTTP bodies, redirects, timeout and cancellation.
The binary smoke test checks ELF/static linking, execution and malformed-JSON
feedback. These checks do not replace real Cloud Run/GCS integration evidence.
See [DESIGN](DESIGN.md) for guarantees, limits and structured error feedback.

## License

[MIT](LICENSE).
