import SwiftUI

struct ConnectionView: View {
    @Bindable var model: ConnectionModel
    @State private var password = ""
    @State private var confirmation = ""
    @State private var code = ""
    private var isServer: Bool { model.stage == .server }
    private var valid: Bool {
        !model.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (6...128).contains(password.count) &&
        (1...80).contains(model.deviceName.trimmingCharacters(in: .whitespacesAndNewlines).count) &&
        (model.initialized || password == confirmation) &&
        (!model.requiresTwoFactor || !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 12) {
                    Image("BrandIcon").resizable().scaledToFit()
                        .frame(width: 64, height: 64).accessibilityHidden(true)
                    Text("SyncBox").font(.largeTitle.bold())
                    Text("你的内容，在每台设备之间。")
                        .font(.title3).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 18) {
                    Text(isServer ? "连接私人服务" : model.initialized ? "欢迎回来" : "设置唯一账号")
                        .font(.title2.bold())
                    if isServer {
                        Text("填写你部署的 SyncBox 地址。所有设备连接同一服务，即可共享会话和消息。")
                            .foregroundStyle(.secondary)
                        field("服务地址") {
                            TextField("https://sync.example.com", text: $model.serverText)
                                .textContentType(.URL)
                                #if os(iOS)
                                .keyboardType(.URL).textInputAutocapitalization(.never)
                                #endif
                                .autocorrectionDisabled()
                        }
                        Toggle("允许 HTTP（仅限受信任局域网）", isOn: $model.allowHTTP)
                        if model.allowHTTP {
                            Text("HTTP 会明文传输密码与消息；外网连接请使用 HTTPS。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Button { Task { await model.connect() } } label: {
                            actionLabel("连接服务", icon: "arrow.right")
                        }.disabled(model.serverText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } else {
                        Text(model.serverText).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        if !model.initialized {
                            Text("此服务只设置一个账号。其他设备使用同一账号登录。")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Text("登录后自动记住此设备，无需每次输入账号和密码。")
                            .font(.caption).foregroundStyle(.secondary)
                        field("用户名") {
                            TextField("输入用户名", text: $model.username)
                                .textContentType(.username)
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                #endif
                                .autocorrectionDisabled()
                                .disabled(model.requiresTwoFactor)
                        }
                        field("密码") {
                            SecureField("6–128 位密码", text: $password)
                                .textContentType(model.initialized ? .password : .newPassword)
                                .disabled(model.requiresTwoFactor)
                        }
                        if !model.initialized {
                            field("确认密码") { SecureField("再次输入密码", text: $confirmation).textContentType(.newPassword) }
                        }
                        if model.initialized && model.requiresTwoFactor {
                            field("两步验证码") {
                                TextField("6 位动态码或恢复码", text: $code).autocorrectionDisabled()
                            }
                            Text("密码已验证，请输入验证器动态码或恢复码。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        field("此设备名称") { TextField("例如：我的 iPhone", text: $model.deviceName) }
                        Button {
                            Task {
                                await model.authenticate(password: password, code: code)
                                if model.stage == .workspace { password = ""; confirmation = "" }
                            }
                        } label: { actionLabel(model.initialized ? (model.requiresTwoFactor ? "验证并登录" : "登录") : "创建账号并进入", icon: "arrow.right") }
                        .disabled(!valid)
                        Button("更换服务地址") { password = ""; confirmation = ""; model.editServer() }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                .disabled(model.busy)
                Label("iPhone · iPad · Mac · Android · Windows · Web", systemImage: "network")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: 460)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background(Color.indigo.opacity(0.045))
    }
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(label).font(.subheadline.weight(.medium)); content() }
    }
    private func actionLabel(_ title: String, icon: String) -> some View {
        HStack { Spacer(); if model.busy { ProgressView().controlSize(.small) }; Text(title); Image(systemName: icon); Spacer() }
    }
}
