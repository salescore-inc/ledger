#!/usr/bin/env python3
"""Package a verified executable with deterministic release identity."""
import argparse, gzip, hashlib, io, json, pathlib, re, tarfile

def package(binary, tag, source, target, output):
    if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag):
        raise ValueError("invalid release tag")
    if not re.fullmatch(r"[0-9a-f]{40}", source):
        raise ValueError("invalid source SHA")
    if target not in ("linux-amd64", "darwin-arm64"):
        raise ValueError("unsupported target")
    data = pathlib.Path(binary).read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    manifest = dict(schemaVersion=1, tag=tag, source=source, target=target, binarySha256=digest)
    members = {"ledger": data, "ledger.sha256": f"{digest}  ledger\n".encode(),
               "manifest.json": (json.dumps(manifest, sort_keys=True) + "\n").encode()}
    output = pathlib.Path(output)
    output.mkdir(parents=True, exist_ok=True)
    asset = f"ledger-{tag}-{target}.tar.gz"
    with (output / asset).open("wb") as file:
        with gzip.GzipFile(filename="", mode="wb", fileobj=file, mtime=0) as gz:
            with tarfile.open(fileobj=gz, mode="w", format=tarfile.USTAR_FORMAT) as archive:
                for name, content in members.items():
                    info = tarfile.TarInfo(name)
                    info.size = len(content)
                    info.mode = 0o755 if name == "ledger" else 0o644
                    archive.addfile(info, io.BytesIO(content))
    manifest.update(asset=asset, archiveSha256=hashlib.sha256((output / asset).read_bytes()).hexdigest())
    (output / f"{target}.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest

if __name__ == "__main__":
    p = argparse.ArgumentParser()
    for name in ("binary", "tag", "source", "target", "output"):
        p.add_argument("--" + name, required=True)
    a = p.parse_args()
    print(json.dumps(package(a.binary, a.tag, a.source, a.target, a.output)))
