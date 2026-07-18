import Foundation

/// File-import primitives that fail *closed*: if size/type metadata can't be
/// read, or the source isn't a plain regular file, the operation is rejected
/// rather than proceeding. Byte limits are enforced while reading/copying (not
/// just via a pre-check that can be skipped when metadata is unavailable), and
/// I/O is streamed in bounded chunks so a huge file never lands wholesale in memory.
public enum SafeFileImport {

    public enum ImportError: Error, Equatable {
        case metadataUnreadable
        case notRegularFile
        case tooLarge(limit: Int)
        case readFailed(String)
        case writeFailed(String)

        /// User-facing sentence for an alert.
        public func message(filename: String) -> String {
            switch self {
            case .metadataUnreadable:
                return "Couldn't read “\(filename)”. Shorkut only imports files it can inspect."
            case .notRegularFile:
                return "“\(filename)” isn't a regular file. Folders, symlinks, and devices can't be imported."
            case .tooLarge(let limit):
                return "“\(filename)” is larger than \(limit / 1024 / 1024) MB, which is larger than a real shortcut file should be."
            case .readFailed(let detail):
                return "Couldn't read “\(filename)”: \(detail)"
            case .writeFailed(let detail):
                return "Couldn't save “\(filename)”: \(detail)"
            }
        }
    }

    private static let chunkSize = 64 * 1024

    /// lstat-style validation (does NOT follow a final symlink): requires a
    /// genuine regular file whose reported size is within `maxBytes`. Returns the
    /// size on success. Missing/unreadable metadata → `.metadataUnreadable`.
    public static func validateRegularFile(
        at path: String,
        maxBytes: Int,
        fileManager: FileManager = .default
    ) -> Result<Int, ImportError> {
        guard let attrs = try? fileManager.attributesOfItem(atPath: path) else {
            return .failure(.metadataUnreadable)
        }
        guard (attrs[.type] as? FileAttributeType) == .typeRegular else {
            return .failure(.notRegularFile)
        }
        guard let size = (attrs[.size] as? NSNumber)?.intValue else {
            return .failure(.metadataUnreadable)
        }
        if size > maxBytes { return .failure(.tooLarge(limit: maxBytes)) }
        return .success(size)
    }

    /// Reads at most `maxBytes` from `url` after validating it's a regular file,
    /// streaming in chunks and bailing out the instant the limit is exceeded — so
    /// a file that grows between stat and read (TOCTOU) still can't blow the cap
    /// or exhaust memory.
    public static func boundedRead(
        at url: URL,
        maxBytes: Int,
        fileManager: FileManager = .default
    ) -> Result<Data, ImportError> {
        if case let .failure(error) = validateRegularFile(at: url.path, maxBytes: maxBytes, fileManager: fileManager) {
            return .failure(error)
        }
        guard let input = try? FileHandle(forReadingFrom: url) else {
            return .failure(.readFailed("couldn't open the file"))
        }
        defer { try? input.close() }

        var data = Data()
        while true {
            let chunk: Data?
            do { chunk = try input.read(upToCount: chunkSize) }
            catch { return .failure(.readFailed(error.localizedDescription)) }
            guard let piece = chunk, !piece.isEmpty else { break }
            if data.count + piece.count > maxBytes { return .failure(.tooLarge(limit: maxBytes)) }
            data.append(piece)
        }
        return .success(data)
    }

    /// Streams `source` → `destination` in bounded chunks, enforcing `maxBytes`
    /// during the copy and deleting a partial destination on any failure.
    /// Returns the number of bytes written on success.
    @discardableResult
    public static func streamCopy(
        from source: URL,
        to destination: URL,
        maxBytes: Int,
        fileManager: FileManager = .default
    ) -> Result<Int, ImportError> {
        if case let .failure(error) = validateRegularFile(at: source.path, maxBytes: maxBytes, fileManager: fileManager) {
            return .failure(error)
        }
        guard let input = try? FileHandle(forReadingFrom: source) else {
            return .failure(.readFailed("couldn't open the source file"))
        }
        defer { try? input.close() }

        // Fresh, empty destination.
        try? fileManager.removeItem(at: destination)
        guard fileManager.createFile(atPath: destination.path, contents: nil),
              let output = try? FileHandle(forWritingTo: destination) else {
            return .failure(.writeFailed("couldn't create the destination file"))
        }

        func abort(_ error: ImportError) -> Result<Int, ImportError> {
            try? output.close()
            try? fileManager.removeItem(at: destination)
            return .failure(error)
        }

        var total = 0
        while true {
            let chunk: Data?
            do { chunk = try input.read(upToCount: chunkSize) }
            catch { return abort(.readFailed(error.localizedDescription)) }
            guard let piece = chunk, !piece.isEmpty else { break }
            total += piece.count
            if total > maxBytes { return abort(.tooLarge(limit: maxBytes)) }
            do { try output.write(contentsOf: piece) }
            catch { return abort(.writeFailed(error.localizedDescription)) }
        }
        try? output.close()
        return .success(total)
    }
}
