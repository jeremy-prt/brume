import Foundation

public enum ShortcutCategory: CaseIterable, Sendable {
    case tabs, splits

    public var title: TextKey {
        switch self {
        case .tabs: .tabs
        case .splits: .splits
        }
    }

    public var actions: [ShortcutAction] {
        ShortcutAction.allCases.filter { $0.category == self }
    }
}

/// Les raccourcis propres à Brume, ceux qu'on peut changer dans les réglages. Ceux de macOS
/// (⌘Q, ⌘N, ⌘,) restent fixes. Le nom de chaque cas est sa clé dans le fichier des réglages :
/// ne pas le renommer.
public enum ShortcutAction: String, CaseIterable, Sendable {
    case newTab, renameTab, closeTerminal, closeTab, previousTab, nextTab, selectTab, verticalTabs, toggleSidebar, resetWindow
    case splitRight, splitDown, zoomSplit, focusPreviousSplit, focusNextSplit, equalizeSplits

    public var category: ShortcutCategory {
        switch self {
        case .newTab, .renameTab, .closeTerminal, .closeTab, .previousTab, .nextTab, .selectTab, .verticalTabs, .toggleSidebar, .resetWindow: .tabs
        case .splitRight, .splitDown, .zoomSplit, .focusPreviousSplit, .focusNextSplit, .equalizeSplits: .splits
        }
    }

    public var title: TextKey {
        switch self {
        case .newTab: .newTab
        case .renameTab: .renameTab
        case .closeTab: .closeTab
        case .previousTab: .previousTab
        case .nextTab: .nextTab
        case .selectTab: .selectTab
        case .splitRight: .splitRight
        case .splitDown: .splitDown
        case .closeTerminal: .closeTerminal
        case .zoomSplit: .zoomSplit
        case .focusPreviousSplit: .focusPreviousSplit
        case .focusNextSplit: .focusNextSplit
        case .equalizeSplits: .equalizeSplits
        case .verticalTabs: .verticalTabs
        case .toggleSidebar: .toggleSidebar
        case .resetWindow: .resetWindow
        }
    }

    public var hint: TextKey? {
        switch self {
        case .selectTab: .selectTabHint
        case .closeTerminal: .closeTerminalHint
        default: nil
        }
    }

    /// Ceux de Ghostty, ⌃⌘S pour l'orientation et ⌘B pour la barre latérale.
    /// Pour `selectTab`, seules les touches de modification comptent : elles vont avec 1 à 9.
    public var defaultShortcut: Shortcut {
        switch self {
        case .newTab: Shortcut("t")
        case .renameTab: Shortcut("r", [.command, .shift])
        case .closeTab: Shortcut("w", [.command, .option])
        case .previousTab: Shortcut("[", [.command, .shift])
        case .nextTab: Shortcut("]", [.command, .shift])
        case .selectTab: Shortcut("1")
        case .splitRight: Shortcut("d")
        case .splitDown: Shortcut("d", [.command, .shift])
        case .closeTerminal: Shortcut("w")
        case .zoomSplit: Shortcut("return", [.command, .shift])
        case .focusPreviousSplit: Shortcut("[")
        case .focusNextSplit: Shortcut("]")
        case .equalizeSplits: Shortcut("=", [.command, .control])
        case .verticalTabs: Shortcut("s", [.command, .control])
        case .toggleSidebar: Shortcut("b")
        case .resetWindow: Shortcut("r", [.command, .option])
        }
    }
}

/// Une combinaison prise ailleurs : un raccourci de Brume qui ne se change pas, un de macOS, ou une
/// touche du terminal.
public struct ReservedShortcut: Sendable {
    public enum Owner: Sendable {
        /// Brume ou macOS : la combinaison est refusée.
        case app
        /// Le terminal : on prévient, et on peut passer outre.
        case terminal
    }

    public let shortcut: Shortcut
    public let title: TextKey
    public let owner: Owner

    init(_ shortcut: Shortcut, _ title: TextKey, _ owner: Owner = .app) {
        self.shortcut = shortcut
        self.title = title
        self.owner = owner
    }

    public static let all: [ReservedShortcut] = [
        // Les autres raccourcis de Brume : ceux des menus, et ⌃Tab (`BrumeTerminalView`).
        .init(Shortcut("n"), .newWindow),
        .init(Shortcut("w", [.command, .shift]), .closeWindow),
        .init(Shortcut(","), .settings),
        .init(Shortcut("tab", .control), .nextTab),
        .init(Shortcut("tab", [.control, .shift]), .previousTab),
        .init(Shortcut("left", [.command, .option]), .focusSplitLeft),
        .init(Shortcut("right", [.command, .option]), .focusSplitRight),
        .init(Shortcut("up", [.command, .option]), .focusSplitUp),
        .init(Shortcut("down", [.command, .option]), .focusSplitDown),
        .init(Shortcut("left", [.command, .control]), .moveTabLeft),
        .init(Shortcut("right", [.command, .control]), .moveTabRight),
        .init(Shortcut("up", [.command, .control]), .moveTabUp),
        .init(Shortcut("down", [.command, .control]), .moveTabDown),
        .init(Shortcut("f"), .find),
        .init(Shortcut("g"), .findNext),
        .init(Shortcut("g", [.command, .shift]), .findPrevious),
        .init(Shortcut("e"), .findSelection),
        .init(Shortcut("+"), .increaseFontSize),
        .init(Shortcut("-"), .decreaseFontSize),
        .init(Shortcut("0"), .resetFontSize),
        .init(Shortcut("0", [.command, .control]), .resetAllSizes),
        .init(Shortcut("k"), .clearScreen),
        // Ceux de macOS, dans toutes les apps.
        .init(Shortcut("q"), .quit),
        .init(Shortcut("h"), .hideApp),
        .init(Shortcut("h", [.command, .option]), .hideOthers),
        .init(Shortcut("m"), .minimize),
        .init(Shortcut("z"), .undo),
        .init(Shortcut("z", [.command, .shift]), .redo),
        .init(Shortcut("x"), .cut),
        .init(Shortcut("c"), .copy),
        .init(Shortcut("v"), .paste),
        .init(Shortcut("a"), .selectAll),
        .init(Shortcut("f", [.command, .control]), .fullScreen),
        // Ceux du moteur, dans le terminal.
        .init(Shortcut("left"), .lineStart, .terminal),
        .init(Shortcut("right"), .lineEnd, .terminal),
        .init(Shortcut("delete"), .deleteLine, .terminal),
    ]
}
