# SyncBox iOS IPA

- 文件：`SyncBox-1.0-1-unsigned.ipa`
- 版本：1.0（Build 1）
- Bundle ID：`com.theo.SyncBox`
- 支持：iPhone / iPad，iOS / iPadOS 17.0+
- 架构：arm64，iPhoneOS SDK Release 真机归档
- 状态：**未签名**，不含 provisioning profile，不能直接安装或上传 TestFlight / App Store。

本机无可用 Apple 签名证书及描述文件，因此此 IPA 供后续合法签名工具或签名流程使用。正式分发需在 Xcode 配置 Team、证书和匹配的描述文件后重新归档并导出。未完成真机安装验证。

已验证归档成功、ZIP 完整性、Payload 目录、应用版本、设备类型及 arm64 可执行文件。校验值见同目录 `.sha256` 文件。

安装签名后的应用时，服务地址应填写手机可访问的服务器地址；手机上的 `127.0.0.1` 不能连接 Mac 后端。
