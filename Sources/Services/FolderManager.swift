import Foundation
import SwiftData
import AppKit

@Observable
final class FolderManager {
    /// Folders selected for the current session.
    var selectedFolders: [URL] = []

    /// Previously sliced folders, most-recent-first. Persisted as
    /// security-scoped bookmarks so they can be reopened across launches.
    private(set) var recentFolders: [URL] = []

    /// How many recents the folder-selection screen surfaces.
    static let displayRecentCount = 3

    private let recentsKey = "MandolineRecentFolders"
    private let maxRecents = 10

    /// Recent bookmarks kept alongside their resolved URLs so we only mint a
    /// fresh bookmark for a folder we currently have access to.
    private var recentBookmarks: [String: Data] = [:]

    init() {
        loadRecents()
    }

    /// The recents shown as quick-access rows on the selection screen.
    var displayRecents: [URL] {
        Array(recentFolders.prefix(Self.displayRecentCount))
    }

    @MainActor
    func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Allow Access"
        panel.message = "Mandoline needs access to the folders you want to review and clean up."

        if panel.runModal() == .OK {
            for url in panel.urls {
                guard !selectedFolders.contains(url) else { continue }

                // For sandboxed apps, the URL returned by NSOpenPanel is security-scoped.
                // We must start accessing it for the duration of our usage.
                if url.startAccessingSecurityScopedResource() {
                    selectedFolders.append(url)
                    addRecent(url)
                } else {
                    print("Failed to start accessing security-scoped resource for \(url.path)")
                }
            }
        }
    }

    /// Reopen a previously sliced folder from the recents list.
    @MainActor
    func openRecent(_ url: URL) {
        if url.startAccessingSecurityScopedResource() {
            if !selectedFolders.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) {
                selectedFolders.append(url)
            }
            addRecent(url)
        } else {
            print("[Mandoline] Failed to access recent folder: \(url.path)")
        }
    }

    /// Adopt folder roots whose security-scoped bookmarks were resolved by a saved index.
    @MainActor
    func openSavedIndex(folderRoots: [URL]) {
        clearFolders()
        for url in folderRoots {
            let standardized = url.standardizedFileURL
            guard !selectedFolders.contains(where: { $0.standardizedFileURL == standardized }) else { continue }
            selectedFolders.append(standardized)
            addRecent(standardized)
        }
    }

    func clearFolders() {
        stopAccessing()
        selectedFolders.removeAll()
        // Recents are intentionally preserved across folder switches.
    }

    /// Remove a folder from the recents list.
    func removeRecent(_ url: URL) {
        let path = url.standardizedFileURL.path
        recentFolders.removeAll { $0.standardizedFileURL.path == path }
        recentBookmarks.removeValue(forKey: path)
        saveRecents()
    }

    func stopAccessing() {
        for url in selectedFolders {
            url.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: - Recents

    private func addRecent(_ url: URL) {
        let path = url.standardizedFileURL.path

        // Reuse an existing bookmark, or mint one while we currently have access.
        let bookmark = recentBookmarks[path]
            ?? (try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil))
        guard let bookmark else { return }

        recentFolders.removeAll { $0.standardizedFileURL.path == path }
        recentFolders.insert(url, at: 0)
        recentBookmarks[path] = bookmark

        if recentFolders.count > maxRecents {
            let dropped = recentFolders[maxRecents...]
            for url in dropped { recentBookmarks.removeValue(forKey: url.standardizedFileURL.path) }
            recentFolders = Array(recentFolders.prefix(maxRecents))
        }

        saveRecents()
    }

    private func saveRecents() {
        let datas = recentFolders.compactMap { recentBookmarks[$0.standardizedFileURL.path] }
        UserDefaults.standard.set(datas, forKey: recentsKey)
    }

    private func loadRecents() {
        guard let datas = UserDefaults.standard.array(forKey: recentsKey) as? [Data] else { return }

        var urls: [URL] = []
        for data in datas {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { continue }

            urls.append(url)
            recentBookmarks[url.standardizedFileURL.path] = data
        }
        recentFolders = urls
    }
}
