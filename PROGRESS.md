# Progress
- [x] B1 Implement versioned binary packaging, release automation and generated Homebrew Formula; preserve CLI behavior `depends:none` `parallel:none`
- [x] B2 Verify actual Linux and macOS executables and publish the fixed release `depends:B1` `parallel:none`
- [x] B3 Verify release identities, checksums and consumer installation end to end `depends:B1,B2` `parallel:none`

- [x] LJ1 Defined single-object legacy recognition, reserved-envelope rejection, lexical preservation, deterministic baseline identity and atomic CAS conversion in root/Append design; main base explicitly authorized `depends:none` `parallel:none`
- [x] LJ2 Reproduced invalid_log; lexical conversion preserves payload tokens and commits baseline/new record together; macOS21/Linux21 tests passed including races, replay/lost acknowledgment, corruption, limits and actual GCS request adapter; Linux static amd64 and native macOS CLI smoke passed `depends:LJ1` `parallel:none`
- [x] LJ3 Complete scoped review and native/static binary verification passed; coherent task commit on codex/legacy-json-compatibility-20261013; no configured upstream or release/deploy performed; Linux evidence in /var/folders/c4/bcbjzcj556d3xj45z64rzjmw0000gn/T/ledger-legacy-linux-89qzh2ui/build.log `depends:LJ1,LJ2` `parallel:none`

- [x] LREL1 Published v0.1.1 from f8536d80aaf3dc9b6688ea640a387562fddc58da; tag and origin/main matched at tag push; both native CI targets and release assembler passed `depends:none` `parallel:none`
- [x] LREL2 Downloaded and verified both immutable archives, manifests and hashes with the upstream assembler; Formula matches the verified generated v0.1.1 asset `depends:LREL1` `parallel:none`

- [x] EG1 Define opt-in generation-bound append, replay precedence, caller revalidation and sticky uncertain outcomes; latest origin/main base explicitly authorized `depends:none` `parallel:none`
- [x] EG2 Implement CLI parsing and conditional append; generation races, replay, legacy and actual cloud request construction verified; native Swift 6.4.0 package run passed all 37 tests and release binary smoke passed `depends:EG1` `parallel:none`
- [x] EG3 Scoped review passed; Swift 6.4.0 macOS 37 tests/release smoke and Linux 37 tests/static amd64 smoke passed, plus 5 packaging tests; evidence in .build/expected-generation-native.log and .build/expected-generation-linux.log; coherent task commit on codex/ledger-expected-generation-20261028, no upstream configured or release/deploy performed `depends:EG2` `parallel:none`

- [x] EGR1 Released v0.2.0 from 2dd06d5a3b332a8790cda2697c65cac82667e7a1 after both native CI builds and assembly passed; tag and origin/main matched at tag push; release workflow 40681339246 passed `depends:EG3` `parallel:none`
- [x] EGR2 Downloaded published archives and verified tag/source, archive and executable checksums, member lists and manifests with the assembler; both published binaries passed standalone smoke; Formula matches the verified v0.2.0 asset `depends:EGR1` `parallel:none`
