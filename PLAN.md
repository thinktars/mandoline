# Mandoline - Engineering Plan

## 📌 Overview
Mandoline is a macOS application designed to help users quickly sort through massive folders of unorganized media (photos, videos). It uses a "Tinder-like" interaction model (Left to trash, Right to keep) with a highly polished, retro-inspired aesthetic similar to [retro.app](https://retro.app/).

## 🏗 Architecture & Tech Stack
* **Target:** macOS Sequoia (15.0+)
* **UI Framework:** SwiftUI with `@Observable` for state management.
* **Database / Persistence:** SwiftData to store the file paths/hashes of "Kept" media, ensuring they are skipped in future sessions.
* **File Access:** Security-Scoped Bookmarks (App Sandbox) so Mandoline can retain read/write access to the selected folders across app launches.
* **Media Handling:** `AVKit` (for native video playback/scrubbing), `Image` (for photos), and `QuickLook` framework for fallback formats.
* **Project Generation:** `XcodeGen` (using a `project.yml`) to make agent collaboration seamless and avoid `.pbxproj` merge conflicts.

---

## 📋 Execution Plan

### Phase 1: Project Setup & Foundation
* Generate the Xcode project `Mandoline` at `~/Programming/tars/mandoline` using `XcodeGen`.
* Set up App Sandbox entitlements with user-selected file read/write permissions.
* Initialize the SwiftData model (`ProcessedFile`) to track what the user has kept.

### Phase 2: Core Services (The "Engine")
* **`FolderManager`**: Handles `NSOpenPanel` to select folders and saves Security-Scoped Bookmarks to `UserDefaults` so the app remembers access permissions on next launch.
* **`ScannerService`**: Recursively crawls selected folders, filters for media types, checks against SwiftData to ignore already "Kept" files, and builds a working Queue.
* **`ActionService` (with 3-Step Undo)**: 
  * `Keep`: Marks the file as kept in SwiftData.
  * `Trash`: Uses `NSWorkspace.shared.recycle` to move to macOS Trash (safely storing the trashed URL).
  * `Undo`: Restores the last action (moving back from Trash or removing the "Kept" flag in SwiftData). Capped at 3 actions.

### Phase 3: Onboarding & Warning UI
* Build the welcome screen featuring the Retro aesthetic.
* Implement the explicit disclaimer: *"Mandoline does not monitor, log, or use personal media. Deletions are at your own risk. Software is offered as-is."*
* Build the Folder Selection UI displaying currently monitored directories.

### Phase 4: The Mandoline "Retro Gallery" View
* Build the main viewing interface with a dark, nostalgic "retro.app" style aesthetic.
* Implement a `MediaViewer` component:
  * Auto-plays videos with a custom scrubber.
  * Shows high-quality images.
  * Displays file metadata (date, size, name) in a retro terminal-like or film-data overlay.
* Bind keyboard shortcuts: `←` (Trash), `→` (Keep), `Z` (Undo).
* Add satisfying, subtle animations (e.g., swiping left/right out of frame when a decision is made).

---

## 🤖 The Agent Team Structure
To execute this, the Pi team will be structured as follows:
1. **Lead / Architect**: Manages the Xcode project, permissions, and overall architecture.
2. **Core Services Dev**: Builds the recursive file scanning, SwiftData persistence, and the tricky Undo/Trash logic using macOS file coordination.
3. **UI / UX Engineer**: Implements the onboarding, Retro UI, keyboard listeners, and AVKit/Image media previews.
