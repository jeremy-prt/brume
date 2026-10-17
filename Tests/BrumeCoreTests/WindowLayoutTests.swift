import BrumeCore
import CoreGraphics
import Testing

struct WindowLayoutTests {
    // Onglets A (split 1 | 2, le clavier dans 2) et B (3), A affiché.
    var twoTabs: WindowLayout<String, Int> {
        WindowLayout(tab: "A", pane: 1).splitting(toward: .right, pane: 2).addingTab("B", pane: 3).selecting("A")
    }

    @Test func splittingDividesTheSelectedTabAndFocusesTheNewPane() {
        #expect(twoTabs.tabs == ["A", "B"])
        #expect(twoTabs.panes(of: "A") == [1, 2])
        #expect(twoTabs.focusedPane == 2)
        #expect(twoTabs.isSplit("A"))
        #expect(!twoTabs.isSplit("B"))
    }

    @Test func newTabGoesAfterTheSelectedOne() {
        let layout = twoTabs.addingTab("C", pane: 4)
        #expect(layout.tabs == ["A", "C", "B"])
        #expect(layout.selectedTab == "C")
        #expect(layout.focusedPane == 4)
    }

    @Test func theNewTabButtonAppendsAtTheEnd() {
        let layout = twoTabs.appendingTab("C", pane: 4)
        #expect(layout.tabs == ["A", "B", "C"])
        #expect(layout.focusedPane == 4)
    }

    @Test func panesAreListedTabByTab() {
        #expect(twoTabs.panes == [1, 2, 3])
        #expect(twoTabs.tabOfPane == [1: "A", 2: "A", 3: "B"])
    }

    @Test func numberNineIsAlwaysTheLastTab() {
        let ten = (2 ... 10).reduce(WindowLayout(tab: 1, pane: 1)) { $0.addingTab($1, pane: $1) }
        #expect(ten.shortcutNumbers[9] == nil)
        #expect(ten.shortcutNumbers[10] == 9)
        #expect(ten.selecting(number: 9).selectedTab == 10)
    }

    @Test func focusingAPaneShowsItsTab() {
        let layout = twoTabs.selecting("B").focusing(1)
        #expect(layout.selectedTab == "A")
        #expect(layout.focusedPane == 1)
    }

    @Test func paneFocusCyclesInsideTheSelectedTab() {
        #expect(twoTabs.focusingPane(offset: 1).focusedPane == 1)
        #expect(twoTabs.focusingPane(toward: .left).focusedPane == 1)
        #expect(twoTabs.focusingPane(toward: .down).focusedPane == 2)
    }

    @Test func closingAPaneGivesTheFocusToItsNeighbour() {
        let layout = twoTabs.removing(2)
        #expect(layout?.panes(of: "A") == [1])
        #expect(layout?.focusedPane == 1)
    }

    @Test func closingTheLastPaneOfATabClosesTheTab() {
        let layout = twoTabs.selecting("B").removing(3)
        #expect(layout?.tabs == ["A"])
        #expect(layout?.selectedTab == "A")
    }

    @Test func closingTheLastPaneEmptiesTheWindow() {
        #expect(WindowLayout(tab: "A", pane: 1).removing(1) == nil)
    }

    @Test func movingByAnOffsetReordersTabs() {
        #expect(twoTabs.moving("A", by: 1).tabs == ["B", "A"])
        #expect(twoTabs.moving("A", by: -1).tabs == ["A", "B"])
    }

    @Test func movingBesideATabRespectsBothEdgesInEitherDirection() {
        let original = WindowLayout(tab: "A", pane: 1).appendingTab("B", pane: 2).appendingTab("C", pane: 3)
        for (tab, after, expected) in [
            ("A", false, ["A", "B", "C"]),
            ("A", true, ["B", "A", "C"]),
            ("C", false, ["A", "C", "B"]),
            ("C", true, ["A", "B", "C"]),
        ] {
            let layout = original.moving(tab, beside: "B", after: after)
            #expect(layout.tabs == expected)
            #expect(layout.selectedTab == "C")
            #expect(layout.isConsistent)
        }
        #expect(original.moving("A", beside: "A", after: true) == original)
        #expect(original.moving("A", beside: "missing", after: false) == original)
        #expect(original.moving("missing", beside: "B", after: true) == original)
    }

    @Test func detachingMovesAPaneToItsOwnTab() {
        let layout = twoTabs.detaching(2, into: "C")
        #expect(layout.tabs == ["A", "C", "B"])
        #expect(layout.panes(of: "A") == [1])
        #expect(layout.panes(of: "C") == [2])
        #expect(layout.selectedTab == "C")
        #expect(twoTabs.detaching(3, into: "C") == twoTabs)
    }

    @Test(arguments: [0, 1, 2]) func detachingPlacesTheNewTabAtTheDropPosition(_ index: Int) {
        let layout = twoTabs.detaching(2, into: "C", at: index)
        var expected = ["A", "B"]
        expected.insert("C", at: index)
        #expect(layout.tabs == expected)
        #expect(layout.panes(of: "A") == [1])
        #expect(layout.panes(of: "C") == [2])
        #expect(layout.selectedTab == "C")
        #expect(layout.focusedPane == 2)
        #expect(layout.isConsistent)
    }

    @Test func separatingGivesEachPaneATab() {
        let layout = twoTabs.separating("A", into: ["C"])
        #expect(layout.tabs == ["A", "C", "B"])
        #expect(layout.panes(of: "C") == [2])
        #expect(layout.selectedTab == "A")
        #expect(layout.isConsistent)
    }

    // L'onglet A affiché, ses splits 1 | 2 sur 200 de large.
    let window = CGRect(x: 0, y: 0, width: 200, height: 100)

    @Test func droppingNearAnEdgeProposesThatSide() {
        let drop = twoTabs.drop(of: .tab("B"), at: CGPoint(x: 195, y: 50), in: window)
        #expect(drop?.target == 2)
        #expect(drop?.direction == .right)
        #expect(drop?.highlight == CGRect(x: 150, y: 0, width: 50, height: 100))
    }

    @Test func theSelectedTabCannotDropOnItself() {
        #expect(twoTabs.drop(of: .tab("A"), at: CGPoint(x: 50, y: 50), in: window) == nil)
    }

    @Test func aDroppedTabJoinsTheSelectedOne() {
        let drop = twoTabs.drop(of: .tab("B"), at: CGPoint(x: 150, y: 95), in: window)!
        let layout = twoTabs.dropping(drop)
        #expect(layout.tabs == ["A"])
        #expect(layout.panes(of: "A") == [1, 2, 3])
        #expect(layout.focusedPane == 3)
        #expect(layout.isConsistent)
    }

    @Test func aTabDroppedOnAPaneNoLongerShownStaysATab() {
        let threeTabs = twoTabs.addingTab("C", pane: 4).selecting("A")
        let drop = threeTabs.drop(of: .tab("B"), at: CGPoint(x: 195, y: 50), in: window)!
        // Pendant le glisser, Cmd+chiffre affiche un autre onglet, ou le split visé se ferme.
        for layout in [threeTabs.selecting("C"), threeTabs.removing(2)!] {
            #expect(layout.dropping(drop) == layout)
        }
    }

    @Test func aPaneClosedDuringTheDragIsNotDropped() {
        let drop = twoTabs.drop(of: .pane(3), at: CGPoint(x: 195, y: 50), in: window)!
        let layout = twoTabs.addingTab("C", pane: 4).removingTab("B")!.selecting("A")
        #expect(layout.dropping(drop) == layout)
    }

    @Test func aDroppedPaneMovesBesideTheTarget() {
        // 2 lâché au bas de 1 : ils passent l'un sous l'autre.
        let drop = twoTabs.drop(of: .pane(2), at: CGPoint(x: 50, y: 95), in: window)!
        #expect(drop.target == 1)
        #expect(drop.direction == .down)
        let layout = twoTabs.dropping(drop)
        #expect(layout.selectedSplits.tree == .split(.vertical, ratio: 0.5, .pane(1), .pane(2)))
        #expect(layout.focusedPane == 2)
    }

    @Test func aPaneDroppedWhereItAlreadyIsProposesNothing() {
        // 1 | 2 : sans 2, 1 prend toute la place ; posé à sa droite, 2 retrouve la sienne.
        #expect(twoTabs.drop(of: .pane(2), at: CGPoint(x: 150, y: 50), in: window) == nil)
    }

    @Test func thePreviewShowsWhereThePaneWillReallyGo() {
        // Sans 2, 1 prend toute la place : à sa gauche, 2 en prend la moitié, pas le quart.
        let drop = twoTabs.drop(of: .pane(2), at: CGPoint(x: 70, y: 50), in: window)
        #expect(drop?.direction == .left)
        #expect(drop?.highlight == CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    @Test func aPaneFromAnotherTabJoinsTheSelectedOne() {
        let drop = twoTabs.drop(of: .pane(3), at: CGPoint(x: 195, y: 50), in: window)!
        let layout = twoTabs.dropping(drop)
        #expect(layout.tabs == ["A"])
        #expect(layout.panes(of: "A") == [1, 2, 3])
    }

    @Test func mergingTwoSingleTabsCreatesAGroup() {
        let original = WindowLayout(tab: "A", pane: 1).addingTab("B", pane: 2)
        let layout = original.merging("B", into: "A")
        #expect(layout.tabs == ["A"])
        #expect(layout.selectedTab == "A")
        #expect(layout.isSplit("A"))
        #expect(layout.selectedSplits.tree == .split(.horizontal, ratio: 0.5, .pane(1), .pane(2)))
        #expect(layout.focusedPane == 2)
        #expect(layout.isConsistent)
    }

    @Test func mergingIntoAnUnselectedGroupPreservesItsPanesAndMovesFocus() {
        let layout = twoTabs.selecting("B").merging("B", into: "A")
        #expect(layout.tabs == ["A"])
        #expect(layout.selectedTab == "A")
        #expect(layout.selectedSplits.tree == .split(.horizontal, ratio: 0.5, .pane(1),
            .split(.horizontal, ratio: 0.5, .pane(2), .pane(3))))
        #expect(layout.focusedPane == 3)
        #expect(layout.isConsistent)
    }

    @Test func mergingAnEntireGroupPreservesItsSplitTree() {
        let original = twoTabs.selecting("B").splitting(toward: .down, pane: 4).addingTab("C", pane: 5)
        let layout = original.merging("B", into: "A")
        #expect(layout.tabs == ["A", "C"])
        #expect(layout.panes(of: "A") == [1, 2, 3, 4])
        #expect(layout.panes(of: "C") == [5])
        #expect(layout.focusedPane == 4)
        #expect(layout.selectedSplits.tree == .split(.horizontal, ratio: 0.5, .pane(1),
            .split(.horizontal, ratio: 0.5, .pane(2), original.splits["B"]!.tree)))
        #expect(layout.isConsistent)
    }

    @Test func mergingMissingTabsOrTheSameTabDoesNothing() {
        #expect(twoTabs.merging("B", into: "B") == twoTabs)
        #expect(twoTabs.merging("missing", into: "A") == twoTabs)
        #expect(twoTabs.merging("B", into: "missing") == twoTabs)
    }

    @Test func swappingReordersAGroup() {
        #expect(twoTabs.swapping(1, 2).panes(of: "A") == [2, 1])
        #expect(twoTabs.swapping(1, 3) == twoTabs)
    }

    @Test func tabsBesidesAndAfter() {
        let layout = twoTabs.addingTab("C", pane: 4)
        #expect(layout.tabs(besides: "C") == ["A", "B"])
        #expect(layout.tabs(after: "A") == ["C", "B"])
        #expect(layout.tabs(after: "B").isEmpty)
    }

    @Test func ratiosApplyToTheSelectedTab() {
        let layout = twoTabs.settingRatio(0.3, at: [])
        #expect(layout.selectedSplits.tree == .split(.horizontal, ratio: 0.3, .pane(1), .pane(2)))
        #expect(layout.equalized().selectedSplits.tree == twoTabs.selectedSplits.tree)
    }
}
