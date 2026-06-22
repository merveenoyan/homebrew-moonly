import SwiftUI

/// Moonly — a macOS menu-bar cycle tracker.
///
/// Everything runs on-device: symptom logs live in a local JSON file under
/// Application Support, and recommendations are generated in-process by
/// LlamaKit (llama.cpp) running Gemma 4 E4B (QAT). The only network egress is
/// the one-time, inbound model download from Hugging Face on first launch.
@main
struct MoonlyApp: App {
    @StateObject private var store = CycleStore.shared
    @StateObject private var llama = LlamaServer.shared

    var body: some Scene {
        MenuBarExtra {
            DropdownView()
                .environmentObject(store)
                .environmentObject(llama)
        } label: {
            // The icon reflects where the user is in their cycle, mirroring
            // the moon-phase metaphor the app is named for.
            Image(systemName: store.menuBarSymbolName)
                .accessibilityLabel("Moonly — \(store.currentPhase.title)")
        }
        .menuBarExtraStyle(.window)
    }
}
