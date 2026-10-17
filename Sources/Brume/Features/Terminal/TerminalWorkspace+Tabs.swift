import AppKit
import BrumeCore
import GhosttyTerminal

/// `kept` : le terminal actif quand la carte s'ouvre, le seul qui restera. `stopsCommands` : une
/// commande tourne dans un des terminaux qui vont se fermer.
struct ResetPrompt: Equatable {
    let kept: UUID
    let stopsCommands: Bool
}

/// Ce qui porte un nom, une couleur et une icône : un onglet, ou un split d'un groupe.
enum TabItem: Hashable {
    case tab(UUID), pane(UUID)
}

extension TerminalWorkspace {
    /// ⌘T l'ouvre après l'onglet actif, comme Ghostty ; les boutons +, en bout de liste où ils sont.
    /// `folder` : un dossier ouvert dans Brume, à la place de celui du terminal actif.
    func newTab(atEnd: Bool = false, in folder: String? = nil) {
        let pane = UUID()
        states[pane] = makeState(pane, inheriting: focused, as: .window, in: folder)
        apply(atEnd ? layout.appendingTab(UUID(), pane: pane) : layout.addingTab(UUID(), pane: pane))
    }

    func select(_ tab: UUID) {
        apply(layout.selecting(tab))
    }

    func select(number: Int) {
        apply(layout.selecting(number: number))
    }

    func selectNext() {
        apply(layout.selecting(offset: 1))
    }

    func selectPrevious() {
        apply(layout.selecting(offset: -1))
    }

    func move(_ tab: UUID, to index: Int) {
        layout = layout.moving(tab, to: index)
    }

    func move(_ tab: UUID, beside target: UUID, after: Bool) {
        layout = layout.moving(tab, beside: target, after: after)
    }

    func moveSelectedTab(by offset: Int) {
        layout = layout.moving(layout.selectedTab, by: offset)
    }

    /// La croix d'un onglet : confirme si une commande tourne dans un de ses splits.
    func close(_ tab: UUID) {
        guard layout.panes(of: tab).contains(where: hasRunningCommand) else { return removeTab(tab) }
        // Sa feuille parle de cet onglet : on l'affiche avant de demander.
        select(tab)
        CloseConfirmation.tab.ask(in: window) { [weak self] in self?.removeTab(tab) }
    }

    func closeSelectedTab() {
        close(layout.selectedTab)
    }

    func closeOthers(of tab: UUID) {
        close(layout.tabs(besides: tab))
    }

    func closeAfter(_ tab: UUID) {
        close(layout.tabs(after: tab))
    }

    /// Par-dessus les réglages s'ils sont ouverts. Le clavier quitte le terminal pour qu'Entrée et
    /// Échap aillent à la carte.
    func askReset() {
        guard resetPrompt == nil else { return }
        renaming = nil
        let kept = focusedID
        resetPrompt = ResetPrompt(kept: kept, stopsCommands: layout.panes.contains { $0 != kept && hasRunningCommand($0) })
        window?.makeFirstResponder(window?.contentView)
    }

    func cancelReset() {
        resetPrompt = nil
        focus(focusedID)
    }

    /// Retour à une fenêtre neuve : le terminal annoncé par la carte reste, avec son shell, seul dans
    /// son onglet (fermé depuis, rien ne change) ; noms, couleurs, icônes et taille du texte
    /// reviennent à la normale, la fenêtre à sa taille d'ouverture, au centre de l'écran.
    func reset() {
        guard let kept = resetPrompt?.kept, let tab = layout.tab(of: kept) else { return cancelReset() }
        resetPrompt = nil
        layout.panes.filter { $0 != kept }.forEach(forget)
        labels = WindowLabels()
        collapsed = []
        apply(WindowLayout(tab: tab, pane: kept))
        states[kept]?.surface?.performBindingAction("reset_font_size")
        if settingsSection != nil { closeSettings() } else { focus(kept) }
        restoreDefaultFrame()
    }

    /// En plein écran, la fenêtre garde l'écran : sa taille ne veut rien dire.
    private func restoreDefaultFrame() {
        guard let window, let settings, !window.styleMask.contains(.fullScreen),
              let screen = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        let size = window.frameRect(forContentRect: CGRect(origin: .zero, size: BrumeApp.defaultWindowSize(settings))).size
        let frame = CGRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2, width: size.width, height: size.height)
        window.setFrame(frame, display: true, animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    func label(of item: TabItem) -> TabLabel? {
        switch item {
        case let .tab(tab): labels.tabs[tab]
        case let .pane(pane): labels.panes[pane]
        }
    }

    func setColor(_ color: TabColor?, of item: TabItem) {
        updateLabel(of: item) { $0.color = color }
    }

    /// Sans icône choisie, celle du terminal.
    func icon(of item: TabItem) -> TabIcon {
        label(of: item)?.icon ?? .terminal
    }

    func setIcon(_ icon: TabIcon, of item: TabItem) {
        updateLabel(of: item) { $0.icon = icon == .terminal ? nil : icon }
    }

    /// Celle choisie, sinon un split pour un groupe : on le reconnaît en haut comme sur le côté.
    func symbol(of tab: UUID) -> String {
        labels.tabs[tab]?.icon?.symbol ?? (layout.isSplit(tab) ? "square.split.2x1" : TabIcon.terminal.symbol)
    }

    /// Le nom choisi, sinon celui qu'annonce le terminal : la commande en cours, ou le dernier
    /// dossier de son chemin, entier dans l'en-tête et avec « Chemin complet dans les onglets ».
    /// Un groupe sans nom choisi s'appelle « Groupe 1 », « Groupe 2 »…
    func displayedTitle(of item: TabItem) -> String {
        if let title = label(of: item)?.title { return title }
        switch item {
        case let .tab(tab):
            let panes = layout.panes(of: tab)
            guard panes.count == 1 else { return "\(L10n.text(.group)) \(labels.groupNumbers[tab] ?? 1)" }
            return terminalTitle(panes[0])
        case let .pane(pane):
            return terminalTitle(pane)
        }
    }

    /// Celle d'un de ses splits : l'onglet travaille tant que l'un d'eux travaille.
    func progress(of tab: UUID) -> TerminalProgress? {
        layout.panes(of: tab).lazy.compactMap { self.paneProgress[$0] }.first
    }

    /// La plus grave de ses splits : un échec dans l'un rougit tout le groupe.
    func activity(of tab: UUID) -> TerminalActivity? {
        layout.panes(of: tab).compactMap { paneActivity[$0] }.max()
    }

    /// Nil : l'onglet affiché.
    func startRenaming(_ item: TabItem? = nil) {
        guard settingsSection == nil else { return }
        isSidebarHidden = false
        let item = item ?? .tab(layout.selectedTab)
        switch item {
        case let .tab(tab): select(tab)
        case let .pane(pane): focus(pane)
        }
        renaming = item
    }

    /// Nil : renommage annulé. Le champ qui disparaît rappelle cette fonction en perdant le focus :
    /// seul le premier appel compte.
    func finishRenaming(_ item: TabItem, input: String?, displayed: String) {
        guard renaming == item else { return }
        renaming = nil
        if let input {
            updateLabel(of: item) { $0.title = TabTitle.renamed(input: input, displayed: displayed, current: $0.title) }
        }
        focus(focusedID)
    }

    func resetTitle(_ item: TabItem) {
        updateLabel(of: item) { $0.title = nil }
    }

    func toggleCollapsed(_ tab: UUID) {
        collapsed.formSymmetricDifference([tab])
    }

    private func close(_ tabs: [UUID]) {
        guard !tabs.isEmpty else { return }
        guard tabs.flatMap(layout.panes(of:)).contains(where: hasRunningCommand) else { return tabs.forEach(removeTab) }
        CloseConfirmation.tabs.ask(in: window) { [weak self] in tabs.forEach { self?.removeTab($0) } }
    }

    private func removeTab(_ tab: UUID) {
        let panes = layout.panes(of: tab)
        guard let remaining = layout.removingTab(tab) else {
            window?.close()
            return
        }
        panes.forEach(forget)
        apply(remaining)
    }

    private func terminalTitle(_ pane: UUID) -> String {
        let title = terminalTitles[pane] ?? ""
        if title.isEmpty { return L10n.text(.terminal) }
        return settings?.showsFullPath == true ? title : TabTitle.short(title)
    }

    private func updateLabel(of item: TabItem, _ change: (inout TabLabel) -> Void) {
        var label = label(of: item) ?? TabLabel()
        change(&label)
        let value = label.isEmpty ? nil : label
        switch item {
        case let .tab(tab): labels.tabs[tab] = value
        case let .pane(pane): labels.panes[pane] = value
        }
    }
}
