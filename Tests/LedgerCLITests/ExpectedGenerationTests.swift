import Foundation
import Testing
@testable import LedgerCLI

@Suite(.timeLimit(.minutes(1)))
struct ExpectedGenerationTests {
    @Test func argumentsAcceptBothOptionOrdersAndCanonicalGenerationStrings() throws {
        let id = UUID().uuidString
        let ordinary = try CommandArguments(["append", "/mount/graph.jsonl", "--id", id])
        #expect(ordinary.expectedGeneration == nil)
        for value in ["0", "1", "184467440737095516160000"] {
            for options in [["--id", id, "--expected-generation", value], ["--expected-generation", value, "--id", id]] {
                let parsed = try CommandArguments(["append", "/mount/graph.jsonl"] + options)
                #expect(parsed.path == "/mount/graph.jsonl")
                #expect(parsed.operationID == id)
                #expect(parsed.expectedGeneration?.rawValue == value)
            }
        }
        for value in ["", "00", "01", "-1", "+1", " 1", "1 ", "1.0", "1e3", "１"] {
            #expect(throws: CLIError.self) { try ExpectedGeneration(value) }
        }
        for options in [["--id", id, "--id", id], ["--expected-generation", "0", "--expected-generation", "1"],
                        ["--id", id, "--unknown", "0"], ["--expected-generation", "0"], ["--id", id, "--expected-generation"]] {
            #expect(throws: CLIError.self) { try CommandArguments(["append", "/mount/graph.jsonl"] + options) }
        }
    }

    @Test func matchingGenerationAndCreationPreserveExactBytes() async throws {
        for generation in [0, 7] {
            let store = GenerationStore(generation: generation)
            let item = try record("{\"number\":900719925474099312345,\"decimal\":1.2300e+99}")
            let expected = try ExpectedGeneration(String(generation))
            let result = try await writer(store).append(item, expectedGeneration: expected, budget: Budget(seconds: 5))
            #expect(result.status == "appended")
            #expect(await store.preconditions == [String(generation)])
            #expect(await store.bytes == item.line)
            #expect(await store.writes == 1)
        }
    }

    @Test func staleAndAbsentGenerationsNeverUpload() async throws {
        for (generation, expected) in [(7, "6"), (7, "0"), (0, "7")] {
            let store = GenerationStore(generation: generation)
            let item = try record()
            let condition = try ExpectedGeneration(expected)
            do {
                _ = try await writer(store).append(item, expectedGeneration: condition, budget: Budget(seconds: 5))
                Issue.record("A stale generation must fail before upload")
            } catch let error as CLIError {
                #expect(error.code == "generation_mismatch")
                #expect(error.retryAction == "revalidate")
                #expect(error.commitState == "not_written")
                #expect(error.exitCode == 4)
                #expect(error.stage == "validate_generation")
            }
            #expect(await store.preconditions.isEmpty)
            #expect(await store.bytes.isEmpty)
        }
    }

    @Test func replayPrecedesGenerationCheckAndDifferentBytesStillFail() async throws {
        let first = try record(), unrelated = try record("{\"unrelated\":true}")
        let store = GenerationStore(generation: 9, bytes: first.line + unrelated.line)
        let expected = try ExpectedGeneration("7")
        let result = try await writer(store).append(first, expectedGeneration: expected, budget: Budget(seconds: 5))
        #expect(result.status == "already_present")
        #expect(result.generation == "9")
        let changed = try record("{\"changed\":true}", id: first.id)
        do {
            _ = try await writer(store).append(changed, expectedGeneration: expected, budget: Budget(seconds: 5))
            Issue.record("Changed operation bytes must fail")
        } catch let error as CLIError { #expect(error.code == "id_conflict") }
        #expect(await store.preconditions.isEmpty)
        #expect(await store.bytes == first.line + unrelated.line)
    }

    @Test func concurrentConditionalAppendsDoNotRebaseTheLosingWrite() async throws {
        let store = GenerationStore(generation: 7, barrier: true)
        let first = try record(), second = try record("{\"second\":true}")
        let expected = try ExpectedGeneration("7")
        async let a = outcome(first, store: store, expected: expected)
        async let b = outcome(second, store: store, expected: expected)
        let results = await [a, b]
        #expect(results.sorted() == ["appended", "generation_mismatch"])
        #expect(await store.writes == 1)
        #expect(await store.conflicts == 1)
        #expect(await store.preconditions == ["7", "7"])
        let bytes = await store.bytes
        #expect(bytes == first.line || bytes == second.line)
    }

    @Test func confirmedLostAcknowledgmentReplaysAtANewerGeneration() async throws {
        let store = GenerationStore(generation: 7, loseFirstUpload: true, commitLostUpload: true)
        let item = try record()
        let expected = try ExpectedGeneration("7")
        let result = try await writer(store, attempts: 1).append(item, expectedGeneration: expected, budget: Budget(seconds: 5))
        #expect(result.status == "already_present")
        #expect(result.generation == "8")
        #expect(await store.preconditions == ["7"])
        #expect(await store.bytes == item.line)
    }

    @Test func uncertainUploadThenGenerationChangeNeverClaimsNotWritten() async throws {
        let competing = try record("{\"competing\":true}")
        let store = GenerationStore(generation: 7, loseFirstUpload: true, competingAfterLoss: competing.line)
        let item = try record()
        let expected = try ExpectedGeneration("7")
        do {
            _ = try await writer(store).append(item, expectedGeneration: expected, budget: Budget(seconds: 5))
            Issue.record("Unresolved commitment must remain unknown")
        } catch let error as CLIError {
            #expect(error.code == "outcome_unknown")
            #expect(error.commitState == "unknown")
            #expect(error.retryAction == "retry_same_request")
        }
        #expect(await store.preconditions == ["7"])
        #expect(await store.bytes == competing.line)
    }

    @Test func uncertainUploadRetriesOnlyTheOriginalGeneration() async throws {
        let store = GenerationStore(generation: 7, loseFirstUpload: true)
        let item = try record()
        let expected = try ExpectedGeneration("7")
        let result = try await writer(store).append(item, expectedGeneration: expected, budget: Budget(seconds: 5))
        #expect(result.status == "appended")
        #expect(await store.preconditions == ["7", "7"])
        #expect(await store.bytes == item.line)
    }

    @Test func uncertainUploadThenConditionalRejectionRemainsUnknown() async throws {
        let store = GenerationStore(generation: 7, loseFirstUpload: true, rejectAfterLoss: true)
        let item = try record()
        let expected = try ExpectedGeneration("7")
        do {
            _ = try await writer(store).append(item, expectedGeneration: expected, budget: Budget(seconds: 5))
            Issue.record("A later definite rejection cannot erase an unresolved upload")
        } catch let error as CLIError {
            #expect(error.code == "outcome_unknown")
            #expect(error.commitState == "unknown")
            #expect(error.stage == "upload")
        }
        #expect(await store.preconditions == ["7", "7"])
        #expect(await store.bytes.isEmpty)
    }

    @Test func legacyConversionIsBoundToTheObservedGeneration() async throws {
        let legacy = Data("{\n\"number\": 900719925474099312345\n}\n".utf8)
        let item = try record()
        let store = GenerationStore(generation: 7, bytes: legacy)
        let expected = try ExpectedGeneration("7")
        let result = try await writer(store).append(item, expectedGeneration: expected, budget: Budget(seconds: 5))
        #expect(result.status == "appended")
        let baseline = try JSONRecord.normalizedLog(legacy)
        #expect(await store.bytes == baseline + item.line)
        #expect(await store.preconditions == ["7"])
        let stale = GenerationStore(generation: 8, bytes: legacy)
        await #expect(throws: CLIError.self) {
            try await writer(stale).append(item, expectedGeneration: expected, budget: Budget(seconds: 5))
        }
        #expect(await stale.bytes == legacy)
        #expect(await stale.preconditions.isEmpty)
    }

    @Test func corruptLogAndExpiredBudgetCannotWrite() async throws {
        let store = GenerationStore(generation: 7, bytes: Data("{\"broken\":}".utf8))
        let item = try record()
        let expected = try ExpectedGeneration("7")
        do {
            _ = try await writer(store).append(item, expectedGeneration: expected, budget: Budget(seconds: 5))
            Issue.record("Corruption must remain explicit")
        } catch let error as CLIError { #expect(error.code == "invalid_log") }
        await #expect(throws: CLIError.self) {
            try await writer(store).append(item, expectedGeneration: expected, budget: Budget(seconds: 0))
        }
        #expect(await store.preconditions.isEmpty)
    }

    private func record(_ text: String = "{\"new\":true}", id: String = UUID().uuidString) throws -> JSONRecord {
        try JSONRecord(input: Data(text.utf8), id: id, limit: 65536)
    }
    private func writer(_ store: GenerationStore, attempts: Int = 5) -> Appender {
        Appender(store: store, maxFileBytes: 65536, maxAttempts: attempts)
    }
    private func outcome(_ item: JSONRecord, store: GenerationStore, expected: ExpectedGeneration) async -> String {
        do {
            return try await writer(store).append(item, expectedGeneration: expected, budget: Budget(seconds: 5)).status
        } catch let error as CLIError { return error.code }
        catch { Issue.record(error); return "unexpected_error" }
    }
}

private actor GenerationStore: ObjectStore {
    var bytes: Data
    private var generation: Int
    private var barrier: Bool
    private var waiter: CheckedContinuation<Void, Never>?
    private var loseFirstUpload: Bool
    private let commitLostUpload: Bool
    private let competingAfterLoss: Data?
    private let rejectAfterLoss: Bool
    private(set) var writes = 0
    private(set) var conflicts = 0
    private(set) var preconditions: [String] = []

    init(generation: Int, bytes: Data = Data(), barrier: Bool = false, loseFirstUpload: Bool = false,
         commitLostUpload: Bool = false, competingAfterLoss: Data? = nil, rejectAfterLoss: Bool = false) {
        self.generation = generation; self.bytes = bytes; self.barrier = barrier
        self.loseFirstUpload = loseFirstUpload; self.commitLostUpload = commitLostUpload
        self.competingAfterLoss = competingAfterLoss
        self.rejectAfterLoss = rejectAfterLoss
    }
    func read(budget: Budget) async throws -> Snapshot {
        let snapshot = Snapshot(generation: String(generation), bytes: bytes)
        if barrier {
            if let waiter { self.waiter = nil; barrier = false; waiter.resume() }
            else { await withCheckedContinuation { waiter = $0 } }
        }
        return snapshot
    }
    func put(_ next: Data, generation: String, budget: Budget) async throws -> PutResult {
        preconditions.append(generation)
        if generation != String(self.generation) { conflicts += 1; return .conflict }
        if loseFirstUpload {
            loseFirstUpload = false
            if commitLostUpload { bytes = next; self.generation += 1; writes += 1 }
            if let competingAfterLoss { bytes.append(competingAfterLoss); self.generation += 1 }
            throw CLIError(code: "io_error")
        }
        if rejectAfterLoss { return .conflict }
        bytes = next; self.generation += 1; writes += 1
        return .committed(String(self.generation))
    }
}
