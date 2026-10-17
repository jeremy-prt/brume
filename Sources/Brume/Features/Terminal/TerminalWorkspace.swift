import BrumeCore
import Combine
import Foundation
import GhosttyTerminal
import SwiftUI

// Un seul moteur pour tous les onglets, fenêtres et splits, comme Ghostty.
@MainActor private let sharedController: TerminalController = {
    let controller = TerminalController(terminalConfiguration: engineConfiguration(engineOptions))
    // Brume reste sombre : sans ça, le moteur part en clair le temps qu'une vue lui donne l'apparence.
    controller.setColorScheme(.dark)
    return controller
}()

/// Ce que les réglages changent dans la config du moteur, commune à toutes les fenêtres.
private struct EngineOptions {
    var isTranslucent = false
    var font = TerminalFont.standard
}

@MainActor private var engineOptions = EngineOptions() {
    didSet { sharedController.setTerminalConfiguration(engineConfiguration(engineOptions)) }
}

private func engineConfiguration(_ options: EngineOptions) -> TerminalConfiguration {
    TerminalConfiguration {
        // Gérées par le patch zsh de Patches/ : le script du paquet les ignore.
        $0.withCustom("shell-integration-features", "ssh-env,ssh-terminfo")
        // L'app Ghostty double les deltas du trackpad avant le moteur, le paquet non :
        // sans ça, le défilement est deux fois plus lent que dans Ghostty.
        $0.withCustom("mouse-scroll-multiplier", "precision:2")
        // Shift+Entrée : saut de ligne dans Claude Code.
        $0.withCustom("keybind", "shift+enter=text:\\n")
        $0.withCustom("macos-option-as-alt", "left")
        // Option+flèche brut, sans le « mot précédent / suivant » de Ghostty.
        $0.withCustom("keybind", "alt+left=unbind")
        $0.withCustom("keybind", "alt+right=unbind")
        // En verre, le voile vient du fond de la fenêtre, d'un seul tenant sous les onglets et
        // les terminaux : le moteur ne peint plus son fond par-dessus.
        $0.withBackgroundOpacity(options.isTranslucent ? 0 : 1)
        if let family = options.font.family {
            $0.withFontFamily(family)
        }
        $0.withFontSize(Float(options.font.size))
    }
}

/// Les fenêtres ouvertes, dans l'ordre où elles se sont ouvertes : la session les rouvrira
/// dans le même ordre, et un changement de couleurs passe par tous leurs terminaux.
@MainActor private var openWorkspaces: [WeakWorkspace] = []

private struct WeakWorkspace {
    weak var value: TerminalWorkspace?
}

/// Pour qu'un nouvel onglet ou une nouvelle fenêtre reprenne son zoom et son dossier.
@MainActor weak var lastFocused: TerminalViewState?

/// Commune à toutes les fenêtres : un seul terminal a le clavier.
@MainActor private let secureInput = SecureInput()

enum FontSizeChange {
    case increase, decrease, reset
}

/// Une fenêtre comme Ghostty : des onglets, chacun divisé en splits, un terminal par split.
@MainActor @Observable
final class TerminalWorkspace {
    var layout: WindowLayout<UUID, UUID> {
        // Un autre split prend le clavier, ou l'onglet change : fin de l'agrandissement.
        didSet {
            if let zoomedPane, layout.focusedPane != zoomedPane || !isSplit { self.zoomedPane = nil }
            onSnapshotChange?()
        }
    }
    /// Les terminaux, par split.
    var states: [UUID: TerminalViewState] = [:]
    private(set) var searches: [UUID: TerminalSearch] = [:]
    /// Le titre et la progression que chaque terminal annonce, relevés ici : un onglet ou un
    /// groupe qui les affiche se met à jour sans observer chacun de ses terminaux.
    private(set) var terminalTitles: [UUID: String] = [:]
    private(set) var paneProgress: [UUID: TerminalProgress] = [:]
    /// Les noms, couleurs et icônes choisis, des onglets et des splits d'un groupe.
    var labels = WindowLabels<UUID, UUID>() {
        didSet { onSnapshotChange?() }
    }
    /// Les onglets divisés repliés dans la barre latérale.
    var collapsed: Set<UUID> = [] {
        didSet { onSnapshotChange?() }
    }
    var renaming: TabItem?
    /// Masquage temporaire propre à cette fenêtre, sans changer l'orientation enregistrée.
    var isSidebarHidden = false
    /// Les splits où une commande ou une progression a fini, où ça a sonné ou notifié (Claude Code
    /// qui attend une réponse) depuis qu'on les a regardés.
    private(set) var paneActivity: [UUID: TerminalActivity] = [:] {
        didSet { if paneActivity.count != oldValue.count { updateDockBadge() } }
    }
    /// Le split agrandi à tout l'onglet le temps de lire, comme `toggle_split_zoom` de Ghostty.
    var zoomedPane: UUID?
    var drop: WindowLayout<UUID, UUID>.Drop?
    /// La page de réglages affichée à la place des terminaux, qui restent ouverts dessous.
    private(set) var settingsSection: SettingsSection?
    /// La carte qui demande avant de réinitialiser la fenêtre.
    var resetPrompt: ResetPrompt?
    /// Pour les raccourcis du clic droit.
    @ObservationIgnored weak var settings: SettingsStore?
    /// Ce que `snapshot` enregistre a changé : la session s'enregistrera peu après.
    @ObservationIgnored var onSnapshotChange: (() -> Void)?
    /// La place des splits, posée par `TerminalSplitView` pour calculer les dépôts.
    @ObservationIgnored var bounds: CGRect = .zero
    @ObservationIgnored private(set) weak var window: NSWindow?
    @ObservationIgnored private var closeGuard: WindowCloseGuard?
    @ObservationIgnored private var watchers: [UUID: [AnyCancellable]] = [:]
    @ObservationIgnored private var visitedFolders: [UUID: RecentFolders] = [:]
    @ObservationIgnored private var windowWatchers: [AnyCancellable] = []
    /// La place de la fenêtre restaurée, posée quand elle s'ouvre.
    @ObservationIgnored private var savedFrame: CGRect?

    static var needsConfirmQuit: Bool {
        sharedController.needsConfirmQuit
    }

    /// Avant le premier terminal : il s'ouvre déjà avec le thème et la police choisis.
    static func prepareEngine(_ settings: AppSettings) {
        engineOptions.font = settings.font
        ThemeFade.start(with: TerminalThemes.colors(for: settings.appearance))
    }

    /// Le moteur est commun à toutes les fenêtres : sans changement, l'appel ne fait rien.
    static func setTranslucent(_ isTranslucent: Bool) {
        engineOptions.isTranslucent = isTranslucent
    }

    static func setFont(_ font: TerminalFont) {
        engineOptions.font = font
    }

    /// Par les terminaux et pas le moteur seul : chacun doit reprendre la couleur de fond du thème.
    static func applyEngineTheme(_ theme: TerminalTheme) {
        sharedController.setTheme(theme)
        for workspace in all {
            for state in workspace.states.values {
                state.setTheme(theme)
            }
        }
    }

    static var all: [TerminalWorkspace] {
        openWorkspaces.removeAll { $0.value == nil }
        return openWorkspaces.compactMap(\.value)
    }

    /// Nil : une fenêtre neuve, un onglet dans le dossier du terminal actif.
    init(restoring saved: SavedWindow? = nil) {
        guard let saved, saved.layout.isConsistent else {
            let pane = UUID()
            layout = WindowLayout(tab: UUID(), pane: pane)
            states[pane] = makeState(pane, inheriting: lastFocused, as: .window, in: Self.folderForNewWindow)
            Self.folderForNewWindow = nil
            openWorkspaces.append(WeakWorkspace(value: self))
            return
        }
        layout = saved.layout
        savedFrame = saved.frame
        let shown = Set(saved.layout.panes(of: saved.layout.selectedTab))
        for pane in saved.layout.panes {
            let state = makeState(pane, inheriting: nil, as: .window, in: saved.panes[pane]?.workingDirectory)
            state.isSurfaceVisible = shown.contains(pane)
            states[pane] = state
        }
        for tab in saved.layout.tabs {
            guard let info = saved.tabs[tab] else { continue }
            if !info.label.isEmpty { labels.tabs[tab] = info.label }
            labels.groupNumbers[tab] = info.groupNumber
            if info.isCollapsed { collapsed.insert(tab) }
        }
        for (pane, info) in saved.panes {
            labels.panes[pane] = info.label
        }
        // Une session sans numéros de groupe les reçoit ici.
        labels = labels.reconciled(from: layout, to: layout)
        openWorkspaces.append(WeakWorkspace(value: self))
    }

    /// Ce que la fenêtre retrouvera au prochain lancement.
    var snapshot: SavedWindow {
        let tabs = Dictionary(uniqueKeysWithValues: layout.tabs.map { tab in
            (tab, SavedTab(label: labels.tabs[tab], isCollapsed: collapsed.contains(tab), groupNumber: labels.groupNumbers[tab]))
        })
        let panes = Dictionary(uniqueKeysWithValues: layout.panes.map { pane in
            // Le dossier de départ tant que le shell n'a pas encore annoncé le sien.
            (pane, SavedPane(
                workingDirectory: states[pane].flatMap { $0.workingDirectory ?? $0.configuration.workingDirectory },
                label: labels.panes[pane]
            ))
        })
        return SavedWindow(layout: layout, tabs: tabs, panes: panes, frame: window?.frame ?? savedFrame)
    }

    /// Le split qui a le clavier, dans l'onglet affiché.
    var focusedID: UUID {
        layout.focusedPane
    }

    var focused: TerminalViewState {
        states[focusedID]!
    }

    var focusedSearch: TerminalSearch? {
        searches[focusedID]
    }

    /// L'onglet affiché est divisé.
    var isSplit: Bool {
        layout.isSplit(layout.selectedTab)
    }

    func attach(to window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        window.tabbingMode = .disallowed
        // Pas sur un écran débranché depuis : la fenêtre rouvrirait invisible.
        if let savedFrame, let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(savedFrame) }) {
            window.setFrame(window.constrainFrameRect(savedFrame, to: screen), display: true)
        }
        savedFrame = nil
        closeGuard = WindowCloseGuard(on: window) { [weak self] window in
            guard let self, states.values.contains(where: Self.isRunning) else { return true }
            (states.count > 1 ? CloseConfirmation.window : .terminal).ask(in: window) { window.close() }
            return false
        }
        let center = NotificationCenter.default
        windowWatchers = [
            center.publisher(for: NSWindow.willCloseNotification, object: window).sink { [weak self] _ in self?.windowWillClose() },
            center.publisher(for: NSWindow.didMoveNotification, object: window)
                .merge(with: center.publisher(for: NSWindow.didResizeNotification, object: window))
                .sink { [weak self] _ in self?.onSnapshotChange?() },
        ]
        Self.serveWaitingActions()
    }

    /// La fenêtre sort tout de suite de la session : SwiftUI peut libérer l'espace de travail plus tard.
    private func windowWillClose() {
        openWorkspaces.removeAll { $0.value == nil || $0.value === self }
        onSnapshotChange?()
        updateDockBadge()
        Self.withdrawNotifications(of: states.keys)
        for pane in states.keys {
            secureInput.set(pane, isAsking: false)
        }
    }

    /// Aucun terminal ne reprend le clavier avant le retour : la frappe irait dans un terminal qu'on
    /// ne voit pas. Le focus va au contenu SwiftUI, pas à la fenêtre : Tab mène alors au premier
    /// champ des réglages.
    func showSettings(_ section: SettingsSection? = nil) {
        settingsSection = section ?? settingsSection ?? .general
        window?.makeFirstResponder(window?.contentView)
        updateSurfaces()
    }

    func closeSettings() {
        settingsSection = nil
        updateSurfaces()
        focus(focusedID)
    }

    /// L'entrée des actions du menu sur les terminaux : la page de réglages ou la carte qui les
    /// couvre se ferme d'abord, sinon l'action agirait dessous sans qu'on la voie.
    func showingTerminals(_ action: (TerminalWorkspace) -> Void) {
        if resetPrompt != nil { cancelReset() }
        if settingsSection != nil { closeSettings() }
        action(self)
    }

    /// Comme le bouton rouge : passe par la confirmation de `WindowCloseGuard`.
    func closeWindow() {
        window?.performClose(nil)
    }

    // MARK: Terminal actif

    /// Passe par le moteur, qui signale une commande en cours à `onClose`. Sur la carte ou la page
    /// de réglages, Cmd+W referme celle du dessus plutôt que le terminal caché dessous.
    func closeFocused() {
        if resetPrompt != nil { return cancelReset() }
        guard settingsSection == nil else { return closeSettings() }
        focused.surface?.performBindingAction("close_surface")
    }

    func changeFontSize(_ change: FontSizeChange) {
        let action = switch change {
        case .increase: "increase_font_size:1"
        case .decrease: "decrease_font_size:1"
        case .reset: "reset_font_size"
        }
        focused.surface?.performBindingAction(action)
    }

    func clearScreen() {
        focused.surface?.performBindingAction("clear_screen")
    }

    func toggleSearch() {
        if searches[focusedID] == nil {
            openSearch(in: focusedID, needle: "")
        } else {
            endSearch(in: focusedID)
        }
    }

    /// Le moteur répond par `start_search` avec la sélection : voir `makeState`.
    func searchSelection() {
        focused.surface?.performBindingAction("search_selection")
    }

    func endSearch(in pane: UUID) {
        guard let search = searches.removeValue(forKey: pane) else { return }
        search.end()
        focus(pane)
    }

    // MARK: Interne

    func hasRunningCommand(_ pane: UUID) -> Bool {
        states[pane].map(Self.isRunning) ?? false
    }

    private static func isRunning(_ state: TerminalViewState) -> Bool {
        state.surface?.needsConfirmQuit == true
    }

    private func openSearch(in pane: UUID, needle: String) {
        guard let state = states[pane] else { return }
        if let search = searches[pane] {
            if !needle.isEmpty { search.needle = needle }
        } else {
            searches[pane] = TerminalSearch(state: state, needle: needle)
        }
        searches[pane]?.focusField()
    }

    /// `close()` et pas `performClose` : la confirmation a déjà eu lieu.
    func remove(_ pane: UUID) {
        guard let remaining = layout.removing(pane) else {
            window?.close()
            return
        }
        forget(pane)
        apply(remaining)
    }
    func forget(_ pane: UUID) {
        states[pane] = nil
        searches[pane] = nil
        watchers[pane] = nil
        visitedFolders[pane] = nil
        terminalTitles[pane] = nil
        paneProgress[pane] = nil
        paneActivity[pane] = nil
        Self.withdrawNotifications(of: [pane])
        secureInput.set(pane, isAsking: false)
    }

    /// Le terminal attend un mot de passe, et macOS cache sa frappe aux autres apps.
    func isSecured(_ pane: UUID) -> Bool {
        secureInput.isSecured(pane)
    }

    /// Seul l'onglet affiché dessine ; les autres gardent leurs shells. Le focus suit le split actif.
    func apply(_ new: WindowLayout<UUID, UUID>) {
        let previous = layout.focusedPane
        let reconciled = labels.reconciled(from: layout, to: new)
        if reconciled != labels { labels = reconciled }
        // Un onglet redevenu seul oublie qu'il était replié : divisé à nouveau, il s'ouvre.
        let groups = Set(new.tabs.filter(new.isSplit))
        if !collapsed.isSubset(of: groups) { collapsed.formIntersection(groups) }
        layout = new
        updateSurfaces()
        if new.focusedPane != previous {
            lastFocused = states[new.focusedPane]
            if isKeyboardFree { states[new.focusedPane]?.requestFocus() }
        }
    }

    /// Ni réglages ni carte par-dessus : un terminal peut reprendre le clavier.
    var isKeyboardFree: Bool {
        settingsSection == nil && resetPrompt == nil
    }

    /// Les splits de l'onglet affiché, ou seulement celui agrandi.
    var shownPanes: Set<UUID> {
        if let zoomedPane { return [zoomedPane] }
        return Set(layout.panes(of: layout.selectedTab))
    }

    /// Seuls les terminaux affichés se dessinent : ni les autres onglets, ni rien sous les réglages.
    func updateSurfaces() {
        let shown = shownPanes
        markSeen(shown)
        let drawn = settingsSection == nil ? shown : []
        for (pane, state) in states {
            state.isSurfaceVisible = drawn.contains(pane)
        }
    }

    /// Brume en arrière-plan, même le terminal affiché n'est pas vu.
    private func note(_ event: TerminalEvent, in pane: UUID) {
        notify(event, in: pane)
        guard !NSApp.isActive || !shownPanes.contains(pane) else { return }
        let activity = TerminalActivity.after(event, from: paneActivity[pane])
        if paneActivity[pane] != activity { paneActivity[pane] = activity }
    }

    /// Ce qui est à l'écran quand Brume est au premier plan : sa pastille et ses notifications partent.
    func markSeen(_ panes: Set<UUID>) {
        guard NSApp.isActive else { return }
        let seen = panes.filter { paneActivity[$0] != nil }
        guard !seen.isEmpty else { return }
        for pane in seen {
            paneActivity[pane] = nil
        }
        Self.withdrawNotifications(of: seen)
    }

    /// `folder` : le dossier où part le terminal, à la place de celui hérité.
    func makeState(
        _ pane: UUID,
        inheriting parent: TerminalViewState?,
        as context: TerminalSurfaceContext,
        in folder: String? = nil
    ) -> TerminalViewState {
        let state = TerminalViewState(controller: sharedController)
        // Comme Ghostty : un nouveau terminal part du zoom et du dossier de celui qui avait le focus.
        if let inherited = parent?.surface?.inheritedOptions(for: context) {
            if inherited.fontSize > 0 { state.configuration.fontSize = inherited.fontSize }
            state.configuration.workingDirectory = inherited.workingDirectory
        }
        if let folder { state.configuration.workingDirectory = folder }
        // Cmd+W passe par le moteur, qui signale une commande en cours.
        state.onClose = { [weak self] processAlive in
            guard let self else { return }
            guard processAlive else { return remove(pane) }
            CloseConfirmation.terminal.ask(in: window) { [weak self] in self?.remove(pane) }
        }
        watchers[pane] = [
            Self.steadyTitle(of: state).sink { [weak self] in self?.terminalTitles[pane] = $0 },
            state.$workingDirectory.removeDuplicates().dropFirst().sink { [weak self] _ in self?.onSnapshotChange?() },
            state.$workingDirectory.compactMap { $0 }.removeDuplicates().sink { [weak self] in
                self?.visitedFolders[pane, default: RecentFolders()].visit($0)
            },
            state.$progress.removeDuplicates().sink { [weak self] in self?.paneProgress[pane] = $0 },
            state.$isPasswordInput.combineLatest(state.$isFocused).map { $0 && $1 }.removeDuplicates()
                .sink { secureInput.set(pane, isAsking: $0) },
            Self.events(of: state).sink { [weak self] in self?.note($0, in: pane) },
        ]
        state.makePlatformView = { [weak self] in
            let view = BrumeTerminalView(frame: .zero)
            view.onContextMenu = { [weak self] in
                guard let self else { return }
                TerminalContextMenu.show(for: pane, in: self)
            }
            view.onSelectTab = { [weak self] offset in
                self?.showingTerminals { offset > 0 ? $0.selectNext() : $0.selectPrevious() }
            }
            return view
        }
        state.onStartSearch = { [weak self] in self?.openSearch(in: pane, needle: $0) }
        state.onEndSearch = { [weak self] in self?.endSearch(in: pane) }
        state.onOpenURL = { [weak self, weak state] in
            let current = state?.workingDirectory ?? state?.configuration.workingDirectory
            return LinkOpener.open($0, from: [current].compactMap { $0 } + (self?.visitedFolders[pane]?.all ?? []))
        }
        return state
    }

    /// L'intégration shell titre l'onglet de la commande lancée, puis du dossier au retour du prompt :
    /// un `ls` le faisait clignoter. Un titre ne s'affiche qu'après 0,4 s, sauf le premier.
    private static func steadyTitle(of state: TerminalViewState) -> some Publisher<String, Never> {
        let title = state.$title.removeDuplicates()
        return title.prefix(1)
            .merge(with: title.dropFirst().debounce(for: .milliseconds(400), scheduler: DispatchQueue.main))
            .removeDuplicates()
    }

    /// Un `@Published` prévient avant de changer : le paquet pose le code de sortie avant la durée,
    /// le titre et le texte d'une notification avant son heure, qu'on lit donc déjà à jour.
    private static func events(of state: TerminalViewState) -> some Publisher<TerminalEvent, Never> {
        Publishers.Merge4(
            state.$lastCommandDurationNanos.dropFirst().map { [weak state] duration in
                TerminalEvent.commandFinished(exitCode: state?.lastCommandExitCode, duration: .nanoseconds(duration ?? 0))
            },
            state.$bellCount.dropFirst().map { _ in TerminalEvent.bell },
            state.$lastDesktopNotificationAt.dropFirst().map { [weak state] _ in
                TerminalEvent.notification(title: state?.lastDesktopNotificationTitle ?? "", body: state?.lastDesktopNotificationBody ?? "")
            },
            state.$progress.map { $0 != nil }.removeDuplicates().dropFirst().filter { !$0 }.map { _ in TerminalEvent.progressEnded }
        )
    }
}

private struct TerminalWorkspaceKey: FocusedValueKey {
    typealias Value = TerminalWorkspace
}

extension FocusedValues {
    var terminalWorkspace: TerminalWorkspace? {
        get { self[TerminalWorkspaceKey.self] }
        set { self[TerminalWorkspaceKey.self] = newValue }
    }
}
