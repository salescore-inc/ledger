import Foundation

struct Snapshot: Sendable {
    let generation: String
    let bytes: Data
}

enum PutResult: Sendable {
    case committed(String)
    case conflict
}

protocol ObjectStore: Sendable {
    func read(budget: Budget) async throws -> Snapshot
    /// Throws conservatively mean the commit might have occurred.
    func put(_ bytes: Data, generation: String, budget: Budget) async throws -> PutResult
}

struct Receipt: Encodable, Sendable {
    let status: String
    let id: String
    let generation: String
}

struct Appender {
    let store: any ObjectStore
    let maxFileBytes: Int
    let maxAttempts: Int

    func append(_ record: JSONRecord, budget: Budget) async throws -> Receipt {
        var uncertain = false
        var stage = "read"
        for attempt in 0..<maxAttempts {
            do {
                try budget.check()
                stage = "read"
                let snapshot = try await store.read(budget: budget)
                guard snapshot.bytes.count <= maxFileBytes else { throw CLIError.size(limit: maxFileBytes, actual: snapshot.bytes.count) }
                stage = "validate_log"
                if try record.isPresent(in: snapshot.bytes) {
                    return Receipt(status: "already_present", id: record.id, generation: snapshot.generation)
                }
                // An uncertain request can still finish later, so keep its sticky state.
                stage = "prepare_append"
                let line = record.line
                guard line.count <= maxFileBytes - snapshot.bytes.count else { throw CLIError.size(limit: maxFileBytes, actual: snapshot.bytes.count + line.count) }
                var next = snapshot.bytes
                next.append(line)
                try budget.check()
                do {
                    stage = "upload"
                    switch try await store.put(next, generation: snapshot.generation, budget: budget) {
                    case .committed(let generation):
                        return Receipt(status: "appended", id: record.id, generation: generation)
                    case .conflict: break
                    }
                } catch let rejected as WriteRejected {
                    throw rejected.failure
                } catch {
                    uncertain = true
                }
                if attempt + 1 < maxAttempts {
                    let delay = min(Double.random(in: 0.01...0.1) * Double(attempt + 1), 1, budget.remaining)
                    if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
                }
            } catch {
                var failure = uncertain ? CLIError(code: "outcome_unknown") : ((error as? CLIError) ?? CLIError(code: "io_error"))
                failure.stage = stage
                throw failure
            }
        }
        // Final reconciliation also handles a commit on the last allowed request.
        if uncertain {
            do {
                try budget.check()
                stage = "read"
                let snapshot = try await store.read(budget: budget)
                guard snapshot.bytes.count <= maxFileBytes else { throw CLIError.size(limit: maxFileBytes, actual: snapshot.bytes.count) }
                stage = "validate_log"
                if try record.isPresent(in: snapshot.bytes) {
                    return Receipt(status: "already_present", id: record.id, generation: snapshot.generation)
                }
            } catch { throw CLIError(code: "outcome_unknown") }
            throw CLIError(code: "outcome_unknown")
        }
        throw CLIError(code: "contention")
    }
}
