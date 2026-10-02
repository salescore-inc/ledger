#!/bin/sh
set -eu
# Fail only when a deinit body synchronously shuts down a resource.
python3 - "$@" <<'PY'
import pathlib, re, sys
failed = False
for root in sys.argv[1:]:
    for path in pathlib.Path(root).rglob('*.swift'):
        source = path.read_text()
        for match in re.finditer(r'\bdeinit\s*\{', source):
            end, depth = match.end(), 1
            while end < len(source) and depth:
                depth += (source[end] == '{') - (source[end] == '}')
                end += 1
            if re.search(r'\bsyncShutdownGracefully\b|\bwaitUntilExit\b|\bsemaphore\.wait\b', source[match.end():end]):
                print(f'{path}:{source[:match.start()].count(chr(10)) + 1}: synchronous deinit shutdown', file=sys.stderr)
                failed = True
sys.exit(failed)
PY
