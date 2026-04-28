import Foundation
import SwiftData

struct ActionRecord {
    /// Original location in the user-selected folder.
    let url: URL
    let type: ProcessedFile.ActionType

    /// For "trash", this is the staged location inside the selected root folder.
    /// Undo moves from `stagedURL` back to `url`.
    let stagedURL: URL?
}

@Observable
final class ActionService {
    var history: [ActionRecord] = []
    let maxUndo = 3

    // MARK: - Public API

    /// Marks a file as kept. This only affects SwiftData; the file is not moved.
    @discardableResult
    func keep(url: URL, context: ModelContext) -> Bool {
        upsertProcessedFile(path: url.path, action: .kept, context: context)
        do {
            try context.save()
        } catch {
            print("SwiftData save failed after keep for \(url.path): \(error)")
            return false
        }

        history.append(ActionRecord(url: url, type: .kept, stagedURL: nil))
        trimHistory()
        return true
    }

    /// Stages a file for deletion by moving it into a hidden staging folder inside the
    /// *selected root folder* that contains the file.
    ///
    /// This makes undo reliable under App Sandbox because the file never leaves the
    /// security-scoped directory tree.
    ///
    /// - Parameter roots: The set of user-selected root folders (security-scoped).
    @discardableResult
    func trash(url: URL, roots: [URL], context: ModelContext) -> Bool {
        let fm = FileManager.default

        guard let root = resolveRoot(for: url, roots: roots) else {
            print("[Mandoline] Refusing to stage-delete because file is not inside any selected root: \(url.path)")
            return false
        }

        // Mirror the original relative path under the staging directory to avoid name collisions.
        let relativePath = relativePath(from: root, to: url)
        let stagingRoot = root.appendingPathComponent(".mandoline-staging", isDirectory: true)
        let deletedRoot = stagingRoot.appendingPathComponent("Deleted", isDirectory: true)

        let destinationURL = deletedRoot.appendingPathComponent(relativePath)
        let destinationDir = destinationURL.deletingLastPathComponent()


        do {
            try fm.createDirectory(at: destinationDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("[Mandoline] Failed to create staging directory at \(destinationDir.path): \(error)")
            return false
        }

        // If something is already staged at that exact path (rare), pick a unique filename in that folder.
        let finalDestinationURL: URL
        if fm.fileExists(atPath: destinationURL.path) {
            finalDestinationURL = uniqueDestination(in: destinationDir, originalName: destinationURL.lastPathComponent)
        } else {
            finalDestinationURL = destinationURL
        }

        do {
            try fm.moveItem(at: url, to: finalDestinationURL)
        } catch {
            print("[Mandoline] Failed to move item to staging (\(url.path) -> \(finalDestinationURL.path)): \(error)")
            return false
        }

        // Sanity check
        if !fm.fileExists(atPath: finalDestinationURL.path) {
            print("[Mandoline] Sanity check failed: file does not exist at staging destination \(finalDestinationURL.path)")
            return false
        }

        // Record action in SwiftData (best-effort)
        upsertProcessedFile(path: url.path, action: .trashed, context: context)
        do {
            try context.save()
        } catch {
            print("[Mandoline] SwiftData save failed after staging delete for \(url.path): \(error)")
        }

        history.append(ActionRecord(url: url, type: .trashed, stagedURL: finalDestinationURL))
        trimHistory()
        return true
    }

    /// Undo the last keep/trash action (up to `maxUndo`).
    @discardableResult
    func undo(context: ModelContext) -> (url: URL, type: ProcessedFile.ActionType)? {
        guard let last = history.popLast() else { return nil }

        var restoredURL = last.url

        switch last.type {
        case .kept:
            deleteProcessedFile(path: last.url.path, context: context)
            do {
                try context.save()
            } catch {
                print("SwiftData save failed after undo keep for \(last.url.path): \(error)")
            }

        case .trashed:
            guard let trashedURL = resolveStagedURL(for: last) else {
                print("[Mandoline] Cannot resolve staged URL for undo: \(last.url.path)")
                // Put it back so the user can try again.
                history.append(last)
                trimHistory()
                return nil
            }

            do {
                if !FileManager.default.fileExists(atPath: trashedURL.path) {
                    print("[Mandoline] Undo failed: staged file missing at \(trashedURL.path)")
                    // Put it back so the user can retry (in case of transient filesystem state).
                    history.append(last)
                    trimHistory()
                    return nil
                }

                let destinationURL = uniqueRestoreDestination(originalURL: last.url)

                // Ensure destination directory exists (in case the user moved/renamed folders during triage).
                let destinationDir = destinationURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true, attributes: nil)

                try FileManager.default.moveItem(at: trashedURL, to: destinationURL)

                restoredURL = destinationURL

                // Undo means: this file should no longer be considered "processed".
                // Even if we had to restore under a different name due to a collision,
                // the user intent is still to undo the trash decision.
                deleteProcessedFile(path: last.url.path, context: context)
                do {
                    try context.save()
                } catch {
                    print("SwiftData save failed after undo trash for \(last.url.path): \(error)")
                }
            } catch {
                print("Failed to restore from staging (\(trashedURL.path) -> \(last.url.path)): \(error)")

                // If the item was restored/moved outside Mandoline, it may no longer exist at trashedURL.
                // In that case, treat this as a no-op undo and clear the processed marker so it can be rescanned.
                if !FileManager.default.fileExists(atPath: trashedURL.path) {
                    deleteProcessedFile(path: last.url.path, context: context)
                    try? context.save()
                    return (last.url, last.type)
                }

                // Otherwise, put it back so the user can retry.
                history.append(last)
                trimHistory()
                return nil
            }
        }

        return (restoredURL, last.type)
    }

    // MARK: - SwiftData helpers

    private func upsertProcessedFile(path: String, action: ProcessedFile.ActionType, context: ModelContext) {
        let descriptor = FetchDescriptor<ProcessedFile>(predicate: #Predicate { $0.filePath == path })

        do {
            if let existing = try context.fetch(descriptor).first {
                existing.action = action
                existing.processedAt = Date()
            } else {
                context.insert(ProcessedFile(filePath: path, action: action))
            }
        } catch {
            // If fetch fails, fall back to insert; worst case we'll get a unique constraint error during save.
            context.insert(ProcessedFile(filePath: path, action: action))
        }
    }

    private func deleteProcessedFile(path: String, context: ModelContext) {
        let descriptor = FetchDescriptor<ProcessedFile>(predicate: #Predicate { $0.filePath == path })
        if let items = try? context.fetch(descriptor) {
            for item in items {
                context.delete(item)
            }
        }
    }

    // MARK: - Trash resolution

    private func resolveStagedURL(for record: ActionRecord) -> URL? {
        // With the Mandoline-managed staging, we always know the location.
        if let stagedURL = record.stagedURL, FileManager.default.fileExists(atPath: stagedURL.path) {
            return stagedURL
        }
        return nil
    }

    private func resolveRoot(for fileURL: URL, roots: [URL]) -> URL? {
        // Pick the deepest matching root (longest path prefix).
        let filePath = fileURL.standardizedFileURL.path

        let matches = roots
            .map { $0.standardizedFileURL }
            .filter { root in
                let rootPath = root.path
                return filePath == rootPath || filePath.hasPrefix(rootPath + "/")
            }
            .sorted { $0.path.count > $1.path.count }

        return matches.first
    }

    private func relativePath(from root: URL, to file: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path

        if filePath == rootPath {
            return file.lastPathComponent
        }

        if filePath.hasPrefix(rootPath + "/") {
            let start = filePath.index(filePath.startIndex, offsetBy: rootPath.count + 1)
            return String(filePath[start...])
        }

        // Shouldn't happen if resolveRoot succeeded; fallback to filename.
        return file.lastPathComponent
    }

    private func uniqueDestination(in directory: URL, originalName: String) -> URL {
        let fm = FileManager.default

        let originalURL = directory.appendingPathComponent(originalName)
        guard fm.fileExists(atPath: originalURL.path) else { return originalURL }

        let ext = (originalName as NSString).pathExtension
        let base = (originalName as NSString).deletingPathExtension

        for i in 2...500 {
            let candidateName = ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)"
            let candidateURL = directory.appendingPathComponent(candidateName)
            if !fm.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        let uuidName = ext.isEmpty ? "\(base) \(UUID().uuidString)" : "\(base) \(UUID().uuidString).\(ext)"
        return directory.appendingPathComponent(uuidName)
    }

    private func uniqueRestoreDestination(originalURL: URL) -> URL {
        // Most of the time the original location is free.
        guard FileManager.default.fileExists(atPath: originalURL.path) else {
            return originalURL
        }

        let directory = originalURL.deletingLastPathComponent()
        let ext = originalURL.pathExtension
        let baseName = originalURL.deletingPathExtension().lastPathComponent

        // Try "<name> (Restored).ext", then "<name> (Restored 2).ext", etc.
        for i in 1...50 {
            let suffix = (i == 1) ? " (Restored)" : " (Restored \(i))"
            let candidateName = baseName + suffix

            let candidate: URL
            if ext.isEmpty {
                candidate = directory.appendingPathComponent(candidateName)
            } else {
                candidate = directory.appendingPathComponent(candidateName).appendingPathExtension(ext)
            }

            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        // Fall back to a UUID.
        let uuidName = baseName + " (Restored " + UUID().uuidString + ")"
        if ext.isEmpty {
            return directory.appendingPathComponent(uuidName)
        } else {
            return directory.appendingPathComponent(uuidName).appendingPathExtension(ext)
        }
    }

    private func trimHistory() {
        if history.count > maxUndo {
            history.removeFirst()
        }
    }
}
