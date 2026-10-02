import Foundation
import Testing
@testable import LedgerCLI

@Suite(.timeLimit(.minutes(1)))
struct AppendTests {
    func record(_ text: String = "{\"n\":9007199254740993}", id: String = UUID().uuidString) throws -> JSONRecord {
        try JSONRecord(input: Data(text.utf8), id: id, limit: 65536)
    }

    @Test func concurrentCreationPreservesBothRecords() async throws {
        let store = MemoryStore(barrier: true)
        let a = try record(), b = try record("{\"b\":true}")
        let writer = Appender(store: store, maxFileBytes: 65536, maxAttempts: 8)
        async let first = writer.append(a, budget: Budget(seconds: 5))
        async let second = writer.append(b, budget: Budget(seconds: 5))
        _ = try await (first, second)
        let saved = try await store.read(budget: Budget(seconds: 5))
        #expect(try a.isPresent(in: saved.bytes))
        #expect(try b.isPresent(in: saved.bytes))
        #expect(saved.bytes.filter { $0 == 10 }.count == 2)
        #expect(await store.conflicts == 1)
    }

    @Test func lostAcknowledgmentAndReplayDoNotDuplicate() async throws {
        let store = MemoryStore(loseAcknowledgment: true)
        let item = try record()
        let writer = Appender(store: store, maxFileBytes: 65536, maxAttempts: 1)
        let first = try await writer.append(item, budget: Budget(seconds: 5))
        #expect(first.status == "already_present")
        let replay = try await writer.append(item, budget: Budget(seconds: 5))
        #expect(replay.generation == first.generation)
        let different = try record("{\"n\":2}", id: item.id)
        await #expect(throws: (any Error).self) {
            do { _ = try await writer.append(different, budget: Budget(seconds: 5)) }
            catch let error as CLIError { #expect(error.code == "id_conflict"); throw error }
        }
        #expect(await store.writes == 1)
    }

    @Test func rejectionAndUnknownOutcomeAreDifferent() async throws {
        let item = try record()
        for mode in [FailureStore.Mode.denied, .unknown, .contention] {
            let writer = Appender(store: FailureStore(mode: mode), maxFileBytes: 65536, maxAttempts: 1)
            do { _ = try await writer.append(item, budget: Budget(seconds: 5)); Issue.record("Expected failure") }
            catch let error as CLIError {
                #expect(error.code == (mode == .denied ? "access_denied" : mode == .unknown ? "outcome_unknown" : "contention"))
                #expect(error.commitState == (mode == .unknown ? "unknown" : "not_written"))
                #expect(error.retryAction == (mode == .denied ? "stop" : "retry_same_request"))
            }
        }
    }

    @Test func framingAndNumericBytesArePreserved() throws {
        let text = "{\"number\":9007199254740993123456789,\"decimal\":1.2300e+99,\"s\":\"日本語\\n\"}"
        let item = try record(text + "\n")
        #expect(item.bytes == Data(text.utf8))
        #expect(try item.isPresent(in: item.line))
        let deepest = String(repeating: "{\"x\":", count: 63) + "{}" + String(repeating: "}", count: 63)
        let nested = try record(deepest)
        #expect(try nested.isPresent(in: nested.line))
        #expect(throws: (any Error).self) { try record("{\"x\":" + deepest + "}") }
        for bad in ["{}\n{}", " { }", "{\"x\":1,\"x\":2}", "{\"x\":{\"a\":1,\"\\u0061\":2}}", "{\"x\":01}", "{\"x\":NaN}", "{\"x\":\"\\q\"}", "{\"x\":\"\\uD800\"}", "[]"] {
            #expect(throws: (any Error).self) { try record(bad) }
        }
        #expect(throws: (any Error).self) { try JSONRecord(input: Data([123, 255, 125]), id: UUID().uuidString, limit: 100) }
        #expect(throws: (any Error).self) { try item.isPresent(in: item.line.dropLast()) }
        #expect(throws: (any Error).self) { try item.isPresent(in: item.line + item.line) }
        let corrupted = Data(String(decoding: item.line, as: UTF8.self).replacingOccurrences(of: "1.2300e+99", with: "1.2301e+99").utf8)
        #expect(throws: (any Error).self) { try item.isPresent(in: corrupted) }
    }

    @Test func diagnosticsLocateInputAndStoredLogErrors() throws {
        do { _ = try record("{\"x\":1,\"x\":2}"); Issue.record("Expected duplicate rejection") }
        catch let error as CLIError {
            #expect(error.message.contains("Duplicate"))
            #expect(error.location?.byteOffset == 7)
            #expect(error.location?.source == "input")
            #expect(error.retryAction == "correct_input")
        }
        let item = try record()
        let prefix = "{\"id\":\"\(item.id)\",\"hash\":\"\(JSONRecord.digest(Data("[]".utf8)))\",\"data\":"
        do { _ = try item.isPresent(in: Data((prefix + "[]}\n").utf8)); Issue.record("Expected object payload rejection") }
        catch let error as CLIError {
            #expect(error.location?.byteOffset == prefix.utf8.count)
            #expect(error.code == "invalid_log")
        }
        do { _ = try item.isPresent(in: item.line + Data("{\"id\":}\n".utf8)); Issue.record("Expected corrupt log") }
        catch let error as CLIError {
            #expect(error.code == "invalid_log")
            #expect(error.location?.line == 2)
            #expect(error.location?.byteOffset == 6)
            #expect(error.location?.source == "log")
            #expect(error.retryAction == "stop")
        }
    }

    @Test func sizeLimitDoesNotWrite() async throws {
        let store = MemoryStore()
        let item = try record()
        let writer = Appender(store: store, maxFileBytes: item.line.count - 1, maxAttempts: 1)
        do { _ = try await writer.append(item, budget: Budget(seconds: 5)); Issue.record("Expected limit failure") }
        catch let error as CLIError {
            #expect(error.code == "limit_exceeded")
            #expect(error.limit == UInt64(item.line.count - 1))
            #expect(error.actual == UInt64(item.line.count))
            #expect(error.stage == "prepare_append")
            #expect(error.retryAction == "stop")
        }
        #expect(await store.writes == 0)
    }

    @Test func pathsRejectAliasesAndAllowSeveralGraphs() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record("Cleanup failed") } }
        let canonical = root.resolvingSymlinksInPath().path
        let config = Configuration(mountRoot: canonical, bucket: "test-bucket", maxRecordBytes: 1024, maxFileBytes: 65536, maxAttempts: 5, timeoutSeconds: 5, accessTokenFile: nil)
        try config.validate()
        let fileRoot = canonical + "/file"
        try Data().write(to: URL(fileURLWithPath: fileRoot))
        let invalidRoot = Configuration(mountRoot: fileRoot, bucket: "test-bucket", maxRecordBytes: 1024, maxFileBytes: 65536, maxAttempts: 5, timeoutSeconds: 5, accessTokenFile: nil)
        #expect(throws: (any Error).self) { try invalidRoot.validate() }
        #expect(try config.objectName(for: canonical + "/a/graph.jsonl") == "a/graph.jsonl")
        #expect(try config.objectName(for: canonical + "/b/graph.jsonl") == "b/graph.jsonl")
        try FileManager.default.createSymbolicLink(atPath: canonical + "/alias", withDestinationPath: "/tmp")
        for path in [canonical + "/../escape.jsonl", canonical + "/a//b.jsonl", canonical + "/alias/graph.jsonl", canonical + "-other/g.jsonl", "/tmp/g.jsonl"] {
            #expect(throws: (any Error).self) { try config.objectName(for: path) }
        }
    }
}

private actor MemoryStore: ObjectStore {
    var bytes = Data()
    var generation = 0
    var conflicts = 0
    var writes = 0
    var barrier: Bool
    var waiter: CheckedContinuation<Void, Never>?
    var loseAcknowledgment: Bool
    init(barrier: Bool = false, loseAcknowledgment: Bool = false) {
        self.barrier = barrier; self.loseAcknowledgment = loseAcknowledgment
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
        if generation != String(self.generation) { conflicts += 1; return .conflict }
        self.bytes = bytes; self.generation += 1; writes += 1
        if loseAcknowledgment { loseAcknowledgment = false; throw CLIError(code: "io_error") }
        return .committed(String(self.generation))
    }
}

private actor FailureStore: ObjectStore {
    enum Mode { case denied, unknown, contention }
    let mode: Mode
    var reads = 0
    init(mode: Mode) { self.mode = mode }
    func read(budget: Budget) async throws -> Snapshot {
        reads += 1
        if mode == .unknown && reads > 1 { throw CLIError(code: "access_denied") }
        return Snapshot(generation: "0", bytes: Data())
    }
    func put(_ bytes: Data, generation: String, budget: Budget) async throws -> PutResult {
        if mode == .denied { throw WriteRejected(failure: CLIError(code: "access_denied")) }
        if mode == .contention { return .conflict }
        throw CLIError(code: "io_error")
    }
}
