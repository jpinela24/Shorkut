import Foundation

/// Guards deletion of shortcut script files so a shortcut record can never be
/// used to delete a file outside Shorkut's own managed scripts directory —
/// whether via `..` traversal, a prefix-collision sibling directory, an
/// absolute external path, or a symlink pointing out of the sandbox.
public enum ManagedScripts {

    public enum Deletion: Equatable {
        /// The target was a regular file inside the managed directory and was removed.
        case deleted
        /// The target is outside the managed directory (or reached via a symlinked
        /// parent) — the caller should drop the record but must NOT delete anything.
        case skippedOutsideManagedDirectory
        /// The target isn't a regular file (missing, a symlink, a directory, a
        /// device) — nothing safe to delete.
        case skippedNotRegularFile
        /// The file was managed and eligible, but removal failed — surfaced to the user.
        case failed(String)
    }

    /// Pure lexical containment check on already-absolute paths. A path is
    /// contained iff it sits strictly beneath `directory`. The trailing
    /// separator is essential: without it `/x/Scripts-evil/f` would falsely
    /// match managed dir `/x/Scripts` (prefix collision).
    public static func isContained(_ path: String, in directory: String) -> Bool {
        let dir = directory.hasSuffix("/") ? directory : directory + "/"
        return path.hasPrefix(dir)
    }

    /// Resolves `path` and its containing directory (following symlinks in the
    /// *parent* chain but NOT the final component), verifies the result is a
    /// regular file strictly inside `directory`, and removes it. Symlinks are
    /// never followed for the final component, so a managed-dir symlink that
    /// points outside is rejected rather than dereferenced.
    public static func deleteIfManaged(
        path: String,
        directory: URL,
        fileManager: FileManager = .default
    ) -> Deletion {
        guard !path.isEmpty else { return .skippedOutsideManagedDirectory }

        // Real path of the managed directory (resolves any symlinks in its own chain).
        let managedReal = directory.resolvingSymlinksInPath().standardizedFileURL.path

        // Lexically normalize the target (collapses `..`, `.`), then resolve
        // symlinks in the PARENT chain only, re-appending the original last
        // component so we don't dereference a final-component symlink.
        let target = URL(fileURLWithPath: path).standardizedFileURL
        let parentReal = target.deletingLastPathComponent().resolvingSymlinksInPath()
        let effective = parentReal.appendingPathComponent(target.lastPathComponent).standardizedFileURL.path

        guard isContained(effective, in: managedReal) else {
            return .skippedOutsideManagedDirectory
        }

        // lstat semantics: attributesOfItem does NOT follow a final symlink, so
        // the type reflects the link itself. Only a genuine regular file qualifies.
        guard let attrs = try? fileManager.attributesOfItem(atPath: target.path),
              (attrs[.type] as? FileAttributeType) == .typeRegular else {
            return .skippedNotRegularFile
        }

        do {
            try fileManager.removeItem(atPath: target.path)
            return .deleted
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
