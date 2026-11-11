# 原生端唯一设备 ID 适配（2026-11-08）

## 实现

- iOS / iPadOS / macOS：使用 Foundation UUID，独立 UserDefaults 项持久保存安装标识，不触发钥匙串授权。
- Android / Windows：使用 Dart Random.secure 生成 UUID v4，安全存储独立键保存，并发初始化复用同一次读取/写入。
- 登录与恢复会话均向后端提交 installationId，旧设备附带原 ID 进行迁移。404/409 时仅移除旧记录 ID，继续携带原安装 UUID 重试。
- 保留后端设备名称，退出、过期和服务器变更不删除安装标识；设备记录及登录令牌仍按服务器隔离。
- 各端设备列表显示可选中的服务端设备 ID 和“当前设备”标记。

## 验证

- Apple 14 项单元测试通过，涵盖安装标识持久化、登录恢复时绑定、404/409 重试、名称同步及原有会话生命周期。1 项可选的真实 HTTP 联调因未配置测试服务器跳过，未把它计入通过数。
- macOS 与 iOS Simulator 的 Xcode 构建通过（CODE_SIGNING_ALLOWED=NO）。未生成新 IPA，未更新已安装 Apple App。
- Flutter 22 项测试通过，新增 6 项涵盖安全存储、并发初始化、清除会话、Android/Windows 旧设备绑定及重试、网络失败保留会话。
- Flutter analyze 无问题。
- 后端设备绑定测试 3 项通过，包含真实 Nest 内存数据库流程，覆盖五个平台的安装标识匹配、旧设备迁移、不同安装隔离和名称保留。
- Android release APK 构建成功，apksigner 校验通过，沿用 Android Debug 开发证书；未在模拟器或真机安装。
- Windows 原生构建与操作系统安全存储未实机验证（当前宿主为 macOS）。
- 正式 Web 代理健康接口返回 status=ok、database=up。

## APK

已更新项目根目录与用户指定的 `/Users/theo/macmini/SyncBox-release.apk`。
SHA-256：`f020153c0b0d94782ec7b6cfb97e55d1071acb34b769285abf81f7c7e483dfca`。

## 边界

安装 UUID 不等于硬件唯一号，也不是身份认证凭据。退出登录、重启、通常的覆盖更新会保留；清除存储或卸载可能重建。复制或恢复完整应用数据可能复制安装标识。服务端删除设备记录后会创建新记录 ID，安装 UUID 本身不变。Web 继续使用浏览器指纹协议。
