import BrumeCore
import Foundation

extension TerminalWorkspace {
    /// Deux splits d'un groupe échangent leur place, glissés l'un sur l'autre dans la barre latérale.
    func swap(_ a: UUID, _ b: UUID) {
        layout = layout.swapping(a, b)
    }

    /// Sur les terminaux. Nil : plus de glisser en cours, ou rien à proposer ici.
    func hoverDrop(dragging: WindowLayout<UUID, UUID>.Dragged, at point: CGPoint?) {
        if point != nil { unzoom() }
        let new = point.flatMap { layout.drop(of: dragging, at: $0, in: bounds) }
        if new != drop { drop = new }
    }

    /// Lâché sur les splits de l'onglet affiché, il les rejoint, avec son nom.
    func performDrop() {
        guard let drop else { return }
        self.drop = nil
        apply(layout.dropping(drop))
        focus(layout.focusedPane)
    }

    func merge(_ tab: UUID, into target: UUID) {
        guard tab != target, layout.tabs.contains(tab), layout.tabs.contains(target) else { return }
        unzoom()
        collapsed.remove(target)
        apply(layout.merging(tab, into: target))
        focus(layout.focusedPane)
    }

    private func unzoom() {
        guard zoomedPane != nil else { return }
        zoomedPane = nil
        updateSurfaces()
    }
}
