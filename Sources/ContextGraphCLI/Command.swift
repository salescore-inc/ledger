import Foundation
#if canImport(Musl)
import Musl
#elseif os(Linux)
import Glibc
#else
import Darwin
#endif

@main
struct Command {
    static func main() async {
        var stage = "arguments"
        var committed = false
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            if args == ["--help"] {
                print("Usage: contextgraph append <absolute-jsonl-path> --id <uuid> < record.json")
                print("Configuration: CONTEXTGRAPH_CONFIG or /etc/contextgraph.json")
                return
            }
            guard args.count == 4, args[0] == "append", args[2] == "--id" else { throw CLIError(code: "invalid_input", message: "Usage: contextgraph append <absolute-jsonl-path> --id <uuid> < record.json") }
            stage = "configuration"
            let configPath = ProcessInfo.processInfo.environment["CONTEXTGRAPH_CONFIG"] ?? "/etc/contextgraph.json"
            let configFile = try FileHandle(forReadingFrom: URL(fileURLWithPath: configPath))
            let configData = try configFile.read(upToCount: 65537) ?? Data()
            try configFile.close()
            guard configData.count <= 65536 else { throw CLIError(code: "invalid_config") }
            let config: Configuration
            do { config = try JSONDecoder().decode(Configuration.self, from: configData) }
            catch { throw CLIError(code: "invalid_config") }
            try config.validate()
            stage = "path"
            let object = try config.objectName(for: args[1])
            let budget = Budget(seconds: config.timeoutSeconds)
            stage = "input"
            let input = try readInput(limit: config.maxRecordBytes, budget: budget)
            let record = try JSONRecord(input: input, id: args[3], limit: config.maxRecordBytes)
            stage = "authentication"
            let token = try await CloudObjectStore.accessToken(configuration: config, budget: budget)
            let store = CloudObjectStore(bucket: config.bucket, object: object, token: token, maxFileBytes: config.maxFileBytes)
            stage = "append"
            let receipt = try await Appender(store: store, maxFileBytes: config.maxFileBytes, maxAttempts: config.maxAttempts).append(record, budget: budget)
            committed = true
            stage = "receipt"
            var output = try JSONEncoder().encode(receipt)
            output.append(10)
            try FileHandle.standardOutput.write(contentsOf: output)
        } catch {
            var failure = (error as? CLIError) ?? CLIError(code: "io_error")
            if failure.stage == nil { failure.stage = stage }
            if committed {
                failure.commitState = "committed"
                failure.message = "The append was confirmed, but writing its receipt failed. Retry the same ID and exact input to recover the receipt."
                failure.retryAction = "retry_same_request"
            } else if stage == "configuration" || stage == "authentication", failure.code == "io_error" {
                failure.retryAction = "stop"
                failure.message = "Runtime configuration or credential I/O failed; ask the runtime owner to check setup."
            }
            if failure.code == "limit_exceeded", stage == "input" {
                failure.retryAction = "correct_input"
                failure.message = "The input exceeds maxRecordBytes. Reduce it before retrying."
            }
            do {
                var output = try JSONEncoder().encode(failure)
                output.append(10)
                try FileHandle.standardError.write(contentsOf: output)
            }
            catch { /* The process exit code remains authoritative if stderr is closed. */ }
            exit(failure.exitCode)
        }
    }

    static func readInput(limit: Int, budget: Budget) throws -> Data {
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: min(65536, limit + 1))
        while true {
            try budget.check()
            var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, Int32(min(budget.remaining * 1000, 1000)))
            if ready < 0 {
                if errno == EINTR { continue }
                throw CLIError(code: "io_error")
            }
            if ready == 0 { continue }
            // The scoped buffer borrow never escapes read(), and capacity is bounded.
            let count = buffer.withUnsafeMutableBytes { read(STDIN_FILENO, $0.baseAddress, $0.count) }
            if count < 0 {
                if errno == EINTR { continue }
                throw CLIError(code: "io_error")
            }
            if count == 0 { return result }
            guard count <= limit - result.count else { throw CLIError.size(limit: limit, actual: result.count + count) }
            result.append(contentsOf: buffer.prefix(count))
        }
    }
}
