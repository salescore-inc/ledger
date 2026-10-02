import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization

struct HTTPResponse: Sendable {
    let status: Int
    let body: Data
}

/// Foundation invokes callbacks and cancellation concurrently. State has one mutex
/// owner; all completion callbacks resume outside that mutex. No shared raw state.
final class HTTPTransport: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct State {
        var task: URLSessionDataTask?
        var continuation: CheckedContinuation<HTTPResponse, any Error>?
        var response: HTTPURLResponse?
        var body = Data()
        var failure: CLIError?
        var cancelled = false
    }
    private let state = Mutex(State())
    private let limit: Int

    private init(limit: Int) { self.limit = limit }

    // ponytail: bounded one-shot CLI retains sessions until exit to avoid the
    // Static Linux SDK libcurl teardown abort. Revisit for a long-lived process.
    private static let sessions = Mutex<[URLSession]>([])

    static func send(_ request: URLRequest, limit: Int) async throws -> HTTPResponse {
        let delegate = HTTPTransport(limit: limit)
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        sessions.withLock { $0.append(session) }
        let task = session.dataTask(with: request)
        // A request timeout alone can reset as data arrives. Bound the entire task.
        let deadline = Task {
            do { try await Task.sleep(for: .seconds(request.timeoutInterval)) }
            catch { return }
            task.cancel()
        }
        defer { deadline.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let cancelled = delegate.state.withLock { state in
                    state.task = task
                    state.continuation = continuation
                    return state.cancelled
                }
                // Resume even an already-cancelled task so completion owns the continuation.
                if cancelled { task.cancel() }
                task.resume()
            }
        } onCancel: {
            let task = delegate.state.withLock { state in
                state.cancelled = true
                return state.task
            }
            task?.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        let allowed = state.withLock { state in
            guard let response = response as? HTTPURLResponse else {
                state.failure = CLIError(code: "io_error"); return false
            }
            state.response = response
            guard response.expectedContentLength <= Int64(limit) else {
                state.failure = CLIError.size(limit: limit, actual: Int(response.expectedContentLength)); return false
            }
            return true
        }
        completionHandler(allowed ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let cancel = state.withLock { state in
            guard state.body.count <= limit - data.count else {
                state.failure = CLIError.size(limit: limit, actual: state.body.count + data.count); return true
            }
            state.body.append(data)
            return false
        }
        if cancel { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let result = state.withLock { state -> (CheckedContinuation<HTTPResponse, any Error>?, Result<HTTPResponse, any Error>) in
            defer { state.body = Data(); state.response = nil }
            let continuation = state.continuation
            state.continuation = nil
            state.task = nil
            if let failure = state.failure { return (continuation, .failure(failure)) }
            if let error { return (continuation, .failure(error)) }
            guard let response = state.response else { return (continuation, .failure(CLIError(code: "io_error"))) }
            return (continuation, .success(HTTPResponse(status: response.statusCode, body: state.body)))
        }
        result.0?.resume(with: result.1)
    }
}
