#!/usr/bin/env python3
"""Verify target artifacts and generate a binary-only Homebrew Formula."""
import argparse, hashlib, json, pathlib, re, tarfile

TARGETS = ("linux-amd64", "darwin-arm64")

def assemble(directory):
    root = pathlib.Path(directory)
    targets = {}
    for target in TARGETS:
        record = json.loads((root / f"{target}.json").read_text())
        if record["target"] != target or record["schemaVersion"] != 1:
            raise ValueError("target identity mismatch")
        if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", record["tag"]) or not re.fullmatch(r"[0-9a-f]{40}", record["source"]):
            raise ValueError("invalid release identity")
        if record["asset"] != f"ledger-{record['tag']}-{target}.tar.gz":
            raise ValueError("asset identity mismatch")
        archive = root / record["asset"]
        if hashlib.sha256(archive.read_bytes()).hexdigest() != record["archiveSha256"]:
            raise ValueError("archive checksum mismatch")
        with tarfile.open(archive) as tar:
            members = tar.getmembers()
            if len(members) != 3 or {m.name for m in members} != {"ledger", "ledger.sha256", "manifest.json"} or not all(m.isfile() for m in members):
                raise ValueError("unexpected archive contents")
            binary = tar.extractfile("ledger").read()
            if hashlib.sha256(binary).hexdigest() != record["binarySha256"]:
                raise ValueError("binary checksum mismatch")
            expected = {k: record[k] for k in ("schemaVersion", "tag", "source", "target", "binarySha256")}
            if json.load(tar.extractfile("manifest.json")) != expected:
                raise ValueError("manifest identity mismatch")
            if tar.extractfile("ledger.sha256").read().decode() != f"{record['binarySha256']}  ledger\n":
                raise ValueError("binary checksum file mismatch")
        targets[target] = record
    identity = {(r["tag"], r["source"]) for r in targets.values()}
    if len(identity) != 1:
        raise ValueError("target sources or tags differ")
    tag, source = identity.pop()
    release = dict(schemaVersion=1, repository="salescore-inc/ledger", tag=tag, source=source, targets=targets)
    (root / "release.json").write_text(json.dumps(release, indent=2) + "\n")
    linux, mac = (targets[t] for t in TARGETS)
    base = f"https://github.com/salescore-inc/ledger/releases/download/{tag}"
    formula = f'''class Ledger < Formula
  desc "Safe, concurrent JSONL append through Cloud Storage generation preconditions"
  homepage "https://github.com/salescore-inc/ledger"
  version "{tag[1:]}"
  license "MIT"

  on_macos do
    depends_on macos: :sequoia
    on_arm do
      url "{base}/{mac['asset']}"
      sha256 "{mac['archiveSha256']}"
    end
  end
  on_linux do
    on_intel do
      url "{base}/{linux['asset']}"
      sha256 "{linux['archiveSha256']}"
    end
  end

  def install
    bin.install "ledger"
  end

  test do
    assert_match "ledger append", shell_output("#{'{'}bin{'}'}/ledger --help")
  end
end
'''
    (root / "ledger.rb").write_text(formula)
    return release

if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("directory")
    print(json.dumps(assemble(p.parse_args().directory)))
