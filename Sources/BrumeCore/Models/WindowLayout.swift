import CoreGraphics

/// Une fenêtre comme Ghostty, Arc ou Dia : des onglets, chacun divisé en splits, un terminal par
/// split. Un onglet divisé s'affiche en groupe dans la barre latérale.
public struct WindowLayout<Tab: Hashable & Sendable, Pane: Hashable & Sendable>: Hashable, Sendable {
    /// Ce qu'on glisse : un onglet, ou un split d'un groupe.
    public enum Dragged: Hashable, Sendable {
        case tab(Tab)
        case pane(Pane)
    }

    /// Glissé sur les splits de l'onglet affiché, et où il ira si on le lâche.
    public struct Drop: Hashable, Sendable {
        public let dragged: Dragged
        public let target: Pane
        public let direction: SplitDirection
        /// Ce que prendra l'onglet, à montrer pendant le glisser.
        public let highlight: CGRect
    }

    public private(set) var tabList: TabList<Tab>
    public private(set) var splits: [Tab: Splits<Pane>]

    public init(tab: Tab, pane: Pane) {
        tabList = TabList(tab)
        splits = [tab: Splits(pane)]
    }

    public var tabs: [Tab] {
        tabList.tabs
    }

    public var selectedTab: Tab {
        tabList.selected
    }

    public var selectedSplits: Splits<Pane> {
        splits[selectedTab]!
    }

    public var focusedPane: Pane {
        selectedSplits.focused
    }

    /// Tous les terminaux, onglet par onglet.
    public var panes: [Pane] {
        tabs.flatMap(panes(of:))
    }

    public func panes(of tab: Tab) -> [Pane] {
        splits[tab]?.tree.panes ?? []
    }

    public func isSplit(_ tab: Tab) -> Bool {
        panes(of: tab).count > 1
    }

    /// L'onglet de chaque terminal, d'un seul passage : à prendre pour les afficher tous.
    public var tabOfPane: [Pane: Tab] {
        splits.reduce(into: [:]) { result, entry in
            for pane in entry.value.tree.panes { result[pane] = entry.key }
        }
    }

    public func tab(of pane: Pane) -> Tab? {
        splits.first { $0.value.tree.panes.contains(pane) }?.key
    }

    /// Une disposition relue d'un fichier peut être abîmée : un onglet sans splits, un terminal
    /// dans deux onglets. Restaurée telle quelle, elle planterait Brume.
    public var isConsistent: Bool {
        let all = panes
        return splits[selectedTab] != nil && Set(tabs) == Set(splits.keys) && tabs.count == splits.count && Set(all).count == all.count
            && splits.values.allSatisfy { $0.tree.panes.contains($0.focused) }
    }

    /// Le chiffre du raccourci de chaque onglet : Cmd+1 à Cmd+8 dans l'ordre, Cmd+9 le dernier.
    public var shortcutNumbers: [Tab: Int] {
        var numbers: [Tab: Int] = [:]
        for (index, tab) in tabs.prefix(8).enumerated() { numbers[tab] = index + 1 }
        if tabs.count > 8, let last = tabs.last { numbers[last] = 9 }
        return numbers
    }

    /// Juste après l'onglet affiché, comme Ghostty, et l'affiche.
    public func addingTab(_ tab: Tab, pane: Pane) -> WindowLayout {
        var layout = self
        layout.tabList = tabList.inserting(tab)
        layout.splits[tab] = Splits(pane)
        return layout
    }

    /// En bout de liste, où se trouve le bouton + qui l'ouvre, et l'affiche.
    public func appendingTab(_ tab: Tab, pane: Pane) -> WindowLayout {
        var layout = self
        layout.tabList = tabList.appending(tab)
        layout.splits[tab] = Splits(pane)
        return layout
    }

    public func selecting(_ tab: Tab) -> WindowLayout {
        var layout = self
        layout.tabList = tabList.selecting(tab)
        return layout
    }

    /// Cmd+1 à Cmd+8, Cmd+9 le dernier.
    public func selecting(number: Int) -> WindowLayout {
        let index = number == 9 ? tabs.count - 1 : number - 1
        guard tabs.indices.contains(index) else { return self }
        return selecting(tabs[index])
    }

    /// Fait le tour : après le dernier vient le premier.
    public func selecting(offset: Int) -> WindowLayout {
        var layout = self
        layout.tabList = tabList.selecting(offset: offset)
        return layout
    }

    /// Affiche son onglet et lui donne le clavier.
    public func focusing(_ pane: Pane) -> WindowLayout {
        guard let tab = tab(of: pane), let tabSplits = splits[tab] else { return self }
        var layout = selecting(tab)
        layout.splits[tab] = tabSplits.focusing(pane)
        return layout
    }

    /// Le split suivant ou précédent de l'onglet affiché, en faisant le tour.
    public func focusingPane(offset: Int) -> WindowLayout {
        let tree = selectedSplits.tree
        guard let pane = offset > 0 ? tree.pane(after: focusedPane) : tree.pane(before: focusedPane) else { return self }
        return focusing(pane)
    }

    public func focusingPane(toward direction: SplitDirection) -> WindowLayout {
        guard let pane = selectedSplits.tree.neighbor(of: focusedPane, toward: direction) else { return self }
        return focusing(pane)
    }

    /// Un split neuf à côté de celui qui a le clavier, dans l'onglet affiché, et le clavier.
    public func splitting(toward direction: SplitDirection, pane: Pane) -> WindowLayout {
        var layout = self
        layout.splits[selectedTab] = selectedSplits.inserting(.pane(pane), beside: focusedPane, toward: direction, focusing: pane)
        return layout
    }

    /// Un onglet vidé disparaît. Nil quand plus rien ne reste.
    public func removing(_ pane: Pane) -> WindowLayout? {
        guard let tab = tab(of: pane), let tabSplits = splits[tab] else { return self }
        guard let remaining = tabSplits.removing(pane) else { return removingTab(tab) }
        var layout = self
        layout.splits[tab] = remaining
        return layout
    }

    /// Fermer l'onglet affiché montre son voisin. Nil quand c'était le dernier.
    public func removingTab(_ tab: Tab) -> WindowLayout? {
        guard splits[tab] != nil else { return self }
        guard let list = tabList.removing(tab) else { return nil }
        var layout = self
        layout.tabList = list
        layout.splits[tab] = nil
        return layout
    }

    public func moving(_ tab: Tab, to index: Int) -> WindowLayout {
        var layout = self
        layout.tabList = tabList.moving(tab, to: index)
        return layout
    }

    public func moving(_ tab: Tab, beside target: Tab, after: Bool) -> WindowLayout {
        guard tab != target, let sourceIndex = tabs.firstIndex(of: tab),
              let targetIndex = tabs.firstIndex(of: target) else { return self }
        let index = targetIndex + (after ? 1 : 0) - (sourceIndex < targetIndex ? 1 : 0)
        return moving(tab, to: index)
    }

    /// D'une place, au clavier.
    public func moving(_ tab: Tab, by offset: Int) -> WindowLayout {
        guard let index = tabs.firstIndex(of: tab) else { return self }
        return moving(tab, to: index + offset)
    }

    /// Sans position choisie, le split part juste après son onglet d'origine, affiché.
    public func detaching(_ pane: Pane, into newTab: Tab, at index: Int? = nil) -> WindowLayout {
        guard let tab = tab(of: pane), let remaining = splits[tab]?.removing(pane) else { return self }
        var layout = self
        layout.splits[tab] = remaining
        layout.tabList = tabList.selecting(tab).inserting(newTab)
        layout.splits[newTab] = Splits(pane)
        return index.map { layout.moving(newTab, to: $0) } ?? layout
    }

    /// Chaque split devient un onglet, à la suite : le premier garde l'onglet, `newTabs` donne
    /// les autres.
    public func separating(_ tab: Tab, into newTabs: [Tab]) -> WindowLayout {
        let panes = panes(of: tab)
        guard panes.count > 1, newTabs.count >= panes.count - 1 else { return self }
        var layout = self
        var list = tabList.selecting(tab)
        layout.splits[tab] = Splits(panes[0])
        for (pane, newTab) in zip(panes.dropFirst(), newTabs) {
            list = list.inserting(newTab)
            layout.splits[newTab] = Splits(pane)
        }
        layout.tabList = list.selecting(tab)
        return layout
    }

    /// Où irait ce qu'on glisse, lâché en `point`, les splits de l'onglet affiché occupant
    /// `bounds` : de ce côté du split survolé. Nil : rien à proposer, comme l'onglet affiché ou un
    /// split sur lui-même.
    public func drop(of dragged: Dragged, at point: CGPoint, in bounds: CGRect) -> Drop? {
        switch dragged {
        case let .tab(tab):
            guard tab != selectedTab, splits[tab] != nil else { return nil }
            return drop(dragged, at: point, over: selectedSplits.tree, in: bounds)
        case let .pane(moved):
            // Le split quitte d'abord sa place, et ses voisins la reprennent : le repère montre où
            // il arrivera vraiment. Lâché là d'où il vient, il ne change rien : pas de repère.
            guard let remaining = removing(moved)?.splits[selectedTab],
                  let drop = drop(dragged, at: point, over: remaining.tree, in: bounds),
                  !(dropping(drop).splits[selectedTab]?.tree.hasSameShape(as: selectedSplits.tree) ?? false) else { return nil }
            return drop
        }
    }

    private func drop(_ dragged: Dragged, at point: CGPoint, over tree: SplitTree<Pane>, in bounds: CGRect) -> Drop? {
        guard let (pane, frame) = tree.frames(in: bounds).first(where: { $0.value.contains(point) }) else { return nil }
        let direction = SplitDirection.nearestEdge(to: point, in: frame)
        return Drop(dragged: dragged, target: pane, direction: direction, highlight: direction.half(of: frame))
    }

    /// Lâché à côté du split visé, dans l'onglet affiché : un onglet y apporte tous ses splits,
    /// un split quitte sa place pour celle-ci. Rien ne bouge si ce qu'on glisse, ou le split visé,
    /// a disparu ou changé d'onglet pendant le glisser.
    public func dropping(_ drop: Drop) -> WindowLayout {
        switch drop.dragged {
        case let .tab(tab):
            guard tab != selectedTab, let moved = splits[tab], var layout = removingTab(tab),
                  let target = layout.splits[selectedTab], target.tree.panes.contains(drop.target) else { return self }
            layout.splits[selectedTab] = target.inserting(moved.tree, beside: drop.target, toward: drop.direction, focusing: moved.focused)
            return layout
        case let .pane(pane):
            guard pane != drop.target, tab(of: pane) != nil, var layout = removing(pane),
                  let target = layout.splits[layout.selectedTab], target.tree.panes.contains(drop.target) else { return self }
            layout.splits[layout.selectedTab] = target.inserting(.pane(pane), beside: drop.target, toward: drop.direction, focusing: pane)
            return layout
        }
    }

    public func merging(_ tab: Tab, into target: Tab) -> WindowLayout {
        guard tab != target, splits[tab] != nil, let destination = splits[target] else { return self }
        let drop = Drop(dragged: .tab(tab), target: destination.focused, direction: .right, highlight: .zero)
        return selecting(target).dropping(drop)
    }

    /// Deux splits d'un même onglet échangent leur place : réordonner un groupe.
    public func swapping(_ a: Pane, _ b: Pane) -> WindowLayout {
        guard a != b, let tab = tab(of: a), tab == self.tab(of: b), let tabSplits = splits[tab] else { return self }
        var layout = self
        layout.splits[tab] = tabSplits.swapping(a, b)
        return layout
    }

    /// Les autres onglets, pour « Fermer les autres onglets ».
    public func tabs(besides tab: Tab) -> [Tab] {
        tabs.filter { $0 != tab }
    }

    /// Ceux qui le suivent, pour « Fermer les onglets à droite » (ou en dessous).
    public func tabs(after tab: Tab) -> [Tab] {
        guard let index = tabs.firstIndex(of: tab) else { return [] }
        return Array(tabs[(index + 1)...])
    }

    public func settingRatio(_ ratio: CGFloat, at path: [Int]) -> WindowLayout {
        var layout = self
        layout.splits[selectedTab] = selectedSplits.settingRatio(ratio, at: path)
        return layout
    }

    public func equalized() -> WindowLayout {
        var layout = self
        layout.splits[selectedTab] = selectedSplits.equalized()
        return layout
    }
}

extension WindowLayout: Codable where Tab: Codable, Pane: Codable {}

/// Les splits d'un onglet, et celui qui a le clavier.
public struct Splits<Pane: Hashable & Sendable>: Hashable, Sendable {
    public private(set) var tree: SplitTree<Pane>
    public private(set) var focused: Pane

    public init(_ pane: Pane) {
        tree = .pane(pane)
        focused = pane
    }

    func focusing(_ pane: Pane) -> Splits {
        guard tree.panes.contains(pane) else { return self }
        var splits = self
        splits.focused = pane
        return splits
    }

    func inserting(_ subtree: SplitTree<Pane>, beside target: Pane, toward direction: SplitDirection, focusing pane: Pane) -> Splits {
        var splits = self
        splits.tree = tree.inserting(subtree, beside: target, toward: direction)
        splits.focused = pane
        return splits
    }

    /// Le voisin prend la place, et le clavier s'il l'avait. Nil quand c'était le dernier.
    func removing(_ pane: Pane) -> Splits? {
        let order = tree.panes
        guard let remaining = tree.removing(pane) else { return nil }
        var splits = self
        splits.tree = remaining
        if focused == pane, let index = order.firstIndex(of: pane) {
            splits.focused = remaining.panes[max(index - 1, 0)]
        }
        return splits
    }

    func swapping(_ a: Pane, _ b: Pane) -> Splits {
        var splits = self
        splits.tree = tree.swapping(a, b)
        return splits
    }

    func settingRatio(_ ratio: CGFloat, at path: [Int]) -> Splits {
        var splits = self
        splits.tree = tree.settingRatio(ratio, at: path)
        return splits
    }

    func equalized() -> Splits {
        var splits = self
        splits.tree = tree.equalized()
        return splits
    }
}

extension Splits: Codable where Pane: Codable {}
