struct ExpectedGeneration: Sendable {
    let rawValue: String

    init(_ rawValue: String) throws {
        guard let first = rawValue.utf8.first,
              rawValue.utf8.allSatisfy({ (48...57).contains($0) }),
              rawValue == "0" || first != 48 else {
            throw CLIError(code: "invalid_input", message: "The expected generation must be 0 or a canonical positive decimal string.")
        }
        self.rawValue = rawValue
    }
}
