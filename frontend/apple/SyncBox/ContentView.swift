import SwiftUI

struct ContentView: View {
    @Bindable var connection: ConnectionModel
    var body: some View {
        Group {
            if connection.stage == .workspace, let workspace = connection.workspace {
                WorkspaceView(model: workspace, connection: connection)
            } else {
                ConnectionView(model: connection)
            }
        }
        .task { await connection.restore() }
        .alert("连接提示", isPresented: Binding(get: { connection.error != nil }, set: { if !$0 { connection.error = nil } })) {
            Button("好", role: .cancel) { connection.error = nil }
        } message: { Text(connection.error ?? "") }
    }
}
