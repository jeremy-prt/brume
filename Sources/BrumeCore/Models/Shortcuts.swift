import Foundation

/// Ce qui empêche ou fait hésiter à donner une combinaison à une action.
public enum ShortcutIssue: Equatable, Sendable {
    case needsModifier
    /// Aller à un onglet : un chiffre, dont seules les touches de modification sont gardées.
    case needsDigit
    /// Prise par un raccourci de Brume qui ne se change pas, ou par macOS : refusée.
    case reserved(TextKey)
    /// Prise par un autre raccourci qu'on peut changer : on peut la lui reprendre.
    case taken(ShortcutAction)
    /// Une touche du terminal, nommée, ou toute combinaison sans ⌘ (⌃R, ⌥B…) : on peut passer outre.
    case terminal(TextKey?)

    public var isBlocking: Bool {
        switch self {
        case .needsModifier, .needsDigit, .reserved: true
        case .taken, .terminal: false
        }
    }
}

/// Les raccourcis changés dans les réglages. Les autres gardent leur valeur par défaut.
///
/// Les comparaisons passent par `normalize`, que l'app tire du clavier du Mac : sur un clavier
/// français, ⇧⌘[ s'écrit ⇧⌘^, et ⇧⌘= revient à ⌘+.
public struct Shortcuts: Hashable, Sendable {
    public typealias Normalize = (Shortcut) -> Shortcut

    /// Nil : le raccourci retiré, l'action n'en a plus.
    private var overrides: [ShortcutAction: Shortcut?] = [:]

    public init() {}

    public subscript(action: ShortcutAction) -> Shortcut? {
        if let override = overrides[action] { return override }
        // ⌘B pouvait déjà être personnalisé avant l'ajout de cette action.
        if action == .toggleSidebar, overrides.contains(where: { other, shortcut in
            guard let shortcut else { return false }
            return Self.combinations(of: shortcut, for: other).contains(action.defaultShortcut)
        }) {
            return nil
        }
        return action.defaultShortcut
    }

    public func isCustom(_ action: ShortcutAction) -> Bool {
        overrides[action] != nil
    }

    public var hasCustom: Bool {
        !overrides.isEmpty
    }

    /// La valeur par défaut retapée redevient la valeur par défaut, et suivra ses changements.
    public mutating func set(_ shortcut: Shortcut?, for action: ShortcutAction, normalize: Normalize = { $0 }) {
        if let shortcut, normalize(shortcut) == normalize(action.defaultShortcut) {
            overrides.removeValue(forKey: action)
        } else {
            overrides[action] = .some(shortcut)
        }
    }

    public mutating func reset(_ action: ShortcutAction) {
        overrides.removeValue(forKey: action)
    }

    public mutating func resetAll() {
        overrides.removeAll()
    }

    public func issue(assigning shortcut: Shortcut, to action: ShortcutAction, normalize: Normalize = { $0 }) -> ShortcutIssue? {
        guard shortcut.hasModifier else { return .needsModifier }
        if action == .selectTab && !shortcut.isDigit { return .needsDigit }
        let wanted = Set(Self.combinations(of: shortcut, for: action).map(normalize))
        func taking(_ other: Shortcut) -> Bool {
            wanted.contains(normalize(other))
        }
        if let reserved = ReservedShortcut.all.first(where: { $0.owner == .app && taking($0.shortcut) }) {
            return .reserved(reserved.title)
        }
        for other in ShortcutAction.allCases where other != action {
            if let current = self[other], Self.combinations(of: current, for: other).contains(where: taking) {
                return .taken(other)
            }
        }
        if let reserved = ReservedShortcut.all.first(where: { $0.owner == .terminal && taking($0.shortcut) }) {
            return .terminal(reserved.title)
        }
        return shortcut.modifiers.contains(.command) ? nil : .terminal(nil)
    }

    /// Aller à un onglet prend les chiffres 1 à 9 avec ses touches de modification.
    public static func combinations(of shortcut: Shortcut, for action: ShortcutAction) -> [Shortcut] {
        guard action == .selectTab else { return [shortcut] }
        return (1 ... 9).map { Shortcut("\($0)", shortcut.modifiers) }
    }
}

/// `{"newTab": "alt+cmd+t", "splitDown": null}` : seuls les raccourcis changés. Une entrée
/// illisible, ou d'une action qui n'existe plus, est ignorée sans faire perdre les autres.
extension Shortcuts: Codable {
    public init(from decoder: Decoder) throws {
        let entries = try decoder.singleValueContainer().decode([String: String?].self)
        for (name, value) in entries {
            guard let action = ShortcutAction(rawValue: name) else { continue }
            if let value {
                guard let shortcut = Shortcut(parsing: value) else { continue }
                overrides[action] = .some(shortcut)
            } else {
                overrides[action] = .some(nil)
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var entries: [String: String?] = [:]
        for (action, shortcut) in overrides {
            entries[action.rawValue] = .some(shortcut?.description)
        }
        var container = encoder.singleValueContainer()
        try container.encode(entries)
    }
}
