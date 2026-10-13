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
        let portFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        process.arguments = ["python3", script.path, portFile.path]
        try process.run()
        defer {
            process.terminate(); process.waitUntilExit()
            if FileManager.default.fileExists(atPath: portFile.path) {
                do { try FileManager.default.removeItem(at: portFile) }
                catch { Issue.record("Fixture port-file cleanup failed") }
            }
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !FileManager.default.fileExists(atPath: portFile.path) {
            guard process.isRunning, ContinuousClock.now < deadline else {
                #if os(macOS)
                let sampleFile = portFile.appendingPathExtension("sample")
                let diagnostic = Process()
                diagnostic.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
                diagnostic.arguments = [String(process.processIdentifier), "1", "-file", sampleFile.path]
                try diagnostic.run()
                diagnostic.waitUntilExit()
                if FileManager.default.fileExists(atPath: sampleFile.path) {
                    let sample = try String(contentsOf: sampleFile, encoding: .utf8)
                    try FileHandle.standardError.write(contentsOf: Data(sample.utf8))
                    try FileManager.default.removeItem(at: sampleFile)
                }
                #endif
                throw CLIError(code: "io_error", message: "HTTP fixture did not start within five seconds.")
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let port = try String(contentsOf: portFile, encoding: .utf8)
        #expect(Int(port) != nil)
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
