import Foundation
import Crypto

/// Validates JSON lexically so payload numbers are never converted or re-encoded.
struct JSONRecord {
    let bytes: Data
    let id: String
    let hash: String

    init(input: Data, id: String, limit: Int) throws {
        guard input.count <= limit else { throw CLIError.size(limit: limit, actual: input.count) }
        guard let uuid = UUID(uuidString: id) else {
            throw CLIError(code: "invalid_input", message: "The --id argument must be a UUID; retain it for retries.")
        }
        var bytes = input
        if bytes.last == 10 { bytes.removeLast() }
        if let offset = bytes.firstIndex(where: { $0 == 10 || $0 == 13 }) {
            throw CLIError(code: "invalid_input", message: "Use one physical JSON line; escape newlines inside strings. Only one trailing LF is allowed.", location: .init(source: "input", line: 1, byteOffset: offset))
        }
        _ = try JSONScanner.object(bytes)
        self.bytes = bytes
        self.id = uuid.uuidString.lowercased()
        self.hash = Self.digest(bytes)
    }

    static func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    var line: Data {
        var result = Data("{\"id\":\"\(id)\",\"hash\":\"\(hash)\",\"data\":".utf8)
        result.append(bytes)
        result.append(contentsOf: [125, 10])
        return result
    }

    /// Checks the entire log before treating any matching receipt as committed.
    func isPresent(in log: Data) throws -> Bool {
        if log.isEmpty { return false }
        guard log.last == 10 else { throw CLIError(code: "invalid_log", message: "The existing log ends without LF; its final record may be incomplete.") }
        guard !log.contains(13) else { throw CLIError(code: "invalid_log", message: "The existing log contains a physical carriage return.") }
        var seen = Set<String>()
        var found = false
        var start = log.startIndex
        var lineNumber = 0
        for end in log.indices where log[end] == 10 {
            lineNumber += 1
            let line = log.subdata(in: start..<end)
            start = end + 1
            do {
                let fields = try JSONScanner.object(line, maximumDepth: 65)
                guard Set(fields.keys) == ["id", "hash", "data"],
                      let idRange = fields["id"], let hashRange = fields["hash"], let dataRange = fields["data"]
                else { throw CLIError(code: "invalid_log", message: "Expected an envelope with exactly id, hash and data fields.") }
                let storedID = try JSONDecoder().decode(String.self, from: line.subdata(in: idRange))
                let storedHash = try JSONDecoder().decode(String.self, from: line.subdata(in: hashRange))
                let payload = line.subdata(in: dataRange)
                guard let uuid = UUID(uuidString: storedID), uuid.uuidString.lowercased() == storedID,
                      seen.insert(storedID).inserted, storedHash == Self.digest(payload)
                else { throw CLIError(code: "invalid_log", message: "The record ID is invalid or duplicated, or its payload hash does not match.") }
                do { _ = try JSONScanner.object(payload) }
                catch var failure as CLIError {
                    failure.location = .init(source: "log", line: lineNumber,
                                             byteOffset: dataRange.lowerBound + (failure.location?.byteOffset ?? 0))
                    throw failure
                }
                if storedID == id {
                    guard storedHash == hash else { throw CLIError(code: "id_conflict") }
                    found = true
                }
            } catch let error as CLIError where error.code == "id_conflict" {
                throw error
            } catch {
                let cause = error as? CLIError
                throw CLIError(code: "invalid_log", message: cause?.message ?? "The existing record is invalid.", location: .init(source: "log", line: lineNumber, byteOffset: cause?.location?.byteOffset ?? 0))
            }
        }
        return found
    }
}

private struct JSONScanner {
    let bytes: Data
    let maximumDepth: Int
    var index = 0

    static func object(_ bytes: Data, maximumDepth: Int = 64) throws -> [String: Range<Int>] {
        guard String(data: bytes, encoding: .utf8) != nil else {
            throw CLIError(code: "invalid_input", message: "The JSON input is not valid UTF-8.")
        }
        var parser = JSONScanner(bytes: bytes, maximumDepth: maximumDepth)
        // Leading/trailing whitespace is excluded from the public record contract.
        do {
            guard bytes.first == 123 else {
                throw CLIError(code: "invalid_input", message: "The input must start with a JSON object, without leading whitespace.")
            }
            let fields = try parser.parseObject(depth: 0)
            guard parser.index == bytes.count else {
                throw CLIError(code: "invalid_input", message: "Unexpected bytes after the JSON object; omit trailing whitespace or additional values.")
            }
            return fields
        } catch {
            var failure = (error as? CLIError) ?? CLIError.invalidInput
            if failure.location == nil {
                failure.location = .init(source: "input", line: 1, byteOffset: parser.index)
            }
            throw failure
        }
    }

    mutating func whitespace() {
        while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
    }
    mutating func consume(_ byte: UInt8) throws {
        guard index < bytes.count, bytes[index] == byte else {
            throw CLIError(code: "invalid_input", message: "Expected JSON delimiter \(String(UnicodeScalar(byte))).")
        }
        index += 1
    }
    mutating func string() throws -> String {
        let start = index
        try consume(34)
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == 34 {
                do { return try JSONDecoder().decode(String.self, from: bytes.subdata(in: start..<index)) }
                catch { throw CLIError(code: "invalid_input", message: "Invalid JSON string or escape sequence.", location: .init(source: "input", line: 1, byteOffset: start)) }
            }
            guard byte >= 32 else { throw CLIError(code: "invalid_input", message: "JSON strings must escape control characters.") }
            if byte == 92 {
                guard index < bytes.count else { throw CLIError(code: "invalid_input", message: "Unexpected end of JSON token.") }
                index += 1
            }
        }
        throw CLIError(code: "invalid_input", message: "Unterminated JSON string; a closing quote is required.")
    }
    mutating func parseObject(depth: Int) throws -> [String: Range<Int>] {
        guard depth < maximumDepth else { throw CLIError(code: "invalid_input", message: "JSON nesting exceeds the supported depth of 64 levels.") }
        try consume(123)
        whitespace()
        var fields: [String: Range<Int>] = [:]
        if index < bytes.count && bytes[index] == 125 { index += 1; return fields }
        while true {
            let keyOffset = index
            let key = try string()
            guard fields[key] == nil else { throw CLIError(code: "invalid_input", message: "Duplicate object key; each decoded key must be unique.", location: .init(source: "input", line: 1, byteOffset: keyOffset)) }
            whitespace(); try consume(58); whitespace()
            let start = index
            try value(depth: depth + 1)
            fields[key] = start..<index
            whitespace()
            if index < bytes.count && bytes[index] == 125 { index += 1; return fields }
            try consume(44); whitespace()
        }
    }
    mutating func value(depth: Int) throws {
        guard depth < maximumDepth else { throw CLIError(code: "invalid_input", message: "JSON nesting exceeds the supported depth of 64 levels.") }
        guard index < bytes.count else { throw CLIError(code: "invalid_input", message: "Unexpected end of input; a JSON value is required.") }
        switch bytes[index] {
        case 123: _ = try parseObject(depth: depth)
        case 34: _ = try string()
        case 91:
            index += 1; whitespace()
            if index < bytes.count && bytes[index] == 93 { index += 1; return }
            while true {
                try value(depth: depth + 1); whitespace()
                if index < bytes.count && bytes[index] == 93 { index += 1; break }
                try consume(44); whitespace()
            }
        case 116: try literal("true")
        case 102: try literal("false")
        case 110: try literal("null")
        default: try number()
        }
    }
    mutating func literal(_ value: String) throws {
        for byte in value.utf8 { try consume(byte) }
    }
    mutating func digits() throws {
        let start = index
        while index < bytes.count && (48...57).contains(bytes[index]) { index += 1 }
        guard index > start else { throw CLIError(code: "invalid_input", message: "Invalid JSON number; a decimal digit is required.") }
    }
    mutating func number() throws {
        if index < bytes.count && bytes[index] == 45 { index += 1 }
        guard index < bytes.count else { throw CLIError(code: "invalid_input", message: "Unexpected end of JSON token.") }
        if bytes[index] == 48 { index += 1 }
        else {
            guard (49...57).contains(bytes[index]) else { throw CLIError(code: "invalid_input", message: "Expected a JSON value; non-finite numbers and unquoted text are invalid.") }
            try digits()
        }
        if index < bytes.count && bytes[index] == 46 { index += 1; try digits() }
        if index < bytes.count && [69, 101].contains(bytes[index]) {
            index += 1
            if index < bytes.count && [43, 45].contains(bytes[index]) { index += 1 }
            try digits()
        }
    }
}
