import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import LedgerCLI

@Suite(.timeLimit(.minutes(1)))
struct HTTPTests {
    @Test func boundsRedirectsTimeoutAndCancellation() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("scripts/http-fixture.py")
        process.arguments = ["python3", script.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        defer { process.terminate(); process.waitUntilExit() }
        var portBytes = Data()
        while let byte = try pipe.fileHandleForReading.read(upToCount: 1), !byte.isEmpty {
            if byte.first == 10 { break }
            portBytes.append(byte)
        }
        let port = try #require(String(data: portBytes, encoding: .utf8))
        func request(_ path: String, timeout: Double = 2) -> URLRequest {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/\(path)")!)
            request.timeoutInterval = timeout
            request.setValue("Bearer test-only", forHTTPHeaderField: "Authorization")
            return request
        }
        let ok = try await HTTPTransport.send(request("ok"), limit: 10)
        #expect(ok.status == 200 && ok.body.count == 2)
        let redirect = try await HTTPTransport.send(request("redirect"), limit: 10)
        #expect(redirect.status == 302)
        for path in ["length", "body"] {
            do { _ = try await HTTPTransport.send(request(path), limit: 10); Issue.record("Expected size rejection") }
            catch let error as CLIError { #expect(error.code == "limit_exceeded") }
        }
        await #expect(throws: (any Error).self) {
            _ = try await HTTPTransport.send(request("slow", timeout: 0.2), limit: 10)
        }
        let task = Task { try await HTTPTransport.send(request("slow"), limit: 10) }
        task.cancel()
        await #expect(throws: (any Error).self) { _ = try await task.value }
    }
}
