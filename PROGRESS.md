# Progress
- [x] B1 Implement versioned binary packaging, release automation and generated Homebrew Formula; preserve CLI behavior `depends:none` `parallel:none`
- [x] B2 Verify actual Linux and macOS executables and publish the fixed release `depends:B1` `parallel:none`
- [x] B3 Verify release identities, checksums and consumer installation end to end `depends:B1,B2` `parallel:none`

- [x] LJ1 Defined single-object legacy recognition, reserved-envelope rejection, lexical preservation, deterministic baseline identity and atomic CAS conversion in root/Append design; main base explicitly authorized `depends:none` `parallel:none`
- [x] LJ2 Reproduced invalid_log; lexical conversion preserves payload tokens and commits baseline/new record together; macOS21/Linux21 tests passed including races, replay/lost acknowledgment, corruption, limits and actual GCS request adapter; Linux static amd64 and native macOS CLI smoke passed `depends:LJ1` `parallel:none`
- [x] LJ3 Complete scoped review and native/static binary verification passed; coherent task commit on codex/legacy-json-compatibility-20261013; no configured upstream or release/deploy performed; Linux evidence in /var/folders/c4/bcbjzcj556d3xj45z64rzjmw0000gn/T/ledger-legacy-linux-89qzh2ui/build.log `depends:LJ1,LJ2` `parallel:none`

- [ ] LREL1 Publish Ledger v0.1.1 from merged tested source; native macOS21 and Linux21 tests/static binary smoke already passed, release packaging tests passed; CI now executes macOS tests before packaging `depends:none` `parallel:none`
- [ ] LREL2 Verify immutable release assets/source and update Homebrew Formula from the verified generated asset `depends:LREL1` `parallel:none`
