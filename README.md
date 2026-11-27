# SyncBox

多端应用项目：Android / Windows 客户端使用 Flutter，Apple 客户端使用 SwiftUI，Web 使用 React + Vite + shadcn/ui，后端使用 NestJS + SQLite。

## 快速开始

安装 Node.js 24，在项目根目录执行：

```sh
npm ci
cp backend/.env.example backend/.env
npm run dev
```

- Web：http://localhost:5173
- 后端健康检查：http://127.0.0.1:3000/api/v1/health
- SQLite：首次启动自动创建 `backend/data/syncbox.sqlite`。

也可分别执行 `npm run dev:web` 和 `npm run dev:backend`。

## 验证与构建

```sh
npm run check
```

执行前后端类型检查、后端集成测试和生产构建。后端构建后通过 `npm start -w @syncbox/backend` 启动；Web 静态产物在 `frontend/web/dist/`。生产部署可使用单个 Docker 镜像，由后端同时提供静态页面和 `/api` 接口。

## Docker 部署

[Docker Hub 镜像 `wishmelz/syncbox`](https://hub.docker.com/r/wishmelz/syncbox) 已包含 Web 页面和后端。安装 Docker 后可直接运行；生产环境建议固定明确镜像标签（SQLite 迁移启动时自动执行，**降级版本不可逆**，升级前建议先下载数据库备份并按 [备份恢复演练说明](docs/backup-restore.md) 验证）。

### 1. 直连部署（局域网 / 直接暴露端口）

将 [compose.yaml](infra/docker/compose.yaml) 单独保存到部署目录并运行：

```sh
SYNCBOX_VERSION=v1.0.6 docker compose up -d --pull always
```

直连配置默认 `TRUST_PROXY=false`，直接读取 TCP 来源 IP 进行登录/安全操作限流，防止客户端伪造 `X-Forwarded-For` 绕过限流。可通过 `.env` 设置 `SYNCBOX_PORT=16384` 和 `SYNCBOX_VERSION`。

### 2. 反向代理部署（Nginx + 内网后端）

将 [compose.proxy.yaml](infra/docker/compose.proxy.yaml) 和 [nginx.proxy.conf](infra/docker/nginx.proxy.conf) 放到同一目录并运行：

```sh
docker compose -f compose.proxy.yaml up -d --pull always
```

代理拓扑仅对内网暴露 `syncbox:3000`，由前段 Nginx 覆写 `X-Forwarded-For $remote_addr`、启用 `client_max_body_size 21m`、为 `/api/v1/events` 关闭 `proxy_buffering` 并延长读超时（3600s），后端在 `TRUST_PROXY=true` 下准确识别真实客户端 IP。更新时在原部署目录沿用同一配置和项目名即可保留数据卷。

## Windows 免安装版

在 [GitHub Releases](https://github.com/WishMelz/SyncBox/releases) 下载名称含 `Windows-x64-Portable` 的 ZIP。完整解压到一个文件夹，双击其中的 `syncbox.exe` 启动。请保留同目录的 DLL 和 `data` 文件夹。

## 目录

```text
SyncBox/
├── Dockerfile                 # Web + 后端单镜像构建入口
├── frontend/
│   ├── flutter/               # Flutter：Android / Windows
│   ├── apple/                 # SwiftUI：iPhone / iPad / Mac
│   └── web/                   # React + Vite + shadcn/ui
│       └── src/
│           ├── components/    # ui 基础组件、layout 通用布局
│           ├── pages/         # 页面
│           ├── hooks/         # 交互与状态逻辑
│           ├── services/      # API 请求
│           ├── lib/           # 工具函数
│           └── styles/        # 全局样式与主题
├── backend/
│   ├── src/
│   │   ├── config/            # 环境变量
│   │   ├── database/          # TypeORM + SQLite
│   │   └── modules/           # auth、devices、messages、health
│   ├── src/database/migrations/ # 启动自动执行的版本化迁移
│   └── tests/                 # 集成测试
├── shared/contracts/          # OpenAPI 接口契约
├── docs/                      # 架构与接口文档
├── infra/docker/              # Compose 与容器配置
├── infra/deploy/              # 部署预留
└── scripts/                   # 维护脚本预留
```

详细说明：[后端](backend/README.md)、[Web](frontend/web/README.md)、[接口](docs/api/README.md)。

## GitHub 发布

仓库地址：[github.com/WishMelz/SyncBox](https://github.com/WishMelz/SyncBox)。GitHub Actions 会在推送 `main` 或 Pull Request 时执行检查；推送 `vMAJOR.MINOR.PATCH` 标签后，会自动构建各端测试包、发布多架构 Docker 镜像并创建 GitHub Release。首次发布前请按 [GitHub 发布说明](docs/github-release.md) 配置 Docker Hub Access Token。

## 多端能力与交付矩阵

| 端 / 模块 | 源码支持 | 发布包包含 | 已验收平台 |
| --- | --- | --- | --- |
| Backend + Web（NestJS / SQLite / React） | 单账号认证与 TOTP 两步认证、`clientId` 幂等消息/图片/多附件（最多 5 个、合计 20 MiB）、SSE 实时通知 + 会话绑定续期/撤销、文件中心（按 `category` 筛选图片/文件）、消息批注/收藏/连续游标分页、内存图片/预览 LRU 缓存、SQLite 一致性备份与 SHA-256 校验、闲置清理与阈值紧缩、`EXPLAIN QUERY PLAN` 与 41 路由 OpenAPI 契约检查 | Docker Hub 多架构镜像 `wishmelz/syncbox`（直连 `compose.yaml` 与反代 `compose.proxy.yaml` + `nginx.proxy.conf`） | 本地 Node.js 24 & GitHub Actions `ubuntu-24.04`（`npm run check`：后端 26 项集成/安全/备份测试、Web 23 项单元测试、OpenAPI 41 路由校验、TypeScript 与生产构建） |
| Flutter（Android / Windows） | 连接/认证/唯一安装 ID、SSE 作用域精准刷新（按 `scope`+`conversationId`+`messageId` + 5 分钟核对）、连续消息历史、内存 `MemoryMediaCache`、流式 XFile 多附件上传进度与取消、文件中心视图、TOTP 验证器直连与密钥复制、SHA-256 校验数据库备份下载 | GitHub Releases `SyncBox-Android-<tag>.apk`、`SyncBox-Windows-<tag>.zip`、`SyncBox-Windows-x64-Portable-<tag>.zip` | GitHub Actions `ubuntu-24.04`（`flutter analyze` + `flutter test`）及 `windows-latest` Release 打包冒烟；代码改动后将在对应 CI 流程验证 |
| Apple（iOS / iPadOS 17+ / macOS 14+） | 连接/认证/唯一安装 ID、SSE 作用域精准刷新 + 5 分钟核对、按消息 ID 粒度锁、连续消息历史、`NSCache` 50 MB 内存预览缓存、磁盘临时文件流式上传进度与取消、文件中心、TOTP `otpauth://` 跳转与密钥复制、SHA-256 校验数据库备份导出 | GitHub Releases 未签名包 `SyncBox-iOS-<tag>-unsigned.ipa`、`SyncBox-macOS-<tag>.zip`（真机安装需自备 Team 重签名） | GitHub Actions `macos-15`（`./scripts/apple-check.sh`：SwiftPM `SyncBoxCore` 测试、macOS 与 iOS Simulator 构建）；代码改动后将在 macOS CI 验证 |

文档总览与导航见 [SyncBox 文档索引](SyncBox文档.md)。

## 同步、安全与附件说明

- **实时同步**：全端使用带 Bearer 鉴权的 `GET /api/v1/events` SSE 长连接，按 `scope`、`conversationId`、`messageId` 合并路由变更并做 5 分钟区间核对；断线自动退避重连，Web/原生均区分“实时同步”与“定时同步”/“连接中断”状态，SSE 心跳同步续期设备在线状态，登出/删设备/改 2FA 会主动断开旧连接。详见 [同步事件影响矩阵](docs/architecture/sync-event-matrix.md)。
- **附件与缓存**：三端统一支持通用多附件收发（1–5 个、合计 ≤ 20 MiB）与旧单图片接口兼容；文件名保留、服务端信号量限制图片预览并发，文件中心通过 `category=image|file` 统合展示新旧图片和文件。三端图片与预览缓存严格限制在内存（≤ 50 MB）并按 `origin + token` 隔离，不落盘，退出登录或删除后立即清除。
- **备份、安全与凭据**：Web 会话令牌保存在 `sessionStorage`，桌面端持久化连接配置，原生端各自使用系统安全存储或受限沙箱文件保存会话；公开/敏感安全接口与备份接口均带速率限制（`SecurityRateLimitService` + `@Throttle` + 备份单飞保护），备份响应附带 `X-SyncBox-Backup-SHA256` 校验摘要。

## 客户端开发说明

- **Apple 客户端**：使用 `open frontend/apple/SyncBox.xcodeproj` 或运行 `./scripts/apple-check.sh`，详细架构与认证/测试说明见 [Apple 开发说明](frontend/apple/README.md)。
- **Flutter 客户端**：源码位于 `frontend/flutter/`，跨平台检查脚本为 `scripts/flutter-check.sh` / `scripts/flutter-check.ps1`，详细说明见 [Flutter 开发说明](frontend/flutter/README.md)。
- **Web 客户端**：详见 [Web 开发说明](frontend/web/README.md)；接口说明见 [API 文档](docs/api/README.md)。
