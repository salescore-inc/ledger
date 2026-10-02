import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const binary = resolve(process.argv[2]);
const elf = readFileSync(binary);
assert.equal(elf.subarray(0, 4).toString('hex'), '7f454c46');
assert.equal(elf[4], 2, 'ELF must be 64-bit');
assert.equal(elf[5], 1, 'ELF must be little-endian');
assert.equal(elf.readUInt16LE(18), 62, 'ELF must target x86-64');
const table = Number(elf.readBigUInt64LE(32));
for (let index = 0; index < elf.readUInt16LE(56); index++) {
  assert.notEqual(elf.readUInt32LE(table + index * elf.readUInt16LE(54)), 3,
    'Standalone binary must not require a dynamic interpreter');
}
assert.match(execFileSync(binary, ['--help'], { encoding: 'utf8', timeout: 10000 }), /contextgraph append/);
const root = mkdtempSync(join(tmpdir(), 'contextgraph-binary-'));
try {
  const config = join(root, 'config.json');
  writeFileSync(config, JSON.stringify({ mountRoot: root, bucket: 'binary-smoke',
    maxRecordBytes: 1024, maxFileBytes: 4096, maxAttempts: 1, timeoutSeconds: 5 }));
  const result = spawnSync(binary, ['append', join(root, 'graph.jsonl'), '--id',
    '6e8b4332-0d5c-4f69-9d9d-516c0a2c65dd'], {
    input: '{"broken":}', encoding: 'utf8', timeout: 10000,
    env: { ...process.env, CONTEXTGRAPH_CONFIG: config },
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
console.log('Standalone Linux amd64 binary and JSON failure passed');
