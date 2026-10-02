# Progress
- [x] CLI1 Extract generic JSONL append CLI with existing payload/CAS/error contracts; own Swift 6.4.0 producer, behavioral tests and independent CI; MIT license; generic ledger/LEDGER_CONFIG boundary; unchanged append engine; 8 native Swift tests and actual CLI validation feedback passed `depends:none` `parallel:none`
- [ ] CLI2 Verify native Linux tests, static Linux amd64 binary and failure feedback in independent CI; fix the HTTP fixture inherited SIGTERM mask proven to block Linux test cleanup; record commit and artifact provenance `depends:CLI1` `parallel:none`
