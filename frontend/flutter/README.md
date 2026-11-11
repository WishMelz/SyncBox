# SyncBox Flutter — Android / Windows

面向 Android 和 Windows 的共用客户端。Flutter 3.47.9 / Dart 3.13.7，版本记录在 `.fvmrc`；依赖通过 `pubspec.lock` 锁定。Apple 原生客户端与 React Web 保持独立。

## 已实现的基础流程

- 填写私人服务站点地址，读取初始化状态。
- 首次设置唯一用户名/密码，或登录已有账号；密码至少 6 位。
- 自动登记 Android / Windows 设备名称。
- 系统安全存储登录凭证和连接配置，不保存密码。
- 会话创建、搜索、分页、重命名及确认删除。
- 会话内消息发送、搜索、向上连续加载、复制与收藏；显示发送设备。最近 20 个会话/搜索窗口在当前运行期间记住阅读位置，历史加载失败可手动重试；新消息仅在底部跟随。收藏列表保留分页。
- 手机单栏导航、宽屏（800px 起）双栏；中文 Material 组件。
- 前台每 5 秒刷新，应用进入后台暂停；失败显示错误并可重试。
- 登录失效返回登录页；切换服务不会携带原服务 token 或设备 ID。
- 当前会话草稿在内存中保存，发送失败保留，关闭应用后不保留。

已支持图片和附件传输、收藏、共享批注、设备设置及 SSE 实时同步。系统分享入口、托盘、开机启动与系统通知尚未实现。

## 目录

```text
frontend/flutter/
├── android/                  # 官方 Android Gradle/Kotlin 工程
├── windows/                  # 官方 Windows C++ Runner / CMake 工程
├── lib/
│   ├── main.dart             # 平台识别与依赖组装
│   ├── app.dart              # 主题、本地化、登录/工作台切换
│   ├── core/
│   │   ├── network/          # API、错误处理、地址校验
│   │   └── storage/          # 可替换的会话存储接口和安全存储实现
│   ├── models/               # Conversation、Message、分页模型
│   ├── features/
│   │   ├── connection/       # 连接、初始化、登录、恢复和退出
│   │   └── workspace/        # Repository、状态控制器、组件化界面
│   └── shared/widgets/       # 共用组件
├── test/                     # HTTP、状态逻辑和响应式组件测试
└── pubspec.yaml
```

## 开发准备

安装 Flutter 3.47.9（或使用 FVM 读取 `.fvmrc`），把 `flutter` 和 `dart` 加入 PATH：

```sh
cd frontend/flutter
flutter pub get
flutter doctor -v
flutter analyze
flutter test
```

本次在 macOS 中使用临时 SDK `/private/tmp/syncbox-flutter-sdk` 和依赖缓存 `/private/tmp/syncbox-pub-cache` 完成验证，未修改全局 PATH。这些临时目录可能被系统清理，日常开发应安装持久 SDK。现阶段验证为静态分析和单元/组件测试，尚未在 Android 真机或 Windows 原生运行。

### Android

安装 Android Studio、Android SDK、Command-line Tools、对应 SDK Platform 和 Build Tools，按 `flutter doctor` 提示完成许可与模拟器配置，然后：

```sh
flutter devices
flutter run -d <android-device-id>
flutter build apk --debug
```

应用标识 `com.theo.syncbox`。已加入联网权限、关闭 Android 自动备份以避免安全存储密钥被错误迁移。支持私人局域网 HTTP，但界面要求显式勾选；生产建议使用 HTTPS，客户端不绕过 TLS 证书验证。

生成模板的 release 仍使用开发签名。分发前需配置正式 keystore 和 Gradle release signing；不要把 `key.properties` 或 keystore 提交到仓库。

### Windows

必须在 Windows 上安装 Flutter 和 Visual Studio 2022（包含 **Desktop development with C++**、Windows SDK、CMake），再执行：

```powershell
cd frontend/flutter
flutter pub get
flutter doctor -v
flutter run -d windows
flutter build windows --release
```

产物默认位于 `build/windows/x64/runner/Release/`，分发时需要整个目录，不能只复制 exe。当前未配置 MSIX/安装器或代码签名。

## 服务地址与现有后端连接

客户端输入的是站点 origin，例如 `https://sync.example.com`，不填写 `/api`；客户端统一追加 `/api/v1`。可直接访问后端，也可连接 Nginx 反向代理的站点地址。原生 App 不受浏览器 CORS 限制。

| 运行环境 | 服务地址示例 |
| --- | --- |
| Windows 与后端在同一台机器 | `http://127.0.0.1:3000` |
| Android 官方模拟器访问宿主机 | `http://10.0.2.2:3000` |
| Android 真机访问电脑后端 | `http://电脑局域网IP:3000` |
| 已部署 Nginx 站点 | `https://sync.example.com` |

真机访问时，确认 `backend/.env` 设置 `HOST=0.0.0.0` 并允许防火墙访问。客户端不会自动修改服务器监听范围。Docker Compose 的端口绑定应按实际部署环境配置。

HTTP 请求不会跟随重定向（避免凭证被转发到其他目标）；请使用服务最终地址。请求超时 15 秒。Token 使用 flutter_secure_storage：Android 系统密钥存储、Windows Credential Manager 配合加密文件。首次账户应由部署者设置；无硬编码账号。

## 开发约定

页面通过 Controller 调用 Repository，HTTP 与安全存储可以在测试中替换。新增业务按 feature 组织；通用 DTO 与 OpenAPI 以仓库 `shared/contracts/openapi.yaml` 和 `docs/api/README.md` 为准。Widget 中不直接保存密码或打印请求头。

可用只读诊断脚本检查后端连通，不创建账号、不发送消息：

```sh
dart run tool/check_server.dart http://127.0.0.1:3000
```

## 图片消息更新

Android / Windows 使用 `file_selector` 选择 JPEG、PNG、WebP、GIF（单张 8 MB），预览并附文字发送，失败保留图片。图片通过 Bearer 鉴权读取，可点开缩放预览。已通过 Flutter 静态检查和测试；未在 Android/Windows 真机验证文件选择器。

## 共享批注

Android/Windows 共用的消息卡片已接入批注展示、展开、添加/编辑与二次确认删除；每条消息最多 2000 字符，保存失败保留草稿。搜索消息和会话均可匹配批注。模型兼容没有 annotation 字段的旧消息响应，写入需升级后端。已通过静态分析、API 请求及组件测试；本次未在 Android 真机或 Windows 系统运行，也未输出 APK/EXE。

## 唯一设备 ID（2026-11-08）

Android/Windows 使用 `Random.secure()` 生成 UUID v4，并通过安全存储独立保存到 `syncbox.installation.id.v1`。清除会话、退出登录、设备改名或切换服务器不会清除此标识；并发读取共用同一次初始化，保存失败时不登记临时 ID。

登录和恢复已有会话均携带 `installationId`，服务端按账号和平台匹配设备，保留设备名称及 ID；旧设备可原位绑定，404/409 时仅去掉旧设备 ID 后重试。设备列表显示可选中的 ID 和“当前设备”。无网络时保留恢复中的会话，指纹或安装 ID 不用于免密认证。

这是应用安装标识，不是硬件序列号；卸载/清除应用存储可能生成新标识，克隆完整应用数据可能复制标识。Android 已关闭自动备份。Windows 共用逻辑通过 Dart 测试和静态分析，Windows 原生编译及系统安全存储实测仍需 Windows 主机。


## 可靠同步与发送重试（2026-11-09）

已接入当前会话新消息自动已读、带鉴权的 SSE 实时通知及前后台连接清理，会话列表不显示未读数字。重连成功后补拉数据，异常时使用轮询；状态栏显示“实时同步”或“定时同步”。发送文字、图片、附件失败后保留草稿，并在当前应用会话内复用发送 ID 重试，避免服务端已经保存但响应丢失时重复发送。更改发送内容或附件后会按新发送处理。

发送失败仅提示并保留当前运行中的草稿，由用户手动再次发送；刷新和网络恢复不会补发，不使用持久离线队列。消息已发送但后续读取失败时，提示“消息已发送，列表刷新失败，请刷新查看。”，不恢复已提交的草稿。错误栏的“刷新”只读取数据。更新后的代码需要重新构建安装包；验证见 `docs/testing/manual-send-2026-11-09.md`。

## TG 风格消息与搜索（2026-11-09）

Android/Windows 同步 Web 的蓝白消息气泡、当前设备靠右、底部时间与跨日分隔。消息和会话支持长按/右键菜单，同时保留更多按钮；删除仍需确认。输入区使用统一纸夹菜单选择图片或文件，附件限制收进菜单，小视口会压缩草稿区高度。

搜索结果在正文、批注、附件名、会话标题/预览、收藏中高亮；长批注命中时自动展开。正文中的 HTTP(S) 链接通过 Android 系统浏览器或 Windows 默认浏览器打开，高亮不改变复制内容和链接目标。消息搜索默认收起，Ctrl/Cmd+F 打开、Esc 收起并清除筛选。

验证范围和原生平台限制见 `docs/testing/native-telegram-search-2026-11-09.md`。Windows 原生 Runner 需在 Windows 主机编译与运行验证；旧安装包需重新构建后才能使用本轮界面。

## 菜单交互同步（2026-11-10）

- 会话列表统一单个横向“更多”图标；选中浅蓝背景时使用深蓝图标，保持清晰对比，不额外显示下拉箭头。
- 消息“更多”按钮紧贴气泡，桌面打开菜单期间保持可见；右键（Windows）和长按（Android）沿用同一组中文复制、收藏、批注、删除操作，删除仍需确认。
- 右键/长按覆盖气泡内边距，普通点击图片仍打开预览；应用系统组件语言统一为简体中文。
- 已通过 `flutter analyze` 和 53 项测试，其中新增 7 项覆盖窄/宽屏气泡按钮距离、选中图标对比度、菜单打开状态和图片右键/长按/预览。此次未重新打包 APK 或 Windows 安装包，也未进行 Windows 真机验证。
