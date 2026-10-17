import BrumeCore
import SwiftUI

/// Passe des onglets en haut à la barre latérale, dans toutes les fenêtres.
struct VerticalTabsCommands: Commands {
    @FocusedValue(\.terminalWorkspace) private var workspace
    let settings: SettingsStore

    var body: some Commands {
        CommandGroup(before: .sidebar) {
            Button(L10n.text(.toggleSidebar)) {
                workspace?.showingTerminals { $0.isSidebarHidden.toggle() }
            }
            .keyboardShortcut(settings.keyboardShortcut(.toggleSidebar))
            .disabled(workspace == nil || !settings.verticalTabs.isOn)
            Toggle(L10n.text(.verticalTabs), isOn: Binding(
                get: { settings.verticalTabs.isOn },
                set: { settings.verticalTabs.isOn = $0 }
            ))
            .keyboardShortcut(settings.keyboardShortcut(.verticalTabs))
        }
    }
}
