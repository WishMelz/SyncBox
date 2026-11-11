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

从仓库根目录构建并启动单个镜像：

```sh
docker build -t syncbox:latest .
docker run -d --name syncbox \
  -p 8080:3000 \
  -v syncbox-data:/app/backend/data \
  syncbox:latest
```

也可以使用 Compose，`SYNCBOX_PORT` 只调整宿主机端口：

```sh
SYNCBOX_PORT=8080 docker compose -f infra/docker/compose.yaml up --build -d
```

访问 `http://127.0.0.1:8080/`，健康检查为 `/api/v1/health`。SQLite 数据保存在 `syncbox-data` 命名卷。

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

## Apple 客户端

```sh
open frontend/apple/SyncBox.xcodeproj
```

支持 iOS / iPadOS 17、macOS 14 及以上。已实现原生服务连接、首次设置/登录、共享会话、消息发送/搜索/复制/收藏和设备列表；登录后记住设备并自动恢复会话，不保存密码、不使用钥匙串，前台每 5 秒同步。真机运行需配置签名 Team。详见 [Apple 开发说明](frontend/apple/README.md)，验证脚本为 `scripts/apple-check.sh`。

## 当前范围

已提供响应式工作台、首次设置/登录与会话接口、设备管理、多设备共享消息的增删改查/搜索接口，以及单镜像部署配置。Web 已接入会话与消息页面；已支持图片消息；Web 已支持通用附件上传和设置面板；WebSocket 实时推送尚未实现。原 `SyncBox文档.md` 保留，当前为空。

## 会话工作空间

Web 已提供首次设置和登录、会话创建/重命名/删除、消息发送、搜索、复制、收藏及设备列表。手机单栏、PC 双栏。每 5 秒自动读取同账号其他设备的新内容，所有请求通过同域 /api 代理。会话删除会连同消息永久删除，界面提供确认。登录凭证只保存在当前标签页 sessionStorage，Web 设备 ID 由后端按浏览器指纹匹配，localStorage 只缓存升级提示；退出会撤销当前会话。

## Android / Windows 客户端

Flutter 框架位于 `frontend/flutter/`，支持连接私人后端、唯一账号首次设置/登录、会话与消息收发。运行前安装 Flutter 和对应平台工具链。详细目录、启动、打包步骤及已验证范围见 [Flutter 开发说明](frontend/flutter/README.md)。跨平台检查脚本为 `scripts/flutter-check.sh` / `scripts/flutter-check.ps1`。

## 图片消息

Web 现已使用通用附件接口，支持选择图片及其他文件、粘贴图片、拖入文件、发送前预览/移除、上传进度、文件名搜索和原文件下载；每条最多 5 个附件，合计最多 20 MiB。原文件及独立图片预览存储在 SQLite，读取需要登录。

Apple / Flutter 当前继续使用旧单图片接口（单张最多 8 MiB，后端转 WebP），历史图片仍可读取。本阶段优先完善 Web，其他端通用附件收发与下载待后续同步；旧客户端能看到附件消息的说明或文件名摘要。原有安装包需重新构建才能使用已实现的 App 新功能。
