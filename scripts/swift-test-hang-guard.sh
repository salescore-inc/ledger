#!/bin/sh
set -eu
repeats=2
timeout=30
while [ "$#" -gt 0 ]; do
    case "$1" in
        --repeats) repeats=$2; shift 2 ;;
        --timeout) timeout=$2; shift 2 ;;
        --) shift; break ;;
        *) echo "Unknown guard option: $1" >&2; exit 2 ;;
    esac
done
mkdir -p .build
mkdir .build/test-guard.lock || exit 3
trap 'rmdir .build/test-guard.lock' EXIT
scripts/check-sync-shutdown-in-deinit.sh Sources Tests
iteration=0
while [ "$iteration" -lt "$repeats" ]; do
    scripts/swift-test-timeout.sh "$timeout" "$@"
    iteration=$((iteration + 1))
done
