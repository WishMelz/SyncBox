import SwiftUI

@main
struct SyncBoxApp: App {
    @State private var connection = ConnectionModel(platform: PlatformInfo.platform, deviceName: PlatformInfo.name)
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacDesktopController.self) private var desktop
    #endif
    var body: some Scene {
        #if os(macOS)
        Window("SyncBox", id: "main") {
            ContentView(connection: connection)
                .tint(ChatStyle.blue)
                .frame(minWidth: 760, minHeight: 540)
                .background(MacMainWindowRegistration())
                .task { desktop.configure(connection) }
        }
        .defaultSize(width: 960, height: 640)
        .windowResizability(.contentMinSize)
        MenuBarExtra("SyncBox", systemImage: "shippingbox") {
            MacQuickPanel(connection: connection)
                .tint(ChatStyle.blue)
                .task { desktop.configure(connection) }
        }
        .menuBarExtraStyle(.window)
        #else
        WindowGroup {
            ContentView(connection: connection).tint(ChatStyle.blue)
        }
        #endif
    }
}

enum PlatformInfo {
    static var platform: String {
        #if os(macOS)
        "macos"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "ipados" : "ios"
        #endif
    }
    static var name: String {
        #if os(macOS)
        Host.current().localizedName ?? "我的 Mac"
        #else
        UIDevice.current.name
        #endif
    }
}
