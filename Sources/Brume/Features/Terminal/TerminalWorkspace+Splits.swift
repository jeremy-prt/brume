import BrumeCore
import Foundation

extension TerminalWorkspace {
    /// Nil : le split actif. Le groupe se déplie : le nouveau split s'y voit.
    func split(_ axis: SplitAxis, from origin: UUID? = nil) {
        if let origin { focus(origin) }
        let pane = UUID()
        states[pane] = makeState(pane, inheriting: focused, as: .split)
        collapsed.remove(layout.selectedTab)
        apply(layout.splitting(toward: axis == .horizontal ? .right : .down, pane: pane))
    }

    func setRatio(_ ratio: CGFloat, at path: [Int]) {
        layout = layout.settingRatio(ratio, at: path)
    }

    /// Nil : le terminal actif.
    func toggleZoom(_ pane: UUID? = nil) {
        if let pane { focus(pane) }
        zoomedPane = zoomedPane == nil && isSplit ? focusedID : nil
        updateSurfaces()
    }

    func equalizeSplits() {
        layout = layout.equalized()
    }

    /// Cmd+0 ne remet que le terminal actif, comme Ghostty : ici, toute la fenêtre.
    func resetSizes() {
        for state in states.values {
            state.surface?.performBindingAction("reset_font_size")
        }
        equalizeSplits()
    }

    func focusNext() {
        apply(layout.focusingPane(offset: 1))
    }

    func focusPrevious() {
        apply(layout.focusingPane(offset: -1))
    }

    func focus(toward direction: SplitDirection) {
        apply(layout.focusingPane(toward: direction))
    }

    /// La croix d'un split dans la barre latérale : confirme si une commande y tourne.
    func closePane(_ pane: UUID) {
        guard states[pane] != nil else { return }
        guard hasRunningCommand(pane) else { return remove(pane) }
        focus(pane)
        CloseConfirmation.terminal.ask(in: window) { [weak self] in self?.remove(pane) }
    }

    func focus(_ pane: UUID) {
        apply(layout.focusing(pane))
        lastFocused = states[pane]
        if isKeyboardFree { states[pane]?.requestFocus() }
    }

    /// Un clic donne déjà le focus au terminal : on ne fait que suivre.
    func didFocus(_ pane: UUID) {
        layout = layout.focusing(pane)
        lastFocused = states[pane]
    }

    /// Chaque split de l'onglet part dans son propre onglet ; le clavier reste où il était.
    func separate(_ tab: UUID) {
        let pane = layout.splits[tab]?.focused
        apply(layout.separating(tab, into: layout.panes(of: tab).dropFirst().map { _ in UUID() }))
        if let pane { focus(pane) }
    }

    func detach(_ pane: UUID, at index: Int? = nil) {
        apply(layout.detaching(pane, into: UUID(), at: index))
        focus(pane)
    }
}
