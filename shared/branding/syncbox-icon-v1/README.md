# SyncBox 图标 v1

以双向箭头组成连续的 S 形，表达内容在个人设备之间收发；转角采用圆润、接近盒状的轮廓，呼应 SyncBox。蓝色背景延续应用现有配色，白色符号在小尺寸下保持清晰，不使用文字、设备轮廓或细碎装饰。

- `icon.svg`：可编辑的矢量母版，完整方形背景。
- `icon-1024.png`：1024 × 1024、不含透明通道的应用图标母版。
- `icon-512.png`、`icon-256.png`、`icon-64.png`、`icon-32.png`：不同尺寸 PNG。
- `mark.svg`：透明背景白色符号，适合深色或品牌色背景。
- `preview.png`：仅用于展示的圆角图标。平台导入应使用完整方形母版，让系统裁切圆角。
- `presentation.png`：图标与小尺寸效果预览。

绘制方式：原生 SVG 矢量设计，Sharp 导出 PNG。未使用 AI 位图生成或命令行图像 API。设计规格：SyncBox 私有多设备共享应用图标；蓝色底、白色 S 形双向箭头；简洁、几何、圆润转角；无文案、无水印、无设备插画；在 32 px 下保持辨识度。

从项目根目录执行 `node shared/branding/syncbox-icon-v1/render.mjs` 可重新导出设计稿。

## 各端接入

已同步 Web、Android、Windows、iOS/iPadOS 和 macOS。执行 `npm run icons:sync` 可从 `icon.svg` 统一重新导出各平台资源与 `platform-preview.png`。

- Web：标签页 SVG/ICO、180 px Apple Touch 图标、192/512 px Web Manifest 图标；登录页和工作台共用 `BrandIcon` 组件。
- Android：五档密度传统图标、圆形图标、API 26+ 自适应图标和 API 33+ 主题图标。前景使用 108 dp 画布与 72 dp 可视区域对应的留白，避免桌面裁切时丢失箭头。Flutter 连接页和工作台共用 `SyncBoxLogo`。
- Windows：`app_icon.ico` 包含 16、24、32、48、64、128、256 px，现有 Runner 资源同时用于窗口、任务栏和程序文件。
- Apple：iOS 使用无透明通道的完整 1024 px 方形；macOS 配齐 16–1024 px，预留 Dock 透明边距；连接页使用独立 `BrandIcon` 图片资源。

打包 Android 时继续使用原有开发签名。若使用临时 `XDG_CONFIG_HOME`，应显式将 `ANDROID_USER_HOME` 指向原有 `.android` 目录，避免生成另一份开发密钥导致无法覆盖旧包。Windows 原生可执行文件需在 Windows 上编译。
