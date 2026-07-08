import SwiftUI
import AppKit

// Configures the host NSWindow so the titlebar is a seamless part of the UI:
// fully transparent with no title and no separator line. Window dragging is
// handled by a narrow explicit titlebar drag region instead of making the whole
// SwiftUI background draggable, because that steals canvas drag gestures.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { apply(to: view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { apply(to: nsView.window) }
    }

    private func apply(to window: NSWindow?) {
        guard let window else { return }
        // Let the SwiftUI content (themeBackground) flow under the titlebar so
        // the bar is a seamless part of the UI — no color step, no separator.
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.titleVisibility = .hidden
        window.title = ""
        window.isMovableByWindowBackground = false
    }
}

/// A narrow AppKit-backed drag strip for the hidden titlebar area. Keeping this
/// explicit prevents canvas/card drags from becoming whole-window drags while
/// still preserving native-feeling window movement from the top chrome.
struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        TitlebarDragView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class TitlebarDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

// Invisible view to catch keyboard events globally within the window
struct KeyEventHandlingView: NSViewRepresentable {
    var onKeyPress: (String) -> Void
    
    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        view.onKeyPress = onKeyPress
        DispatchQueue.main.async {
            // Make sure this view becomes first responder so it receives key events.
            view.window?.makeFirstResponder(view)
        }
        return view
    }
    
    func updateNSView(_ nsView: KeyView, context: Context) {
        // Keep the callback updated across SwiftUI view updates.
        nsView.onKeyPress = onKeyPress
    }
}

class KeyView: NSView {
    var onKeyPress: ((String) -> Void)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        // Prevent key-repeat from spamming actions (especially Undo)
        if event.isARepeat { return }

        if let chars = event.charactersIgnoringModifiers {
            if chars == "[" {
                onKeyPress?("[")
                return
            } else if chars == "]" {
                onKeyPress?("]")
                return
            } else if chars.lowercased() == "z" {
                onKeyPress?("z")
                return
            }
        }
        
        switch event.keyCode {
        case 123: // Left Arrow
            onKeyPress?("left")
        case 124: // Right Arrow
            onKeyPress?("right")
        case 53:  // Esc
            onKeyPress?("esc")
        case 36:  // Enter/Return
            onKeyPress?("enter")
        default:
            super.keyDown(with: event)
        }
    }
}
