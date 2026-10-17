import BrumeCore
import GhosttyTerminal
import SwiftUI

/// Les splits de l'onglet affiché, sous la barre d'onglets du haut, ou à droite de la barre latérale.
struct TerminalSplitView: View {
    let workspace: TerminalWorkspace
    let titlebar: WindowTitlebar
    let showsNumbers: Bool
    let sidebarWidth: CGFloat?
    let showsHorizontalTabs: Bool

    var body: some View {
        GeometryReader { geometry in
            let window = CGRect(origin: .zero, size: geometry.size)
            // Sans barre latérale, les boutons de fenêtre ne doivent pas recouvrir le shell.
            let barHeight = showsHorizontalTabs || sidebarWidth == nil ? titlebar.buttonsCenterY * 2 : 0
            // Le trait du bord de la barre latérale a sa propre colonne.
            let bounds = window.divided(atDistance: sidebarWidth.map { $0 + 1 } ?? 0, from: .minXEdge).remainder
                .divided(atDistance: barHeight, from: .minYEdge).remainder
            let layout = workspace.layout
            let tabOfPane = layout.tabOfPane
            let zoomed = workspace.zoomedPane
            // Chaque onglet garde la place de ses splits, affiché ou non : en changer ne
            // redimensionne aucun terminal. Le split agrandi couvre les autres.
            let frames = layout.tabs.reduce(into: [UUID: CGRect]()) { result, tab in
                result.merge(layout.splits[tab]?.tree.frames(in: bounds) ?? [:]) { $1 }
            }.merging(zoomed.map { [$0: bounds] } ?? [:]) { $1 }
            // Les terminaux de tous les onglets au même niveau, rangés par identifiant : changer
            // d'onglet, diviser ou déplacer un onglet garde chaque vue. Une vue recréée tuerait
            // le shell qu'elle porte. Ceux des autres onglets restent montés, transparents.
            ZStack(alignment: .topLeading) {
                ForEach(layout.panes, id: \.self) { pane in
                    if let state = workspace.states[pane], let frame = frames[pane] {
                        let isShown = tabOfPane[pane] == layout.selectedTab && (zoomed == nil || zoomed == pane)
                        TerminalPane(
                            state: state,
                            search: workspace.searches[pane],
                            isSecured: workspace.isSecured(pane),
                            dimmed: workspace.isSplit && zoomed == nil && pane != workspace.focusedID,
                            onFocus: { workspace.didFocus(pane) },
                            onLeaveSearch: { workspace.focus(pane) },
                            onCloseSearch: { workspace.endSearch(in: pane) }
                        )
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                        .opacity(isShown ? 1 : 0)
                        .allowsHitTesting(isShown)
                        .accessibilityHidden(!isShown)
                    }
                }
                if showsHorizontalTabs {
                    TabBar(
                        workspace: workspace,
                        width: window.width,
                        height: barHeight,
                        leadingInset: titlebar.isFullScreen ? 8 : titlebar.buttonsWidth + 14,
                        showsNumbers: showsNumbers
                    )
                } else if sidebarWidth == nil {
                    WindowDragArea { workspace.window?.zoom(nil) }
                        .frame(width: window.width, height: barHeight)
                }
                // Identifiées par leur place dans l'arbre : stable pendant un glissé.
                ForEach(zoomed == nil ? layout.selectedSplits.tree.dividers(in: bounds) : [], id: \.path) { divider in
                    SplitHandle(divider: divider, onEqualize: workspace.equalizeSplits) { workspace.setRatio($0, at: divider.path) }
                }
                if let drop = workspace.drop {
                    DropHighlight(frame: drop.highlight)
                }
            }
            .animation(Ink.motion(.easeOut(duration: 0.12)), value: workspace.drop)
            .onChange(of: bounds, initial: true) { workspace.bounds = bounds }
        }
    }
}

/// Où ira l'onglet lâché, en couleur d'accent.
private struct DropHighlight: View {
    let frame: CGRect

    @Environment(\.accent) private var accent

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(accent.color.opacity(0.18))
            .strokeBorder(accent.color.opacity(0.6), lineWidth: 2)
            .padding(4)
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Le trait entre deux splits. Il passe à la couleur d'accent au survol : on voit qu'il se glisse.
private struct SplitHandle: View {
    let divider: SplitDivider
    let onEqualize: () -> Void
    let onDrag: (CGFloat) -> Void

    @State private var isActive = false
    @Environment(\.accent) private var accent

    /// Plus large que le trait d'un point, pour l'attraper sans viser.
    private let grip: CGFloat = 6

    var body: some View {
        let line = divider.line
        let isVertical = divider.axis == .horizontal
        let thickness: CGFloat = isActive ? 2 : 1
        ZStack {
            Rectangle()
                .fill(isActive ? accent.color : Color(nsColor: .separatorColor))
                .frame(width: isVertical ? thickness : nil, height: isVertical ? nil : thickness)
        }
        .frame(width: isVertical ? grip : line.width, height: isVertical ? line.height : grip)
        .contentShape(Rectangle())
        .pointerStyle(isVertical ? .columnResize : .rowResize)
        .onHover { hovering in
            withAnimation(Ink.motion(.easeOut(duration: 0.12))) { isActive = hovering }
        }
        .offset(x: isVertical ? line.minX - grip / 2 : line.minX, y: isVertical ? line.minY : line.minY - grip / 2)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(TerminalScreen.space))
                .onChanged { onDrag(divider.ratio(at: $0.location)) }
        )
        // Comme la séparation des éditeurs de VS Code : double-cliquée, les splits reprennent des parts égales.
        .simultaneousGesture(TapGesture(count: 2).onEnded(onEqualize))
    }
}

private struct TerminalPane: View {
    @ObservedObject var state: TerminalViewState
    let search: TerminalSearch?
    let isSecured: Bool
    let dimmed: Bool
    let onFocus: () -> Void
    let onLeaveSearch: () -> Void
    let onCloseSearch: () -> Void

    var body: some View {
        TerminalSurfaceView(context: state)
            // Comme Ghostty : le volet inactif est légèrement assombri.
            .overlay {
                if dimmed {
                    Color.black.opacity(0.3).allowsHitTesting(false)
                }
            }
            .overlay {
                ScrollbarOverlay(
                    position: state.scrollbar.map {
                        ScrollbarPosition(total: Int($0.total), offset: Int($0.offset), visible: Int($0.len))
                    },
                    isDark: state.backgroundColor.isDark,
                    onScroll: { state.attachedPlatformView?.scrollWheel(with: $0) },
                    onScrollToRow: { state.surface?.scrollToRow(UInt($0)) }
                )
            }
            .overlay(alignment: .topTrailing) {
                VStack(alignment: .trailing, spacing: 0) {
                    if let search {
                        TerminalSearchBar(
                            search: search,
                            count: SearchCount(total: state.searchTotal, selected: state.searchSelected),
                            onLeave: onLeaveSearch,
                            onClose: onCloseSearch
                        )
                    }
                    if isSecured {
                        SecureInputLock()
                    }
                }
            }
            .onChange(of: state.isFocused) { _, isFocused in
                if isFocused { onFocus() }
            }
    }
}

/// Titre et couleur de la fenêtre, pris sur le terminal qui a le focus, sauf nom choisi pour l'onglet.
struct TerminalWindowChrome: ViewModifier {
    @ObservedObject var state: TerminalViewState
    let customTitle: String?
    let translucency: Translucency

    func body(content: Content) -> some View {
        content
            .navigationTitle(customTitle ?? state.title)
            // La barre de titre prend la couleur du terminal, comme dans Ghostty. En verre, cette
            // couleur fait le voile de toute la fenêtre, terminaux compris.
            .containerBackground(Color(state.backgroundColor).opacity(translucency.opacity), for: .window)
    }
}

private extension TerminalColor {
    var isDark: Bool {
        0.299 * Double(red) + 0.587 * Double(green) + 0.114 * Double(blue) < 128
    }
}
