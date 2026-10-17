import BrumeCore
import SwiftUI

/// Les onglets verticaux : ceux de la fenêtre listés à gauche, sur le modèle de la barre latérale
/// des réglages. Un onglet divisé y est un groupe qui se déplie sur ses splits. Les boutons rouge,
/// jaune, vert en occupent le haut.
struct TabSidebar: View {
    let workspace: TerminalWorkspace
    let width: CGFloat
    /// La hauteur de la barre de titre, où se tiennent les boutons de la fenêtre.
    let topInset: CGFloat
    let showsNumbers: Bool
    let onResize: (CGFloat) -> Void
    let onResizeEnd: () -> Void

    @State private var isDragging = false
    /// La place de chaque onglet, groupe déplié compris, dans l'espace de `TerminalScreen`.
    @State private var frames: [UUID: CGRect] = [:]
    @State private var paneFrames: [UUID: CGRect] = [:]
    @State private var swapTarget: UUID?
    @State private var detachIndex: Int?
    @State private var viewport: CGRect = .zero
    @State private var mergeTarget: UUID?
    @State private var reorderTarget: UUID?
    @State private var reordersAfterTarget = false
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        let layout = workspace.layout
        let numbers = showsNumbers ? layout.shortcutNumbers : [:]
        GeometryReader { geometry in
            ScrollViewReader { scroller in
                ScrollView(.vertical) {
                    VStack(spacing: 2) {
                        ForEach(layout.tabs, id: \.self) { tab in
                            VStack(spacing: 2) {
                                TabSidebarRow(tab: tab, workspace: workspace, isDragging: isDragging, number: numbers[tab])
                                    .opacity(workspace.drop?.dragged == .tab(tab) ? 0.5 : 1)
                                    .gesture(drag(tab), including: workspace.renaming == .tab(tab) ? .subviews : .all)
                                if layout.isSplit(tab) && !workspace.collapsed.contains(tab) {
                                    ForEach(layout.panes(of: tab), id: \.self) { pane in
                                        TabSidebarPane(pane: pane, tab: tab, workspace: workspace, isDragging: isDragging)
                                            .opacity(workspace.drop?.dragged == .pane(pane) ? 0.5 : 1)
                                            .gesture(drag(pane, in: tab), including: workspace.renaming == .pane(pane) ? .subviews : .all)
                                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(TerminalScreen.space)) } action: {
                                                paneFrames[pane] = $0
                                            }
                                            .overlay {
                                                if swapTarget == pane {
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .strokeBorder(Ink.muted, lineWidth: 1)
                                                        .allowsHitTesting(false)
                                                }
                                            }
                                            .transition(.accordion(.vertical))
                                    }
                                }
                            }
                            .overlay {
                                if mergeTarget == tab {
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(Ink.muted, lineWidth: 1)
                                        .allowsHitTesting(false)
                                }
                            }
                            .overlay(alignment: reordersAfterTarget ? .bottom : .top) {
                                if reorderTarget == tab {
                                    Rectangle()
                                        .fill(Ink.muted)
                                        .frame(height: 2)
                                        .allowsHitTesting(false)
                                }
                            }
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(TerminalScreen.space)) } action: {
                                frames[tab] = $0
                            }
                            .transition(.accordion(.vertical))
                        }
                        NewTabRow(shortcut: settings.shortcutLabel(.newTab)) { workspace.newTab(atEnd: true) }
                            .overlay(alignment: .top) {
                                if detachIndex == layout.tabs.count && reorderTarget == nil {
                                    Rectangle().fill(Ink.muted).frame(height: 2).allowsHitTesting(false)
                                }
                            }
                    }
                    // Un onglet ou un split s'ouvre en accordéon, ses voisins et « Nouvel onglet »
                    // glissent avec lui.
                    .animation(Ink.slide, value: layout.panes)
                    .animation(Ink.slide, value: layout.tabs)
                    .animation(Ink.slide, value: workspace.collapsed)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    // Le vide sous la liste déplace la fenêtre ; double-cliqué, il ouvre un onglet,
                    // comme sous les onglets de Safari.
                    .frame(minHeight: geometry.size.height, alignment: .top)
                    .background { WindowDragArea { workspace.newTab(atEnd: true) } }
                }
                .scrollIndicators(.never)
                .onChange(of: layout.selectedTab) { _, tab in
                    withAnimation(Ink.slide) { scroller.scrollTo(tab) }
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(TerminalScreen.space)) } action: {
                viewport = $0
            }
        }
        .padding(.top, topInset + 8)
        .frame(width: width)
        .background(Color.black.opacity(0.12))
        .background { WindowDragArea() }
        .overlay(alignment: .top) {
            WindowDragArea { workspace.window?.zoom(nil) }
                .frame(height: topInset)
        }
        .overlay(alignment: .trailing) {
            TabSidebarEdge(width: width, onResize: onResize, onResizeEnd: onResizeEnd)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text(.tabs))
    }

    /// Le centre d'un onglet le rejoint ; ses bords réordonnent la liste. Sur les terminaux,
    /// l'onglet rejoint celui affiché, comme depuis la barre du haut.
    private func drag(_ tab: UUID) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(TerminalScreen.space))
            .onChanged { value in
                isDragging = true
                updateTabDrag(tab, at: value.location)
            }
            .onEnded { value in
                updateTabDrag(tab, at: value.location)
                isDragging = false
                if let target = mergeTarget {
                    workspace.merge(tab, into: target)
                } else if let target = reorderTarget {
                    workspace.move(tab, beside: target, after: reordersAfterTarget)
                } else {
                    workspace.performDrop()
                }
                mergeTarget = nil
                reorderTarget = nil
            }
    }

    private func updateTabDrag(_ tab: UUID, at point: CGPoint) {
        mergeTarget = nil
        reorderTarget = nil
        guard point.x < width else {
            return workspace.hoverDrop(dragging: .tab(tab), at: point)
        }
        workspace.hoverDrop(dragging: .tab(tab), at: nil)
        guard viewport.contains(point) else { return }
        let tabs = workspace.layout.tabs
        let hovered = tabs.first { frames[$0].map { ($0.minY ... $0.maxY).contains(point.y) } ?? false }
        guard let target = hovered, target != tab, tabs.contains(tab), let frame = frames[target] else { return }
        if (frame.minY + 8 ... frame.maxY - 8).contains(point.y) {
            mergeTarget = target
        } else {
            reorderTarget = target
            reordersAfterTarget = point.y >= frame.midY
        }
    }

    private func drag(_ pane: UUID, in tab: UUID) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(TerminalScreen.space))
            .onChanged { value in
                isDragging = true
                updatePaneDrag(pane, in: tab, at: value.location)
            }
            .onEnded { value in
                updatePaneDrag(pane, in: tab, at: value.location)
                isDragging = false
                if let index = detachIndex {
                    workspace.detach(pane, at: index)
                } else if let target = swapTarget {
                    workspace.swap(pane, target)
                } else {
                    workspace.performDrop()
                }
                detachIndex = nil
                swapTarget = nil
                reorderTarget = nil
            }
    }

    private func updatePaneDrag(_ pane: UUID, in tab: UUID, at point: CGPoint) {
        detachIndex = nil
        swapTarget = nil
        reorderTarget = nil
        guard point.x < width else {
            return workspace.hoverDrop(dragging: .pane(pane), at: point)
        }
        workspace.hoverDrop(dragging: .pane(pane), at: nil)
        guard viewport.contains(point), workspace.layout.isSplit(tab) else { return }
        let tabs = workspace.layout.tabs
        if let target = tabs.first(where: { frames[$0]?.contains(point) == true }), let frame = frames[target],
           let index = tabs.firstIndex(of: target) {
            if target == tab && (frame.minY + 8 ... frame.maxY - 8).contains(point.y) {
                swapTarget = workspace.layout.panes(of: tab).first {
                    $0 != pane && paneFrames[$0]?.contains(point) == true
                }
            } else {
                reordersAfterTarget = point.y >= frame.midY
                reorderTarget = target
                detachIndex = index + (reordersAfterTarget ? 1 : 0)
            }
        } else {
            let index = tabs.firstIndex { (frames[$0]?.minY ?? .infinity) > point.y } ?? tabs.count
            detachIndex = index
            if index < tabs.count {
                reorderTarget = tabs[index]
                reordersAfterTarget = false
            }
        }
    }
}

/// Au bout de la liste, comme le + au bout de la barre du haut.
private struct NewTabRow: View {
    let shortcut: String?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                SystemSymbol.image("plus", size: 12)
                    .frame(width: 16, height: 16)
                Text(L10n.text(.newTab))
                    .font(.system(size: 13))
                Spacer(minLength: 0)
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.meta)
                        .opacity(isHovered ? 1 : 0)
                }
            }
            .foregroundStyle(isHovered ? Ink.text : Ink.muted)
            .padding(.horizontal, 8)
            .frame(height: TabSidebarRow.height)
            .background(isHovered ? Ink.hover : .clear, in: .rect(cornerRadius: 6))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(Ink.feedback, value: isHovered)
    }
}
