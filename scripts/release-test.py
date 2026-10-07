import importlib.util, json, pathlib, tempfile, unittest

def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result

root = pathlib.Path(__file__).parent
producer = module("producer", root / "package-binary.py")
assembler = module("assembler", root / "assemble-release.py")

class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.binary = self.root / "input"
        self.binary.write_bytes(b"tested executable bytes")
        for target in assembler.TARGETS:
            producer.package(self.binary, "v0.1.0", "a" * 40, target, self.root)

    def test_deterministic_archive_and_binary_only_formula(self):
        first = (self.root / "ledger-v0.1.0-linux-amd64.tar.gz").read_bytes()
        producer.package(self.binary, "v0.1.0", "a" * 40, "linux-amd64", self.root)
        self.assertEqual(first, (self.root / "ledger-v0.1.0-linux-amd64.tar.gz").read_bytes())
        result = assembler.assemble(self.root)
        self.assertEqual(result["source"], "a" * 40)
        formula = (self.root / "ledger.rb").read_text()
        self.assertIn(result["targets"]["linux-amd64"]["archiveSha256"], formula)
        self.assertIn(result["targets"]["darwin-arm64"]["archiveSha256"], formula)
        self.assertIn('bin.install "ledger"', formula)
        self.assertNotIn("swift build", formula)

    def test_changed_archive_is_rejected(self):
        with (self.root / "ledger-v0.1.0-linux-amd64.tar.gz").open("ab") as f:
            f.write(b"changed")
        with self.assertRaisesRegex(ValueError, "archive checksum"):
            assembler.assemble(self.root)

    def test_mixed_sources_and_tags_are_rejected(self):
        for field, value in (("source", "b" * 40), ("tag", "v0.2.0")):
            with self.subTest(field=field):
                producer.package(self.binary, "v0.1.0", "a" * 40, "darwin-arm64", self.root)
                producer.package(self.binary, value if field == "tag" else "v0.1.0", value if field == "source" else "a" * 40, "darwin-arm64", self.root)
                with self.assertRaisesRegex(ValueError, "sources or tags"):
                    assembler.assemble(self.root)

    def test_missing_target_is_rejected(self):
        (self.root / "darwin-arm64.json").unlink()
        with self.assertRaises(FileNotFoundError):
            assembler.assemble(self.root)

    def test_invalid_producer_identities_are_rejected(self):
        for tag, source, target in (("latest", "a" * 40, "linux-amd64"), ("v0.1.0", "main", "linux-amd64"), ("v0.1.0", "a" * 40, "linux-arm64")):
            with self.subTest(target=target), self.assertRaises(ValueError):
                producer.package(self.binary, tag, source, target, self.root)

if __name__ == "__main__":
    unittest.main()
