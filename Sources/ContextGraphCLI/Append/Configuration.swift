import Foundation

struct Configuration: Decodable, Sendable {
    let mountRoot: String
    let bucket: String
    let maxRecordBytes: Int
    let maxFileBytes: Int
    let maxAttempts: Int
    let timeoutSeconds: Int
    /// Explicit local verification only. Cloud Run uses its workload metadata identity.
    let accessTokenFile: String?

    func validate() throws {
        guard mountRoot.hasPrefix("/"), mountRoot != "/", !mountRoot.hasSuffix("/"),
              bucket.utf8.count >= 3, bucket.utf8.count <= 222,
              bucket.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || [45, 46, 95].contains($0) }),
              maxRecordBytes > 0, maxFileBytes > maxRecordBytes,
              maxFileBytes < Int.max / 4, maxAttempts > 0, maxAttempts <= 1000,
              timeoutSeconds > 0, timeoutSeconds <= 3600
        else { throw CLIError(code: "invalid_config") }
        let root = URL(fileURLWithPath: mountRoot)
        var isDirectory: ObjCBool = false
        guard root.standardizedFileURL.path == mountRoot,
              root.resolvingSymlinksInPath().path == mountRoot,
              FileManager.default.fileExists(atPath: mountRoot, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { throw CLIError(code: "invalid_config") }
    }

    func objectName(for path: String) throws -> String {
        let url = URL(fileURLWithPath: path)
        guard path.hasPrefix(mountRoot + "/"), path.hasSuffix(".jsonl"),
              !path.contains("\0"), !path.contains("\\"),
              !path.split(separator: "/", omittingEmptySubsequences: false).dropFirst().contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
              url.standardizedFileURL.path == path,
              url.resolvingSymlinksInPath().path == path
        else { throw CLIError(code: "invalid_path") }
        // resolvingSymlinksInPath may leave a missing leaf unresolved. Inspect each
        // existing parent as well; the mount mapping itself remains configuration-owned.
        var componentPath = mountRoot
        for component in path.dropFirst(mountRoot.count + 1).split(separator: "/") {
            componentPath += "/" + component
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: componentPath)
                guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else {
                    throw CLIError(code: "invalid_path")
                }
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                break
            } catch {
                throw CLIError(code: "invalid_path")
            }
        }
        let name = String(path.dropFirst(mountRoot.count + 1))
        guard name.utf8.count <= 1024 else { throw CLIError(code: "invalid_path") }
        return name
    }
}

struct Budget: Sendable {
    let deadline: ContinuousClock.Instant
    init(seconds: Int) { deadline = .now.advanced(by: .seconds(seconds)) }
    var remaining: Double {
        let duration = ContinuousClock.now.duration(to: deadline).components
        return max(0, Double(duration.seconds) + Double(duration.attoseconds) / 1e18)
    }
    func check() throws {
        try Task.checkCancellation()
        guard remaining > 0 else { throw CLIError(code: "io_error") }
    }
}
