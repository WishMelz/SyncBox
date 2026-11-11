import SwiftUI

@main
struct SyncBoxApp: App {
    @State private var connection = ConnectionModel(platform: PlatformInfo.platform, deviceName: PlatformInfo.name)
    var body: some Scene {
        WindowGroup {
            ContentView(connection: connection)
                .tint(ChatStyle.blue)
                #if os(macOS)
                .frame(minWidth: 820, minHeight: 580)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1120, height: 760)
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
