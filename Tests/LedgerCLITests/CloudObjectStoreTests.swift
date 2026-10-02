import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import LedgerCLI

@Suite(.timeLimit(.minutes(1)))
struct CloudObjectStoreTests {
    @Test func tokenFileChecksDeadlineAndCancellation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record("Cleanup failed") } }
        let path = root.appendingPathComponent("token.txt")
        try Data("test-only-token\n".utf8).write(to: path)
        let config = Configuration(mountRoot: root.path, bucket: "test-bucket", maxRecordBytes: 100, maxFileBytes: 1024, maxAttempts: 3, timeoutSeconds: 5, accessTokenFile: path.path)
        #expect(try await CloudObjectStore.accessToken(configuration: config, budget: Budget(seconds: 5)) == "test-only-token")
        do {
            _ = try await CloudObjectStore.accessToken(configuration: config, budget: Budget(seconds: 0))
            Issue.record("Expired authentication must fail")
        } catch let error as CLIError { #expect(error.code == "io_error") }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await CloudObjectStore.accessToken(configuration: config, budget: Budget(seconds: 5))
        }
        await #expect(throws: CancellationError.self) { _ = try await cancelled.value }
    }

    @Test func generationDisappearanceUsesOneReadPairAndTheAppendBudget() async throws {
        let fixture = StoreHTTPFixture(missingBodies: 100)
        let store = makeStore(fixture)
        do {
            _ = try await store.read(budget: Budget(seconds: 5))
            Issue.record("Disappearing generation must report contention")
        } catch let error as CLIError { #expect(error.code == "contention") }
        #expect(await fixture.count == 2)
        for attempts in [1, 3] {
            let appendFixture = StoreHTTPFixture(missingBodies: 100)
            let writer = Appender(store: makeStore(appendFixture), maxFileBytes: 1024, maxAttempts: attempts)
            do {
                _ = try await writer.append(record(), budget: Budget(seconds: 5))
                Issue.record("Repeated read conflicts must exhaust the attempt budget")
            } catch let error as CLIError {
                #expect(error.code == "contention")
                #expect(error.retryAction == "retry_same_request")
                #expect(error.commitState == "not_written")
            }
            #expect(await appendFixture.count == 2 * attempts)
            #expect(await appendFixture.uploads == 0)
        }
    }

    @Test func generationRaceRecoversAndPreservesConditionalUpload() async throws {
        let fixture = StoreHTTPFixture(missingBodies: 1)
        let writer = Appender(store: makeStore(fixture), maxFileBytes: 1024, maxAttempts: 3)
        let item = try record()
        let result = try await writer.append(item, budget: Budget(seconds: 5))
        #expect(result.status == "appended")
        #expect(result.generation == "3")
        #expect(await fixture.count == 5)
        #expect(await fixture.lastUpload == item.line)
    }

    @Test func unknownUploadStaysUnknownWhenLaterGenerationsDisappear() async throws {
        let fixture = StoreHTTPFixture(missingBodies: 0, loseUpload: true)
        let writer = Appender(store: makeStore(fixture), maxFileBytes: 1024, maxAttempts: 2)
        do {
            _ = try await writer.append(record(), budget: Budget(seconds: 5))
            Issue.record("Unresolved upload must remain unknown")
        } catch let error as CLIError {
            #expect(error.code == "outcome_unknown")
            #expect(error.commitState == "unknown")
            #expect(error.retryAction == "retry_same_request")
        }
        #expect(await fixture.count == 7)
        #expect(await fixture.uploads == 1)
    }

    private func makeStore(_ fixture: StoreHTTPFixture) -> CloudObjectStore {
        CloudObjectStore(bucket: "test-bucket", object: "folder/日本語 #?.jsonl", token: "test-only-token", maxFileBytes: 1024, send: { request, limit in
            try await fixture.send(request, limit: limit)
        })
    }

    private func record() throws -> JSONRecord {
        try JSONRecord(input: Data("{\"ok\":true}".utf8), id: UUID().uuidString, limit: 100)
    }
}

private actor StoreHTTPFixture {
    var count = 0
    var uploads = 0
    var lastUpload: Data?
    var metadataReads = 0
    var missingBodies: Int
    let loseUpload: Bool

    init(missingBodies: Int, loseUpload: Bool = false) {
        self.missingBodies = missingBodies; self.loseUpload = loseUpload
    }

    func send(_ request: URLRequest, limit: Int) throws -> HTTPResponse {
        count += 1
        // Bound a broken implementation's test requests rather than wait for its deadline.
        guard count <= 32 else { throw CLIError(code: "io_error") }
        let url = try #require(request.url)
        let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(parts.scheme == "https" && parts.host == "storage.googleapis.com")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-only-token")
        if request.httpMethod == "POST" {
            uploads += 1
            lastUpload = request.httpBody
            #expect(url.path == "/upload/storage/v1/b/test-bucket/o")
            #expect(query["name"] == "folder/日本語 #?.jsonl")
            #expect(query["ifGenerationMatch"] == String(metadataReads))
            #expect(query["uploadType"] == "media")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-ndjson")
            if loseUpload { throw CLIError(code: "io_error") }
            return HTTPResponse(status: 200, body: Data("{\"generation\":\"\(metadataReads + 1)\"}".utf8))
        }
        #expect(url.path == "/storage/v1/b/test-bucket/o/folder/日本語 #?.jsonl")
        if query["alt"] == "media" {
            #expect(query["generation"] == String(metadataReads))
            if missingBodies > 0 || (loseUpload && uploads > 0) {
                missingBodies -= 1
                return HTTPResponse(status: 404, body: Data())
            }
            return HTTPResponse(status: 200, body: Data())
        }
        metadataReads += 1
        #expect(query["fields"] == "generation,size")
        return HTTPResponse(status: 200, body: Data("{\"generation\":\"\(metadataReads)\",\"size\":\"0\"}".utf8))
    }
}
