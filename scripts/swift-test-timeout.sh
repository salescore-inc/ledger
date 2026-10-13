#!/bin/sh
set -eu
python3 - "$@" <<'PY'
import os, signal, subprocess, sys
seconds = int(sys.argv[1])
if not 1 <= seconds <= 120:
    sys.exit('Test timeout must be between 1 and 120 seconds')
process = subprocess.Popen(['swift', 'test', *sys.argv[2:]], start_new_session=True)
try:
    sys.exit(process.wait(timeout=seconds))
except subprocess.TimeoutExpired:
    subprocess.run(['ps', '-ef'], check=False)
    if sys.platform == 'darwin':
        processes = subprocess.check_output(['ps', '-axo', 'pid=,command='], text=True)
        for line in processes.splitlines():
            if 'swiftpm-testing-helper' in line and os.getcwd() in line:
                pid = line.strip().split(None, 1)[0]
                subprocess.run(['sample', pid, '3', '-file', '.build/test-timeout.sample.txt'], timeout=10, check=False)
                with open('.build/test-timeout.sample.txt') as sample:
                    print(sample.read())
    os.killpg(process.pid, signal.SIGKILL)
    process.wait()
    sys.exit(124)
PY
