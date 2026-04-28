import SwiftUI
import AppKit

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
