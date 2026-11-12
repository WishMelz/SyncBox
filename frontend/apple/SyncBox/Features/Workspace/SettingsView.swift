import SwiftUI

struct SettingsView: View {
    @Bindable var connection: ConnectionModel
    let model: WorkspaceModel
    var embedded = false
    var onNavigationLockChanged: (Bool) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var settings: AppSettings?
    @State private var name = ""
    @State private var enabled = false
    @State private var days = "30"
    @State private var password = ""
    @State private var code = ""
    @State private var confirmation = ""
    @State private var secret: String?
    @State private var recovery: [String] = []
    @State private var busy = false
    @State private var error: String?
    @State private var notice: String?
    @State private var confirmingReset = false
    @State private var showDevices = false
    @State private var showLogout = false
    @State private var loaded = false
    var body: some View {
        NavigationStack {
            Form {
                if busy { ProgressView("正在保存…") }
                if let error { Section { Text(error).foregroundStyle(.red); Button("重新加载") { run { try await load() } } } }
                if let notice { Text(notice).foregroundStyle(.tint) }
                Section("账号与连接") {
                    LabeledContent("账号", value: connection.username)
                    LabeledContent("服务地址") { Text(connection.serverText).textSelection(.enabled) }
                    LabeledContent("同步状态", value: model.error != nil ? "连接中断" : model.lastSynced == nil ? "正在连接…" : model.realtimeConnected ? "实时同步" : "定时同步")
                    Button("刷新连接", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                }
                Section("当前设备") {
                    TextField("设备名称", text: $name)
                    Button("保存名称") { run { try await connection.renameDevice(name); notice = "设备名称已保存" } }
                        .disabled(!(1...80).contains(name.trimmingCharacters(in: .whitespacesAndNewlines).count))
                    LabeledContent("设备 ID") { Text(connection.deviceId ?? "未登记").font(.caption.monospaced()).textSelection(.enabled) }
                    Button("管理设备") { showDevices = true }
                }
                if let settings {
                    Section {
                        Text("\(settings.storage.fileCount) 个文件 · \(ByteCountFormatter.string(fromByteCount: Int64(settings.storage.bytes), countStyle: .file))").font(.caption).foregroundStyle(.secondary)
                        Toggle("自动清理闲置文件", isOn: $enabled)
                        TextField("闲置天数（1–3650）", text: $days).disabled(!enabled)
                        Button("保存清理设置") { run {
                            guard let value = Int(days), (1...3650).contains(value) else { throw APIError(message: "请输入 1–3650 天") }
                            let _: AppSettings = try await api.send("/settings/cleanup", method: "PATCH", body: CleanupInput(enabled: enabled, idleDays: value))
                            try await load(); notice = "清理设置已保存"
                        } }
                    } header: { Text("文件清理") } footer: { Text("按上传、预览、下载时间计算。自动删除长期未访问的图片和附件，保留消息文字。") }
                    Section {
                        LabeledContent("两步认证", value: settings.twoFactorEnabled ? "已开启" : "未开启")
                        SecureField("当前密码", text: $password)
                        TextField("验证码或恢复码", text: $code).autocorrectionDisabled()
                        if let secret {
                            Text("在验证器中手动添加下方密钥，再输入生成的 6 位验证码。密钥有效期 10 分钟。").font(.caption)
                            Text(secret).font(.body.monospaced()).textSelection(.enabled)
                            Button("取消设置") { clearSecurity() }
                        }
                        Button(settings.twoFactorEnabled ? "关闭两步认证" : secret == nil ? "设置两步认证" : "验证并开启") { run { try await changeTwoFactor() } }.disabled(password.count < 6 || !recovery.isEmpty)
                        if !recovery.isEmpty {
                            Text("请保存恢复码。每个只能使用一次，丢失验证器时可用于登录。").font(.callout)
                            Text(recovery.joined(separator: "\n")).font(.body.monospaced()).textSelection(.enabled)
                            Button("我已保存恢复码") { recovery = [] }
                        }
                    } header: { Text("账号安全") } footer: { Text("开启或关闭两步认证后，其他设备需重新登录。") }
                    Section {
                        Text("账号、设备、会话、消息和附件全部删除，恢复首次设置状态。无法撤销。").font(.callout)
                        TextField("输入“删除所有数据”确认", text: $confirmation)
                        Button("删除所有数据", role: .destructive) { confirmingReset = true }
                            .disabled(confirmation != "删除所有数据" || password.count < 6 || !recovery.isEmpty)
                    } header: { Text("删除所有数据") } footer: { Text("使用上方当前密码与验证码验证身份。") }
                }
                Section {
                    Button("退出登录", role: .destructive) { showLogout = true }
                        .disabled(!recovery.isEmpty || connection.busy)
                }
            }.formStyle(.grouped).disabled(busy)
                .navigationTitle("设置")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    if !embedded {
                        ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.disabled(busy || !recovery.isEmpty) }
                    }
                }
        }.frame(idealWidth: 560, idealHeight: 680)
            .interactiveDismissDisabled(busy || !recovery.isEmpty)
            .onChange(of: busy || !recovery.isEmpty, initial: true) { _, locked in onNavigationLockChanged(locked) }
            .task {
                guard !loaded else { return }
                loaded = true
                name = connection.deviceName
                run { try await load() }
            }
            .sheet(isPresented: $showDevices) { DevicesView(model: model, server: connection.serverText, currentDeviceId: connection.deviceId) }
            .alert("永久删除所有数据？", isPresented: $confirmingReset) {
                Button("取消", role: .cancel) {}
                Button("永久删除", role: .destructive) { run {
                    var body = security; body["confirmation"] = confirmation
                    _ = try await api.request("/settings/data", method: "DELETE", query: [:], body: JSONEncoder().encode(body))
                    if !embedded { dismiss() }
                    connection.resetLocalSession()
                } }
            } message: { Text("所有设备都将退出登录，此操作无法撤销。") }
            .alert("退出登录？", isPresented: $showLogout) {
                Button("取消", role: .cancel) {}
                Button("退出", role: .destructive) { Task {
                    await connection.logout()
                    if connection.error == nil && !embedded { dismiss() }
                } }
            } message: { Text("将撤销本设备当前登录，未发送的草稿不会保留。") }
    }
    private var api: APIClient { connection.api! }
    private var security: [String: String] {
        var body = ["password": password]
        if !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { body["code"] = code.trimmingCharacters(in: .whitespacesAndNewlines) }
        return body
    }
    private func clearSecurity() { password = ""; code = ""; secret = nil }
    private func load() async throws {
        let value: AppSettings = try await api.get("/settings")
        settings = value; enabled = value.cleanup.enabled; days = String(value.cleanup.idleDays)
    }
    private func changeTwoFactor() async throws {
        if settings?.twoFactorEnabled == true {
            let _: AppSettings = try await api.send("/settings/two-factor/disable", body: security)
            clearSecurity(); try await load(); notice = "两步认证已关闭"
        } else if secret == nil {
            let value: TwoFactorSetup = try await api.send("/settings/two-factor/setup", body: security)
            secret = value.secret; code = ""
        } else {
            let value: RecoveryCodes = try await api.send("/settings/two-factor/enable", body: security)
            recovery = value.recoveryCodes; clearSecurity(); try await load()
        }
    }
    private func run(_ action: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true; error = nil; notice = nil
        Task {
            defer { busy = false }
            do { try await action() }
            catch {
                if (error as? APIError)?.status == 401 {
                    if !embedded { dismiss() }
                    connection.expire()
                }
                else { self.error = userFacingError(error) }
            }
        }
    }
}
