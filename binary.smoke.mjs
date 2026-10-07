import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const binary = resolve(process.argv[2]);
const bytes = readFileSync(binary);
if (process.platform === 'linux') {
  assert.equal(bytes.subarray(0, 4).toString('hex'), '7f454c46');
  assert.equal(bytes[4], 2, 'ELF must be 64-bit');
  assert.equal(bytes[5], 1, 'ELF must be little-endian');
  assert.equal(bytes.readUInt16LE(18), 62, 'ELF must target x86-64');
  const table = Number(bytes.readBigUInt64LE(32));
  for (let index = 0; index < bytes.readUInt16LE(56); index++) {
    assert.notEqual(bytes.readUInt32LE(table + index * bytes.readUInt16LE(54)), 3,
      'Standalone Linux binary must not require a dynamic interpreter');
  }
} else {
  assert.equal(process.platform, 'darwin');
  assert.equal(bytes.readUInt32LE(0), 0xfeedfacf, 'Mach-O must be 64-bit');
  assert.equal(bytes.readUInt32LE(4), 0x0100000c, 'Mach-O must target arm64');
  const dependencies = execFileSync('/usr/bin/otool', ['-L', binary], {encoding: 'utf8', timeout: 10000});
  assert.doesNotMatch(dependencies, /\/Library\/Developer|\.xctoolchain/,
    'Installed binary must not depend on an installed Swift toolchain');
}
assert.match(execFileSync(binary, ['--help'], { encoding: 'utf8', timeout: 10000 }), /ledger append/);
const root = mkdtempSync(join(tmpdir(), 'ledger-binary-'));
try {
  const config = join(root, 'config.json');
  writeFileSync(config, JSON.stringify({ mountRoot: root, bucket: 'binary-smoke',
    maxRecordBytes: 1024, maxFileBytes: 4096, maxAttempts: 1, timeoutSeconds: 5 }));
  const result = spawnSync(binary, ['append', join(root, 'graph.jsonl'), '--id',
    '6e8b4332-0d5c-4f69-9d9d-516c0a2c65dd'], {
    input: '{"broken":}', encoding: 'utf8', timeout: 10000,
    env: { ...process.env, LEDGER_CONFIG: config },
  });
  assert.equal(result.error, undefined);
  assert.equal(result.status, 2);
  assert.equal(result.stdout, '');
  const failure = JSON.parse(result.stderr);
  assert.equal(failure.code, 'invalid_input');
  assert.equal(failure.stage, 'input');
  assert.equal(failure.retryAction, 'correct_input');
  assert.equal(failure.commitState, 'not_written');
} finally {
  rmSync(root, { recursive: true, force: true });
}
console.log('Standalone target binary and JSON failure passed');
