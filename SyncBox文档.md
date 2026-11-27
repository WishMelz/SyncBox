# SyncBox 文档索引

本文件作为仓库内所有工程、架构、接口与端侧开发文档的统一导航入口：

## 概览与部署

- [项目主 README](README.md)：快速启动、统一多端能力与交付矩阵、Docker 直连与反向代理部署拓扑。
- [数据库备份与恢复演练指南](docs/backup-restore.md)：SQLite 在线一致性快照下载、SHA-256 校验与停服恢复/抽样验收步骤。
- [GitHub 发布说明](docs/github-release.md)：Docker Hub 镜像与 GitHub Releases 多平台产物自动发布说明。

## 架构与接口契约

- [API 接口文档](docs/api/README.md)：全量路由语义、鉴权与限流策略、文件中心、连续游标分页与 SSE 事件流。
- [同步事件影响矩阵](docs/architecture/sync-event-matrix.md)：服务端 SSE `invalidate` 事件作用域（`conversations`、`messages`、`favorites`、`devices`、`settings`）与三端统一刷新策略。
- [OpenAPI 规范](shared/contracts/openapi.yaml)：41 个后端路由的机器可读契约（由 `npm run check:openapi` 与控制器装饰器自动对齐校验）。

## 模块文档

- [后端开发说明](backend/README.md)
- [Web 前端说明](frontend/web/README.md)
- [Flutter 客户端说明（Android / Windows）](frontend/flutter/README.md)
- [Apple 客户端说明（iOS / iPadOS / macOS）](frontend/apple/README.md)
