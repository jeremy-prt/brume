import AppKit
import SwiftUI

/// Fond de la barre du haut : glisser déplace la fenêtre, double-cliquer suit le réglage
/// macOS (agrandir, réduire ou rien).
struct WindowDragArea: NSViewRepresentable {
    /// À la place du réglage macOS, pour une zone qui n'est pas une barre de titre.
    var onDoubleClick: (() -> Void)?

    func makeNSView(context: Context) -> DragSurface {
        DragSurface()
    }

    func updateNSView(_ view: DragSurface, context: Context) {
        view.onDoubleClick = onDoubleClick
    }

    final class DragSurface: NSView {
        var onDoubleClick: (() -> Void)?
        private var pressed: NSEvent?

        // Dragging and double-clicks are handled below; AppKit must not also treat them as title-bar clicks.
        override var mouseDownCanMoveWindow: Bool { false }

        override func isAccessibilityElement() -> Bool {
            false
        }

        override func mouseDown(with event: NSEvent) {
            pressed = event
        }

        // Le déplacement ne part qu'au premier mouvement : lancé dès l'appui, il avalerait le
        // second clic d'un double-clic.
        override func mouseDragged(with event: NSEvent) {
            guard let pressed else { return }
            self.pressed = nil
            window?.performDrag(with: pressed)
        }

        override func mouseUp(with event: NSEvent) {
            pressed = nil
            guard event.clickCount == 2 else { return }
            if let onDoubleClick {
                return onDoubleClick()
            }
            switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
            case "Minimize": window?.miniaturize(nil)
            case "None": break
            default: window?.zoom(nil)
            }
        }
    }
}
