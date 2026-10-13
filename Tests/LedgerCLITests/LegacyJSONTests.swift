import Foundation
import Testing
@testable import LedgerCLI

@Suite(.timeLimit(.minutes(1)))
struct LegacyJSONTests {
    private let legacy = Data("  {\n  \"number\": 9007199254740993123456789,\n  \"decimal\": 1.2300e+99,\n  \"text\": \"日本語 \\\"quoted\\\" \\n\",\n  \"empty\": {}\n}\n".utf8)
    private let compact = Data("{\"number\":9007199254740993123456789,\"decimal\":1.2300e+99,\"text\":\"日本語 \\\"quoted\\\" \\n\",\"empty\":{}}".utf8)

    @Test func legacyPayloadAndNewRecordCommitTogether() async throws {
        let store = LegacyStore(bytes: legacy)
        let item = try record()
        let receipt = try await writer(store).append(item, budget: Budget(seconds: 5))
        let saved = try await store.read(budget: Budget(seconds: 5))
        #expect(receipt.status == "appended")
        #expect(saved.bytes.suffix(item.line.count) == item.line)
        let lines = saved.bytes.split(separator: 10)
        #expect(lines.count == 2)
        let expectedTail = Data("\"data\":".utf8) + compact + Data([125])
        #expect(Data(lines[0]).suffix(expectedTail.count) == expectedTail)
        #expect(try item.isPresent(in: saved.bytes))
        #expect(await store.writes == 1)
        #expect(await store.preconditions == ["7"])
    }

    @Test func concurrentLegacyAppendsPreserveOneBaselineAndBothAdditions() async throws {
        let store = LegacyStore(bytes: legacy, barrier: true)
        let a = try record(), b = try record("{\"b\":true}")
        async let first = writer(store).append(a, budget: Budget(seconds: 5))
        async let second = writer(store).append(b, budget: Budget(seconds: 5))
        _ = try await (first, second)
        let saved = try await store.read(budget: Budget(seconds: 5))
        #expect(saved.bytes.filter { $0 == 10 }.count == 3)
        #expect(try a.isPresent(in: saved.bytes))
        #expect(try b.isPresent(in: saved.bytes))
        #expect(await store.conflicts == 1)
    }

    @Test func lostAcknowledgmentAndReplayRetainOneMigration() async throws {
        let store = LegacyStore(bytes: legacy, loseAcknowledgment: true)
        let item = try record()
        let result = try await writer(store, attempts: 1).append(item, budget: Budget(seconds: 5))
        #expect(result.status == "already_present")
        let before = try await store.read(budget: Budget(seconds: 5))
        let replay = try await writer(store).append(item, budget: Budget(seconds: 5))
        #expect(replay.status == "already_present")
        #expect(replay.generation == before.generation)
        #expect(await store.writes == 1)
        let after = try await store.read(budget: Budget(seconds: 5))
        #expect(after.bytes == before.bytes)
    }

    @Test func rejectsMalformedSnapshotsAndEnvelopeCandidatesWithoutWriting() async throws {
        let item = try record()
        let malformed = [
            Data("{\"x\":1,\"x\":2}".utf8), Data("{\"x\":NaN}".utf8),
            Data("[]".utf8), Data("{}\n{}\n".utf8), Data([123, 255, 125]),
            Data("{\"id\":\"not-an-envelope\"}\n".utf8),
            Data("{\"hash\":\"broken\",\"data\":{}}\n".utf8),
            item.line.dropLast(), item.line + item.line,
        ]
        for bytes in malformed {
            let store = LegacyStore(bytes: bytes)
            do {
                _ = try await writer(store).append(item, budget: Budget(seconds: 5))
                Issue.record("Invalid stored data must fail")
            } catch let error as CLIError {
                #expect(error.code == "invalid_log")
                #expect(error.retryAction == "stop")
                #expect(error.commitState == "not_written")
            }
            #expect(await store.writes == 0)
            let saved = try await store.read(budget: Budget(seconds: 5))
            #expect(saved.bytes == bytes)
        }
    }

    @Test func conversionOverheadRespectsFileLimitBeforeUpload() async throws {
        let store = LegacyStore(bytes: Data("{}".utf8))
        let item = try record()
        let small = Appender(store: store, maxFileBytes: item.line.count + 2, maxAttempts: 1)
        do {
            _ = try await small.append(item, budget: Budget(seconds: 5))
            Issue.record("Conversion overhead must count toward the file limit")
        } catch let error as CLIError {
            #expect(error.code == "limit_exceeded")
            #expect(error.stage == "prepare_append")
            #expect(try #require(error.actual) > UInt64(item.line.count + 2))
        }
        #expect(await store.writes == 0)
    }

    @Test func deterministicLegacyIdentityNeverAcknowledgesUncommittedData() async throws {
        let normalized = try JSONRecord.normalizedLog(legacy)
        #expect(try normalized == JSONRecord.normalizedLog(compact))
        let envelope = try #require(JSONSerialization.jsonObject(with: normalized) as? [String: Any])
        let id = try #require(envelope["id"] as? String)
        let colliding = try JSONRecord(input: compact, id: id, limit: 65536)
        #expect(normalized == colliding.line)
        let store = LegacyStore(bytes: legacy)
        do {
            _ = try await writer(store).append(colliding, budget: Budget(seconds: 5))
            Issue.record("A derived baseline ID must not acknowledge an uncommitted snapshot")
        } catch let error as CLIError { #expect(error.code == "id_conflict") }
        #expect(await store.writes == 0)
    }

    @Test func unchangedJSONLRetainsItsBytesAndDepthLimitsRemainStrict() throws {
        let item = try record()
        #expect(try JSONRecord.normalizedLog(item.line) == item.line)
        let deepest = String(repeating: "{\"x\":", count: 63) + "{}" + String(repeating: "}", count: 63)
        let baseline = try record(deepest)
        #expect(try baseline.isPresent(in: JSONRecord.normalizedLog(Data(deepest.utf8))) == false)
        #expect(throws: CLIError.self) {
            try JSONRecord.normalizedLog(Data(("{\"x\":" + deepest + "}").utf8))
        }
    }

    @Test func expiredBudgetCannotConvertOrWrite() async throws {
        let store = LegacyStore(bytes: legacy)
        await #expect(throws: CLIError.self) {
            try await writer(store).append(record(), budget: Budget(seconds: 0))
        }
        #expect(await store.writes == 0)
    }

    private func record(_ text: String = "{\"new\":true}") throws -> JSONRecord {
        try JSONRecord(input: Data(text.utf8), id: UUID().uuidString, limit: 65536)
    }

    private func writer(_ store: LegacyStore, attempts: Int = 8) -> Appender {
        Appender(store: store, maxFileBytes: 65536, maxAttempts: attempts)
    }
}

private actor LegacyStore: ObjectStore {
    private var bytes: Data
    private var generation = 7
    private var barrier: Bool
    private var waiter: CheckedContinuation<Void, Never>?
    private var loseAcknowledgment: Bool
    private(set) var writes = 0
    private(set) var conflicts = 0
    private(set) var preconditions: [String] = []

    init(bytes: Data, barrier: Bool = false, loseAcknowledgment: Bool = false) {
        self.bytes = bytes
        self.barrier = barrier
        self.loseAcknowledgment = loseAcknowledgment
    }

    func read(budget: Budget) async throws -> Snapshot {
        let snapshot = Snapshot(generation: String(generation), bytes: bytes)
        if barrier {
            if let waiter { self.waiter = nil; barrier = false; waiter.resume() }
            else { await withCheckedContinuation { waiter = $0 } }
        }
        return snapshot
    }

    func put(_ bytes: Data, generation: String, budget: Budget) async throws -> PutResult {
        preconditions.append(generation)
        if generation != String(self.generation) { conflicts += 1; return .conflict }
        self.bytes = bytes
        self.generation += 1
        writes += 1
        if loseAcknowledgment { loseAcknowledgment = false; throw CLIError(code: "io_error") }
        return .committed(String(self.generation))
    }
}
