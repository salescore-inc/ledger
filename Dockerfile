# syntax=docker/dockerfile:1.7

FROM --platform=$BUILDPLATFORM swift:6.4.0 AS ledger-build
WORKDIR /ledger
RUN apt-get update && apt-get install --no-install-recommends --yes curl ca-certificates python3 \
    && rm -rf /var/lib/apt/lists/*
# Keep SDK download outside SwiftPM's networking lifetime.
RUN curl --fail --silent --show-error --location --max-time 300 \
    https://download.swift.org/swift-6.4.0-release/static-sdk/swift-6.4.0-RELEASE/swift-6.4.0-RELEASE_static-linux-0.1.0.artifactbundle.tar.gz \
    --output /tmp/swift-sdk.tar.gz \
    && echo '47d2fd89eebfdf9eb4d536b6710414297f755c17926cdebc4742c08982b40a9e /tmp/swift-sdk.tar.gz' | sha256sum --check \
    && swift sdk install /tmp/swift-sdk.tar.gz \
    && rm /tmp/swift-sdk.tar.gz
COPY Package.swift Package.resolved ./
COPY Sources ./Sources
COPY Tests ./Tests
COPY scripts ./scripts
RUN timeout 240s swift build --build-tests -j 4
RUN scripts/swift-test-hang-guard.sh --repeats 2 --timeout 30 -- --skip-build
RUN swift build --swift-sdk x86_64-swift-linux-musl -c release -j 4 \
    && cp "$(swift build --swift-sdk x86_64-swift-linux-musl -c release --show-bin-path)/ledger" /ledger/ledger \
    && sha256sum ledger > ledger.sha256

# Validate the distributable without a Swift installation.
FROM node:24-bookworm-slim AS ledger-binary-test
WORKDIR /binary
COPY --from=ledger-build /ledger/ledger /ledger/ledger.sha256 ./
COPY binary.smoke.mjs ./
RUN sha256sum --check ledger.sha256 && node binary.smoke.mjs ./ledger

# ledger-binary exports a standalone executable and checksum.
FROM scratch AS ledger-binary
COPY --from=ledger-binary-test /binary/ledger /binary/ledger.sha256 /

