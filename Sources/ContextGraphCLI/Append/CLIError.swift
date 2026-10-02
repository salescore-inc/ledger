import Foundation

struct CLIError: Error, Sendable, Encodable {
    struct Location: Sendable, Encodable {
        let source: String
        let line: Int
        let byteOffset: Int
    }

    let code: String
    var message: String
    var retryAction: String
    var commitState: String
    var stage: String?
    var location: Location?
    var limit: UInt64?
    var actual: UInt64?

    init(code: String, message: String? = nil, location: Location? = nil,
         limit: UInt64? = nil, actual: UInt64? = nil) {
        self.code = code
        self.location = location
        self.limit = limit
        self.actual = actual
        self.commitState = code == "outcome_unknown" ? "unknown" : "not_written"
        switch code {
        case "invalid_input":
            self.message = "Provide one valid UTF-8 JSON object on one line and a valid operation UUID."
            retryAction = "correct_input"
        case "invalid_path":
            self.message = "Use an absolute .jsonl path inside the configured mount, without traversal or symlink aliases."
            retryAction = "correct_input"
        case "invalid_config":
            self.message = "The runtime configuration is invalid; ask the runtime owner to correct it."
            retryAction = "stop"
        case "invalid_log":
            self.message = "The existing JSONL log is invalid; ask its owner to repair it before appending."
            retryAction = "stop"
        case "id_conflict":
            self.message = "This operation ID already has different data. Recover its original input; do not blindly retry with a new ID."
            retryAction = "stop"
        case "contention":
            self.message = "Concurrent writes exhausted the attempt budget. Retry with backoff using the same ID and exact input."
            retryAction = "retry_same_request"
        case "outcome_unknown":
            self.message = "An upload may have committed. Retry only with the same ID and exact input to confirm it."
            retryAction = "retry_same_request"
        case "access_denied":
            self.message = "Storage authentication or authorization failed; ask the runtime owner to check workload permissions."
            retryAction = "stop"
        case "limit_exceeded":
            self.message = "A byte limit was exceeded; check the stage and limits before retrying."
            retryAction = "stop"
        default:
            self.message = "An I/O operation failed. Retry with backoff using the same ID and exact input; persistent failure needs operator attention."
            retryAction = "retry_same_request"
        }
        if let message { self.message = message }
    }

    var exitCode: Int32 {
        switch code {
        case "invalid_input", "invalid_path", "invalid_config": 2
        case "id_conflict", "invalid_log": 3
        case "contention": 4
        case "outcome_unknown": 6
        default: 5
        }
    }
    static let invalidInput = CLIError(code: "invalid_input")
    static let invalidLog = CLIError(code: "invalid_log")
    static func size(limit: Int, actual: Int) -> CLIError {
        CLIError(code: "limit_exceeded", limit: UInt64(limit), actual: UInt64(actual))
    }
}
