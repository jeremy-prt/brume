import BrumeCore
import Foundation
import Testing

struct ShortcutTests {
    @Test func textFormRoundTrips() {
        for shortcut in [Shortcut("s", [.command, .control]), Shortcut("+"), Shortcut("return", [.command, .shift]), Shortcut("f5", .option)] {
            #expect(Shortcut(parsing: shortcut.description) == shortcut)
        }
        #expect(Shortcut(parsing: "ctrl+cmd+s")?.description == "ctrl+cmd+s")
        #expect(Shortcut(parsing: "cmd+plus") == Shortcut("+"))
        #expect(Shortcut(parsing: "cmd+hyper+s") == nil)
        #expect(Shortcut(parsing: "cmd+") == nil)
        #expect(Shortcut(parsing: "cmd+enter") == nil)
    }

    @Test @MainActor func labelFollowsTheMenuOrder() {
        #expect(Shortcut("d", [.shift, .command]).label == "⇧⌘D")
        #expect(Shortcut("left", [.command, .option, .control]).label == "⌃⌥⌘←")
        #expect(Shortcut("return", [.command, .shift]).label == "⇧⌘↩")
    }

    @Test func aCustomShortcutReplacesTheDefault() {
        var shortcuts = Shortcuts()
        shortcuts.set(Shortcut("t", [.command, .option]), for: .newTab)
        #expect(shortcuts[.newTab] == Shortcut("t", [.command, .option]))
        #expect(shortcuts.isCustom(.newTab))
        shortcuts.reset(.newTab)
        #expect(shortcuts[.newTab] == Shortcut("t"))
        #expect(!shortcuts.hasCustom)
    }

    @Test func theDefaultTypedAgainIsNotCustom() {
        var shortcuts = Shortcuts()
        shortcuts.set(Shortcut("t"), for: .newTab)
        #expect(!shortcuts.isCustom(.newTab))
    }

    @Test func aRemovedShortcutIsNone() {
        var shortcuts = Shortcuts()
        shortcuts.set(nil, for: .splitDown)
        #expect(shortcuts[.splitDown] == nil)
        #expect(shortcuts.isCustom(.splitDown))
    }

    @Test func aKeyAloneGoesToTheTerminal() {
        #expect(Shortcuts().issue(assigning: Shortcut("t", []), to: .newTab) == .needsModifier)
        #expect(Shortcuts().issue(assigning: Shortcut("t", .shift), to: .newTab) == .needsModifier)
    }

    @Test func goingToATabNeedsADigit() {
        #expect(Shortcuts().issue(assigning: Shortcut("t", .control), to: .selectTab) == .needsDigit)
        #expect(Shortcuts().issue(assigning: Shortcut("4", [.command, .option]), to: .selectTab) == nil)
    }

    @Test func macOSAndFixedShortcutsAreRefused() {
        #expect(Shortcuts().issue(assigning: Shortcut("q"), to: .newTab) == .reserved(.quit))
        #expect(Shortcuts().issue(assigning: Shortcut("f"), to: .newTab) == .reserved(.find))
        #expect(Shortcuts().issue(assigning: Shortcut("k"), to: .newTab) == .reserved(.clearScreen))
    }

    @Test func controlTabSwitchesTabsAsWell() {
        #expect(Shortcuts().issue(assigning: Shortcut("tab", .control), to: .splitRight) == .reserved(.nextTab))
        #expect(Shortcuts().issue(assigning: Shortcut("tab", [.control, .shift]), to: .splitRight) == .reserved(.previousTab))
        #expect(Shortcuts().issue(assigning: Shortcut("tab", [.control, .option]), to: .splitRight) == .terminal(nil))
    }

    @Test func closeTerminalSitsWithTheTabsBeforeCloseTab() {
        let tabs = ShortcutCategory.tabs.actions
        #expect(tabs.firstIndex(of: .closeTerminal).map { $0 + 1 } == tabs.firstIndex(of: .closeTab))
        #expect(!ShortcutCategory.splits.actions.contains(.closeTerminal))
    }

    @Test func anotherActionsShortcutCanBeTakenBack() {
        #expect(Shortcuts().issue(assigning: Shortcut("d"), to: .newTab) == .taken(.splitRight))
        // ⌘3 fait partie de ⌘1 à ⌘9.
        #expect(Shortcuts().issue(assigning: Shortcut("3"), to: .newTab) == .taken(.selectTab))
        #expect(Shortcuts().issue(assigning: Shortcut("1", [.command, .shift]), to: .selectTab) == nil)
    }

    @Test func itsOwnShortcutIsNoConflict() {
        #expect(Shortcuts().issue(assigning: Shortcut("t"), to: .newTab) == nil)
    }

    @Test func aRemovedShortcutFreesItsKeys() {
        var shortcuts = Shortcuts()
        shortcuts.set(nil, for: .splitRight)
        #expect(shortcuts.issue(assigning: Shortcut("d"), to: .newTab) == nil)
    }

    @Test func terminalKeysOnlyWarn() {
        #expect(Shortcuts().issue(assigning: Shortcut("left"), to: .newTab) == .terminal(.lineStart))
        #expect(Shortcuts().issue(assigning: Shortcut("t", .control), to: .newTab) == .terminal(nil))
        #expect(Shortcuts().issue(assigning: Shortcut("left"), to: .newTab)?.isBlocking == false)
    }

    @Test func comparisonsGoThroughTheKeyboardLayout() {
        // Un clavier où ⇧⌘[ s'écrit ⇧⌘^ : le ^ tapé retrouve le raccourci par défaut.
        let azerty: Shortcuts.Normalize = { $0.key == "[" ? Shortcut("^", $0.modifiers) : $0 }
        #expect(Shortcuts().issue(assigning: Shortcut("^", [.command, .shift]), to: .newTab, normalize: azerty) == .taken(.previousTab))
        var shortcuts = Shortcuts()
        shortcuts.set(Shortcut("^", [.command, .shift]), for: .previousTab, normalize: azerty)
        #expect(!shortcuts.isCustom(.previousTab))
    }

    @Test func sidebarShortcutUsesCommandBAndPreservesCustomBindings() throws {
        let defaults = AppSettings.decoded(from: Data(#"{"shortcuts": {}}"#.utf8))!
        #expect(defaults.shortcuts[.toggleSidebar] == Shortcut("b"))
        #expect(defaults.shortcuts[.verticalTabs] == Shortcut("s", [.command, .control]))
        #expect(defaults.shortcuts.issue(assigning: Shortcut("b"), to: .newTab) == .taken(.toggleSidebar))
        let customized = AppSettings.decoded(from: Data(#"{"shortcuts": {"verticalTabs": "alt+cmd+s", "toggleSidebar": "alt+cmd+b"}}"#.utf8))!
        let restored = AppSettings.decoded(from: try customized.encoded())!
        #expect(restored.shortcuts[.verticalTabs] == Shortcut("s", [.command, .option]))
        #expect(restored.shortcuts[.toggleSidebar] == Shortcut("b", [.command, .option]))
    }

    @Test func existingCommandBAssignmentsAreNotStolenByTheNewSidebarAction() throws {
        let settings = AppSettings.decoded(from: Data(#"{"shortcuts": {"verticalTabs": "cmd+b"}}"#.utf8))!
        var shortcuts = AppSettings.decoded(from: try settings.encoded())!.shortcuts
        #expect(shortcuts[.verticalTabs] == Shortcut("b"))
        #expect(shortcuts[.toggleSidebar] == nil)
        shortcuts.reset(.verticalTabs)
        #expect(shortcuts[.toggleSidebar] == Shortcut("b"))
    }

    @Test func savedShortcutsAreReadBack() throws {
        var settings = AppSettings()
        settings.shortcuts.set(Shortcut("t", [.command, .option]), for: .newTab)
        settings.shortcuts.set(nil, for: .splitDown)
        #expect(AppSettings.decoded(from: try settings.encoded()) == settings)
    }

    @Test func anUnreadableShortcutIsSkippedAndTheOthersSurvive() {
        let json = #"{"shortcuts": {"newTab": "alt+cmd+t", "splitDown": "cmd+nope", "gone": "cmd+x", "splitRight": null}}"#
        let shortcuts = AppSettings.decoded(from: Data(json.utf8))?.shortcuts
        #expect(shortcuts?[.newTab] == Shortcut("t", [.command, .option]))
        #expect(shortcuts?[.splitDown] == Shortcut("d", [.command, .shift]))
        #expect(shortcuts?[.splitRight] == nil)
    }
}
