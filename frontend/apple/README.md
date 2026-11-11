# SyncBox Apple 客户端

原生 SwiftUI 客户端，共用一个 Xcode target，支持 iOS / iPadOS 17+ 与 macOS 14+。连接现有 NestJS / SQLite 服务，采用一个私有部署、一个账号、所有设备共享会话和消息的模型。

## 已实现

- 自定义服务器地址，自动检测是否需要首次设置；用户名和密码只在后端初始化一次，密码 6–128 位。
- 首次手动登录后记住此设备，启动时验证并恢复登录；退出撤销凭证，401 清除本地会话并重新登录。密码不保存，也不访问钥匙串。
- 登记 iPhone / iPad / Mac 设备，展示发送设备和已登记设备列表。
- 会话创建、分页、搜索、重命名、删除；消息正文发送、向上连续加载、关键词搜索、复制、收藏、删除。删除前二次确认。最近 20 个会话/搜索窗口在当前运行期间记住阅读位置；加载历史失败保留内容并支持手动重试。底部跟随新消息，阅读历史时保持位置。
- iPhone 列表/详情导航，iPad 和 Mac 自适应双栏，深浅色和系统字体适配；Mac ⌘N 创建会话，Enter 发送、Shift+Enter 换行，也支持 ⌘Enter 发送。中文输入法组合输入期间的 Enter 交给输入法确认，不发送消息。
- 前台每 5 秒拉取，后台暂停。异步响应校验当前会话和查询条件，避免旧内容覆盖新选择；发送失败保留草稿，发送期间的新草稿也不会被清空。

草稿只保留在进程内，退出或关闭应用不会持久保存。已支持图片及附件上传、共享批注、收藏、设备设置和 SSE 实时同步；尚未实现 APNs、分享扩展、菜单栏程序或离线消息数据库。

## 打开与运行

```sh
open frontend/apple/SyncBox.xcodeproj
```

在 Xcode 选择 `SyncBox` Scheme 和 `My Mac`、iPhone 或 iPad 模拟器，点击 Run。实际 iPhone/iPad 运行需要在 Signing & Capabilities 中选择自己的 Team，并按需要修改 bundle identifier（当前为 `com.theo.SyncBox`）。无需第三方 Swift 依赖。

先在项目根目录启动后端：

```sh
npm run dev:backend
```

Mac 和同一台 Mac 的 iOS 模拟器可以填写 `http://127.0.0.1:3000`，并勾选局域网 HTTP。也可填写具有 `/api` 反向代理的服务根地址。不要填写 `/api/v1` 路径。

真实手机上的 `127.0.0.1` 是手机本身。真机需要填写 Mac 的局域网地址或部署服务域名；后端默认只监听回环地址，按部署需要显式配置 `HOST=0.0.0.0` 或使用可达的反向代理，并允许系统本地网络访问。客户端开发没有修改当前后端监听配置。

首次部署才显示“设置唯一账号”；已有服务直接登录原账号，不会清空数据库或创建第二个账号。

## 目录

```text
SyncBox/
  Core/
    APIClient.swift       # URLSession、URL 校验、鉴权、错误映射、禁止重定向
    Models.swift          # 后端 JSON 模型
    SessionStore.swift    # 连接偏好、本地会话存储及可替换协议
    ConnectionModel.swift # 服务连接、认证、偏好恢复与设备登记
    WorkspaceModel.swift  # 会话与消息状态、分页和异步结果保护
  Features/
    Connection/           # 服务器配置、首次设置和登录
    Workspace/            # 双栏工作台、消息详情、卡片与设备列表
  ContentView.swift
  SyncBoxApp.swift
Configuration/Info.plist   # 局域网使用说明与自托管服务网络配置
Tests/                    # Swift 核心逻辑和可选真实 API 集成测试
Package.swift             # 独立运行核心逻辑测试，不影响 Xcode App target
```

## 网络和登录状态

默认要求 HTTPS。为了兼容动态私人服务的局域网 HTTP 地址，Info.plist 配置 ATS `NSAllowsArbitraryLoads`；应用层仍要求用户主动勾选 HTTP。未绕过 TLS 证书校验，不跟随 HTTP 重定向，不将令牌转发到其他服务。外网应通过受信任的 HTTPS 反向代理连接；App Store 发布时需要说明 HTTP 例外用途，或在仅支持 HTTPS 的分发版本中移除该例外。

URLSession 使用 ephemeral configuration，关闭 Cookie 和响应缓存。UserDefaults 仅保存服务器和设备配置；令牌单独保存在应用容器 Application Support/SyncBox/Session/session.json，目录权限 0700，文件权限 0600，并排除备份；iOS 另使用系统文件保护。令牌为本地明文文件，依赖应用沙箱和系统账户权限保护，不等同于钥匙串加密。密码从不保存。

启动时通过 `/auth/me` 验证保存的令牌后恢复工作台。网络失败保留会话，重试连接即可继续；401、主动退出或切换服务会清除本地令牌。后端当前会话有效期为 7 天，到期或设备被移除后需重新登录。历史钥匙串条目不再读取、迁移或删除，不触发其访问授权。Mac 保持 App Sandbox 和 outgoing network entitlement。

本地 ad-hoc 签名可用于 Mac 开发验证。正式发布需要 Apple 签名、应用图标、归档及公证/App Store 配置；当前未生成正式 IPA/DMG。

## 验证

```sh
./scripts/apple-check.sh
```

该脚本分别执行核心测试、Mac 构建和 iOS Simulator 构建；默认使用 `/Applications/Xcode.app`，可通过 `DEVELOPER_DIR` 覆盖。中间文件位于临时目录，可用 `APPLE_BUILD_DIR` 指定。也可以仅运行：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --package-path frontend/apple
```

核心 12 项测试覆盖服务地址校验、HTTP 同意、鉴权/查询编码、初始化冲突、6 位密码、设备登记/非凭据偏好存储、重启自动登录、本地令牌权限、过期清理、断网恢复、退出/过期、服务隔离、旧请求竞争、发送失败和发送期间编辑草稿。

真实 API 集成测试默认跳过。先启动使用**独立临时 SQLite 数据库**和非 3000 端口的后端，并设置测试账号，然后提供 `SYNCBOX_TEST_SERVER`、`SYNCBOX_TEST_USERNAME`、`SYNCBOX_TEST_PASSWORD` 环境变量运行 `swift test`。仅接受回环地址且禁止默认 3000 端口；测试会创建临时设备、会话、消息并清理，不要使用个人真实数据库。

本次已验证：Mac 与 iOS Simulator 编译通过；12 项核心测试通过；此前的 1 项真实双设备 API 集成测试通过；Mac 窗口完成登录、会话创建、读取/发送消息和关键词搜索。iPhone 模拟器已安装并启动；尚未完成 iPhone/iPad 真机与完整触控流程验证。

## 图片消息更新

已加入消息图片鉴权读取和大图预览，输入区支持选择图片文件，iOS 另支持系统照片选择器。发送前预览、移除，可附文字，失败保留图片草稿。原始选择数据最多 8 MB、2400 万像素；HEIC 等系统支持的图片格式转换成 JPEG 后上传。Mac 开启用户选择文件只读权限。图片草稿不跨重启保存。

本次 Mac/iOS 编译和 Swift API 图片联调通过；照片图库与真机图片选择仍需设备验证。之前生成的 IPA 不包含本次更新，需要重新打包签名后安装。

## 共享批注

iOS/iPadOS/macOS 的消息操作区新增批注入口，支持展示、展开、编辑和确认删除；每条消息保存一份最多 2000 字符的纯文本批注。编辑失败保留草稿，消息搜索可匹配批注关键词。服务端需包含 `1794000000008-annotations` 迁移。通过 Apple 核心测试和隔离 API 联调，并验证 iOS Simulator/macOS 编译；未重新打包 IPA。

## 唯一设备 ID（2026-11-08）

iOS/iPadOS/macOS 使用 `UUID()` 生成安装标识，单独保存在 `syncbox.installation.id.v1` 偏好项，不随退出登录、令牌到期或切换服务器清除。登录及恢复会话时提交 `installationId`，后端按账号、平台、安装标识复用服务端设备 ID，并保留服务端自定义名称。升级时附带旧设备 ID 绑定历史记录；404/409 时去掉旧 ID，以同一安装标识重试。设备列表显示可选中的 ID，并标注当前设备。

安装标识不是密码或硬件序列号。清除应用数据或卸载重装后可能变化；完整克隆应用数据也会复制安装标识，因此不构成物理设备证明。切换服务器不会发送旧服务的凭证或设备记录 ID，安装标识由目标服务独立登记。此次修改需更新客户端安装包后生效。


## 可靠同步与发送重试（2026-11-09）

已接入当前会话新消息自动已读、带鉴权的 SSE 实时通知及前后台连接清理，会话列表不显示未读数字。重连成功后补拉数据，异常时使用轮询；状态栏显示“实时同步”或“定时同步”。发送文字、图片、附件失败后保留草稿，并在当前应用会话内复用发送 ID 重试，避免服务端已经保存但响应丢失时重复发送。更改发送内容或附件后会按新发送处理。

发送失败仅提示并保留当前运行中的草稿，由用户手动再次发送；刷新和网络恢复不会补发，不使用持久离线队列。消息已发送但后续读取失败时，提示“消息已发送，列表刷新失败，请刷新查看。”，不恢复已提交的草稿。更新后的代码需要重新构建安装包；验证见 `docs/testing/manual-send-2026-11-09.md`。

## TG 风格消息与搜索（2026-11-09）

iOS/iPadOS/macOS 同步 Web 的蓝白气泡、当前设备消息靠右、底部时间及日期分隔。消息支持系统长按/右键菜单与更多按钮，包含复制、收藏、批注、删除；删除保持二次确认。纸夹菜单统一图片、照片图库和文件入口，取消常驻的附件限制说明。

搜索结果对正文、批注、附件名、会话标题/预览和收藏高亮，长批注命中后自动展开。HTTP(S) 链接可直接打开，复制仍保留原文。搜索默认收起，Mac 支持 ⌘F 打开和 Esc 收起并清除筛选；Enter、Shift+Enter 和中文输入法确认行为保持不变。

编译、核心测试和验证限制见 `docs/testing/native-telegram-search-2026-11-09.md`。此次未导出新的 IPA，旧安装包需要重新构建安装后生效。
