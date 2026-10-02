import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct WriteRejected: Error, Sendable {
    let failure: CLIError
}

struct CloudObjectStore: ObjectStore {
    let bucket: String
    let object: String
    let token: String
    let maxFileBytes: Int
    private let send: @Sendable (URLRequest, Int) async throws -> HTTPResponse

    init(bucket: String, object: String, token: String, maxFileBytes: Int,
         send: @escaping @Sendable (URLRequest, Int) async throws -> HTTPResponse = { request, limit in
             try await HTTPTransport.send(request, limit: limit)
         }) {
        self.bucket = bucket; self.object = object; self.token = token
        self.maxFileBytes = maxFileBytes; self.send = send
    }

    static func accessToken(configuration: Configuration, budget: Budget) async throws -> String {
        try budget.check()
        if let path = configuration.accessTokenFile {
            // Local verification uses a caller-created short-lived token file, not a private key.
            let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
            defer { do { try handle.close() } catch { /* Read-only descriptor cleanup. */ } }
            let data = try handle.read(upToCount: 16385) ?? Data()
            try budget.check()
            guard data.count <= 16384, let value = String(data: data, encoding: .utf8) else {
                throw CLIError(code: "invalid_config")
            }
            return try validToken(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        var request = URLRequest(url: URL(string: "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token")!)
        request.setValue("Google", forHTTPHeaderField: "Metadata-Flavor")
        request.timeoutInterval = min(budget.remaining, 10)
        let response = try await HTTPTransport.send(request, limit: 16384)
        try budget.check()
        guard response.status == 200 else { throw CLIError(code: "access_denied") }
        struct Token: Decodable { let access_token: String }
        return try validToken(JSONDecoder().decode(Token.self, from: response.body).access_token)
    }

    private static func validToken(_ token: String) throws -> String {
        guard !token.isEmpty, token.utf8.allSatisfy({ $0 >= 33 && $0 <= 126 }) else {
            throw CLIError(code: "access_denied")
        }
        return token
    }

    private func url(upload: Bool = false, query: [URLQueryItem] = []) -> URL {
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = "storage.googleapis.com"
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let bucket = bucket.addingPercentEncoding(withAllowedCharacters: safe)!
        if upload {
            parts.percentEncodedPath = "/upload/storage/v1/b/\(bucket)/o"
        } else {
            parts.percentEncodedPath = "/storage/v1/b/\(bucket)/o/\(object.addingPercentEncoding(withAllowedCharacters: safe)!)"
        }
        parts.queryItems = query.isEmpty ? nil : query
        return parts.url!
    }

    private func request(_ url: URL, budget: Budget) throws -> URLRequest {
        try budget.check()
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = budget.remaining
        return request
    }

    func read(budget: Budget) async throws -> Snapshot {
        // Metadata and content must refer to one generation, even if a writer replaces it.
        let metadata = try await send(request(url(query: [URLQueryItem(name: "fields", value: "generation,size")]), budget: budget), 16384)
        if metadata.status == 404 { return Snapshot(generation: "0", bytes: Data()) }
        try checkReadStatus(metadata.status)
        struct Metadata: Decodable { let generation: String; let size: String }
        let info = try JSONDecoder().decode(Metadata.self, from: metadata.body)
        guard let size = UInt64(info.size),
              !info.generation.isEmpty, info.generation.utf8.allSatisfy({ (48...57).contains($0) })
        else { throw CLIError(code: "io_error") }
        guard size <= UInt64(maxFileBytes) else {
            throw CLIError(code: "limit_exceeded", message: "The existing object exceeds maxFileBytes; ask its owner to manage the log size.", limit: UInt64(maxFileBytes), actual: size)
        }
        let content = try await send(request(url(query: [
            URLQueryItem(name: "alt", value: "media"),
            URLQueryItem(name: "generation", value: info.generation),
        ]), budget: budget), maxFileBytes)
        // Appender owns the shared attempt budget and backoff for a lost generation.
        if content.status == 404 { throw CLIError(code: "contention") }
        try checkReadStatus(content.status)
        guard content.body.count == size else { throw CLIError(code: "io_error") }
        return Snapshot(generation: info.generation, bytes: content.body)
    }

    func put(_ bytes: Data, generation: String, budget: Budget) async throws -> PutResult {
        var request = try request(url(upload: true, query: [
            URLQueryItem(name: "uploadType", value: "media"),
            URLQueryItem(name: "name", value: object),
            URLQueryItem(name: "ifGenerationMatch", value: generation),
            URLQueryItem(name: "fields", value: "generation"),
        ]), budget: budget)
        request.httpMethod = "POST"
        request.httpBody = bytes
        request.setValue("application/x-ndjson", forHTTPHeaderField: "Content-Type")
        let response = try await send(request, 16384)
        if response.status == 412 { return .conflict }
        if response.status == 401 || response.status == 403 {
            throw WriteRejected(failure: CLIError(code: "access_denied"))
        }
        // Other responses are reconciled conservatively; never expose a provider error body.
        guard response.status == 200 else { throw CLIError(code: "io_error") }
        struct Result: Decodable { let generation: String }
        let result = try JSONDecoder().decode(Result.self, from: response.body)
        guard !result.generation.isEmpty, result.generation.utf8.allSatisfy({ (48...57).contains($0) }) else {
            throw CLIError(code: "io_error")
        }
        return .committed(result.generation)
    }

    private func checkReadStatus(_ status: Int) throws {
        if status == 401 || status == 403 { throw CLIError(code: "access_denied") }
        guard status == 200 else { throw CLIError(code: "io_error") }
    }
}
