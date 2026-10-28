struct CommandArguments {
    static let usage = "Usage: ledger append <absolute-jsonl-path> --id <uuid> [--expected-generation <generation>] < record.json"

    let path: String
    let operationID: String
    let expectedGeneration: ExpectedGeneration?

    init(_ arguments: [String]) throws {
        guard arguments.count == 4 || arguments.count == 6,
              arguments[0] == "append" else {
            throw CLIError(code: "invalid_input", message: Self.usage)
        }
        var operationID: String?
        var expectedGeneration: ExpectedGeneration?
        for index in stride(from: 2, to: arguments.count, by: 2) {
            switch arguments[index] {
            case "--id" where operationID == nil:
                operationID = arguments[index + 1]
            case "--expected-generation" where expectedGeneration == nil:
                expectedGeneration = try ExpectedGeneration(arguments[index + 1])
            default:
                throw CLIError(code: "invalid_input", message: Self.usage)
            }
        }
        guard let operationID else {
            throw CLIError(code: "invalid_input", message: Self.usage)
        }
        self.path = arguments[1]
        self.operationID = operationID
        self.expectedGeneration = expectedGeneration
    }
}
