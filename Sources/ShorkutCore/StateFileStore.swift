import Foundation

/// Outcome of loading persisted state, so the caller can react deliberately
/// instead of silently falling back to empty defaults on corruption.
public enum StateLoad<Payload> {
    /// The main file decoded cleanly.
    case loaded(Payload)
    /// The main file was unreadable/corrupt but the last-known-good backup decoded.
    case recoveredFromBackup(Payload)
    /// No state exists yet (fresh install) — migration/defaults are appropriate.
    case empty
    /// Neither the main file nor any backup could be decoded. The caller MUST
    /// NOT overwrite the file blindly; the underlying error is provided.
    case corrupt(Error)
}

public enum StateStoreError: Error {
    case noReadableState
}

/// Atomically-written, backup-protected JSON store for a Codable payload.
/// Injecting `fileURL`/`fileManager` keeps it fully unit-testable.
public final class StateFileStore<Payload: Codable> {
    public let fileURL: URL
    public let backupURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.backupURL = fileURL.appendingPathExtension("bak")
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    private func decode(_ url: URL) throws -> Payload {
        let data = try Data(contentsOf: url)
        return try decoder.decode(Payload.self, from: data)
    }

    /// Loads state, preferring the main file, then the backup. Reports the real
    /// decode error rather than swallowing it.
    public func load() -> StateLoad<Payload> {
        let mainExists = fileManager.fileExists(atPath: fileURL.path)
        let backupExists = fileManager.fileExists(atPath: backupURL.path)
        if !mainExists && !backupExists { return .empty }

        var lastError: Error = StateStoreError.noReadableState
        if mainExists {
            do { return .loaded(try decode(fileURL)) }
            catch { lastError = error }
        }
        if backupExists {
            do { return .recoveredFromBackup(try decode(backupURL)) }
            catch { lastError = error }
        }
        return .corrupt(lastError)
    }

    /// Writes `payload` atomically. Before overwriting an existing good file it
    /// is copied to the backup, so a crash mid-write can't lose the prior state.
    @discardableResult
    public func save(_ payload: Payload) -> Result<Void, Error> {
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try encoder.encode(payload)

            if fileManager.fileExists(atPath: fileURL.path) {
                try? fileManager.removeItem(at: backupURL)
                try fileManager.copyItem(at: fileURL, to: backupURL)
            }

            let tmpURL = fileURL.appendingPathExtension("tmp-\(UUID().uuidString)")
            try data.write(to: tmpURL, options: .atomic)
            if fileManager.fileExists(atPath: fileURL.path) {
                _ = try fileManager.replaceItemAt(fileURL, withItemAt: tmpURL)
            } else {
                try fileManager.moveItem(at: tmpURL, to: fileURL)
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    /// Moves a corrupt main file aside (never deletes it) so the user's data is
    /// preserved for manual recovery while the app starts fresh. Returns the URL
    /// it was moved to.
    @discardableResult
    public func quarantineCorruptFile() -> URL? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let dest = fileURL.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))")
        do {
            try fileManager.moveItem(at: fileURL, to: dest)
            return dest
        } catch {
            return nil
        }
    }
}

/// One-time migration from the pre-state-file layout, where sections/shortcuts/
/// tiles lived as separate JSON blobs in UserDefaults. Pure: the app reads the
/// blobs and passes them here. Idempotency is the caller's job — migration only
/// runs when no state file exists yet.
public enum StateMigration {
    public static func migrate(
        sectionsJSON: Data?,
        shortcutsJSON: Data?,
        tilesJSON: Data?,
        legacyTileIDs: [String]?
    ) -> PersistentState {
        let decoder = JSONDecoder()

        var sections: [ShortcutSection] = []
        if let data = sectionsJSON, let decoded = try? decoder.decode([ShortcutSection].self, from: data), !decoded.isEmpty {
            sections = decoded
        }
        if sections.isEmpty {
            sections = [ShortcutSection(name: "General")]
        }

        var shortcuts: [ScriptShortcut] = []
        if let data = shortcutsJSON, let decoded = try? decoder.decode([ScriptShortcut].self, from: data) {
            shortcuts = decoded
        }

        var tiles: [TileConfig] = []
        if let data = tilesJSON, let decoded = try? decoder.decode([TileConfig].self, from: data), !decoded.isEmpty {
            tiles = decoded
        } else if let legacyTileIDs, !legacyTileIDs.isEmpty {
            tiles = legacyTileIDs.enumerated().map { index, id in
                TileConfig(id: id, name: "Tile \(index + 1)", sectionIds: nil)
            }
        }
        if tiles.isEmpty {
            tiles = [TileConfig(id: primaryTileID, name: "Tile 1", sectionIds: nil)]
        }

        return PersistentState(sections: sections, shortcuts: shortcuts, tiles: tiles)
    }
}
