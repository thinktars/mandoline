import Foundation
import SwiftData
import AppKit

@Observable
final class FolderManager {
    var selectedFolders: [URL] = []
    
    // Security-Scoped Bookmark handling
    private let bookmarksKey = "MandolineBookmarks"
    
    init() {
        loadBookmarks()
    }
    
    @MainActor
    func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Allow Access"
        panel.message = "Select folders to monitor and manage. Mandoline needs read/write access to delete files you choose to trash."
        
        if panel.runModal() == .OK {
            for url in panel.urls {
                guard !selectedFolders.contains(url) else { continue }

                // For sandboxed apps, the URL returned by NSOpenPanel is security-scoped.
                // We must start accessing it for the duration of our usage.
                if url.startAccessingSecurityScopedResource() {
                    selectedFolders.append(url)
                    saveBookmark(for: url)
                } else {
                    print("Failed to start accessing security-scoped resource for \(url.path)")
                }
            }
        }
    }
    
    private func saveBookmark(for url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            var bookmarks = UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] ?? [:]
            bookmarks[url.path] = bookmarkData
            UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
        } catch {
            print("Failed to save bookmark for \(url): \(error)")
        }
    }
    
    private func loadBookmarks() {
        guard let bookmarks = UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] else { return }
        
        for (_, data) in bookmarks {
            var isStale = false
            do {
                let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                if isStale {
                    saveBookmark(for: url)
                }
                if url.startAccessingSecurityScopedResource() {
                    selectedFolders.append(url)
                }
            } catch {
                print("Failed to resolve bookmark: \(error)")
            }
        }
    }
    
    func stopAccessing() {
        for url in selectedFolders {
            url.stopAccessingSecurityScopedResource()
        }
    }
    
    func clearFolders() {
        stopAccessing()
        selectedFolders.removeAll()
        UserDefaults.standard.removeObject(forKey: bookmarksKey)
    }
}
