import BrumeCore
import SwiftUI

struct TerminalScreen: View {
    /// Toute la fenêtre : barres d'onglets, terminaux et glissés partagent cet espace.
    nonisolated static let space = "terminal-screen"

    @Environment(SessionStore.self) private var session
    @Environment(SettingsStore.self) private var settings
    @Environment(\.openWindow) private var openWindow
    /// Créé à l'apparition et pas à l'init : SwiftUI peut refaire l'init, et chaque appel
    /// consommerait une fenêtre de la session.
    @State private var workspace: TerminalWorkspace?

    var body: some View {
        ZStack {
            if let workspace {
                TerminalWindow(workspace: workspace, translucency: settings.appearance.translucency, showsSidebar: settings.verticalTabs.isOn)
            }
        }
        .onAppear {
            guard workspace == nil else { return }
            TerminalWorkspace.prepareEngine(settings.settings)
            workspace = session.makeWorkspace()
            // `open Brume.app --args -BrumeSettings welcome` ouvre une page des réglages pour la vérifier
            // sans piloter l'interface, une fois la fenêtre rattachée pour que le focus y aille comme avec ⌘,.
            if let name = UserDefaults.standard.string(forKey: "BrumeSettings"), let section = SettingsSection(rawValue: name) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [workspace] in workspace?.showSettings(section) }
            }
            for _ in 0 ..< session.takeWindowsToOpen() {
                openWindow(id: BrumeApp.terminalWindowID)
            }
        }
    }
}

private struct TerminalWindow: View {
    let workspace: TerminalWorkspace

    @State private var titlebar = WindowTitlebar()
    @State private var commandKey = CommandKeyHold()
    @State private var translucency: TranslucencyTransition
    /// La largeur de la barre latérale pendant qu'on glisse son bord : enregistrée au lâcher.
    @State private var draggedSidebarWidth: CGFloat?
    /// Les onglets affichés en haut ou sur le côté, en retard sur le réglage le temps d'un fondu :
    /// une vue terminal ne s'anime pas, elle sauterait à sa nouvelle place sous les yeux.
    @State private var showsSidebar: Bool
    @State private var isSwitchingTabs = false
    @Environment(SettingsStore.self) private var settings
    /// Cmd+chiffre n'agit que sur la fenêtre active : les autres ne montrent pas de numéros.
    @Environment(\.appearsActive) private var isActive

    init(workspace: TerminalWorkspace, translucency: Translucency, showsSidebar: Bool) {
        self.workspace = workspace
        _translucency = State(initialValue: TranslucencyTransition(translucency))
        _showsSidebar = State(initialValue: showsSidebar)
    }

    var body: some View {
        let sidebarVisible = settings.verticalTabs.isOn && !workspace.isSidebarHidden
        ZStack {
            let showsTerminals = workspace.settingsSection == nil
            let showsNumbers = commandKey.isHeld && isActive
            let sidebarWidth = showsSidebar ? draggedSidebarWidth ?? settings.verticalTabs.width : nil
            // Cachés et non retirés : une vue terminal recréée tuerait son shell. La barre latérale
            // s'ajoute à côté, sans déplacer `TerminalSplitView` dans l'arbre.
            ZStack(alignment: .topLeading) {
                TerminalSplitView(
                    workspace: workspace, titlebar: titlebar, showsNumbers: showsNumbers,
                    sidebarWidth: sidebarWidth, showsHorizontalTabs: !settings.verticalTabs.isOn
                )
                if let sidebarWidth {
                    TabSidebar(
                        workspace: workspace,
                        width: sidebarWidth,
                        topInset: titlebar.buttonsCenterY * 2,
                        showsNumbers: showsNumbers,
                        onResize: { draggedSidebarWidth = $0 },
                        onResizeEnd: {
                            if let width = draggedSidebarWidth { settings.verticalTabs.width = width }
                            draggedSidebarWidth = nil
                        }
                    )
                }
            }
            .coordinateSpace(.named(TerminalScreen.space))
            .opacity(showsTerminals && !isSwitchingTabs ? 1 : 0)
            .allowsHitTesting(showsTerminals)
            .accessibilityHidden(!showsTerminals)
            if let section = workspace.settingsSection {
                SettingsPage(workspace: workspace, section: section, titlebar: titlebar)
                    .transition(.opacity)
            }
            if let prompt = workspace.resetPrompt {
                ConfirmationCard(
                    title: L10n.text(.resetWindowTitle),
                    message: L10n.text(.resetWindowMessage),
                    background: Color(hex: TerminalThemes.colors(for: settings.appearance).background),
                    warning: prompt.stopsCommands ? L10n.text(.resetWindowRunning) : nil,
                    confirmLabel: L10n.text(.reset),
                    onConfirm: workspace.reset,
                    onCancel: workspace.cancelReset
                )
            }
        }
        .animation(Ink.motion(.easeOut(duration: 0.18)), value: workspace.settingsSection)
        .ignoresSafeArea(.container, edges: .top)
        .modifier(TerminalWindowChrome(
            state: workspace.focused,
            customTitle: workspace.label(of: .tab(workspace.layout.selectedTab))?.title,
            translucency: translucency.shown
        ))
        .focusedSceneValue(\.terminalWorkspace, workspace)
        .background(WindowReader {
            workspace.attach(to: $0)
            titlebar.attach(to: $0)
            translucency.attach(to: $0)
        })
        .onAppear { workspace.focus(workspace.focusedID) }
        .tint(settings.appearance.accent.color)
        .environment(\.accent, settings.appearance.accent)
        .animation(Ink.motion(.easeInOut(duration: 0.3)), value: settings.appearance.accent)
        .onChange(of: settings.appearance.translucency) { translucency.animate(to: $1) }
        .onChange(of: TerminalThemes.colors(for: settings.appearance)) { ThemeFade.run(to: $1) }
        .onChange(of: settings.font) { TerminalWorkspace.setFont($1) }
        .task(id: settings.shortcuts[.selectTab]) { commandKey.modifiers = settings.tabNumberModifiers }
        .onChange(of: sidebarVisible) { _, isOn in
            withAnimation(Ink.motion(.easeIn(duration: 0.1))) { isSwitchingTabs = true } completion: {
                showsSidebar = isOn
                // Un tour de plus : les terminaux se redessinent à leur taille avant de réapparaître.
                withAnimation(Ink.motion(.easeOut(duration: 0.18).delay(0.03))) { isSwitchingTabs = false }
            }
        }
    }
}
