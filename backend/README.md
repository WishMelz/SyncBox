# SyncBox 后端

技术栈：NestJS 12 + TypeScript + TypeORM 1 + SQLite（better-sqlite3）。使用 Node.js 24，通过仓库根目录 npm workspaces 管理依赖。

## 开发

在仓库根目录执行：

```sh
npm ci
cp backend/.env.example backend/.env
npm run dev:backend
```

默认监听 `http://127.0.0.1:3000`；接口为 `GET /api/v1/health`。

```sh
curl http://127.0.0.1:3000/api/v1/health
npm test
npm run build -w @syncbox/backend
npm start -w @syncbox/backend
```

## 结构

- `src/main.ts`：服务入口与启动配置。
- `src/app.module.ts`：根模块。
- `src/app.setup.ts`：统一 API 前缀、DTO 校验与退出钩子。
- `src/config/`：环境变量校验。
- `src/database/`：SQLite / TypeORM 连接配置。
- `src/modules/health/`：健康检查模块，会实际执行数据库查询。
- `tests/`：HTTP 集成测试和数据库持久化验证，使用临时数据库。
- `src/database/migrations/`：版本化迁移，启动自动执行，创建用户、会话、设备与消息表。

业务功能按 `src/modules/<feature>/` 组织 Controller、Service 和 DTO。当前模块通过 DatabaseService 执行参数化 SQL，表结构由 TypeORM migrations 管理；需要实体时可在同一迁移体系中扩展。

## 数据库与配置

`DATABASE_PATH` 默认为 `./data/syncbox.sqlite`，相对后端进程工作目录解析。通过 workspace 脚本启动时位于 `backend/data/`；首次启动自动创建目录和数据库文件。支持 `:memory:` 用于测试。

连接启用 WAL、外键与 5 秒 busy timeout。`synchronize` 关闭。版本化迁移随启动运行，已执行记录保存在 migrations 表。后续修改通过新迁移演进，不修改旧迁移。SQLite 单连接应用查询通过 DatabaseService 串行调度，避免并发事务相互干扰。

`PORT` 默认为 3000，`HOST` 默认为 127.0.0.1。环境变量无效时启动失败。凭据不要提交到仓库。

前端开发通过 Vite 同域代理访问 API，因此默认不开放跨域。生产环境应让 Web 与 `/api` 共用域名；若改为跨域部署，再配置准确的允许来源。

## Docker

从仓库根目录运行：

```sh
docker compose -f infra/docker/compose.yaml up --build -d
```

SQLite 存储在 `syncbox-data` 命名卷。Docker 构建会先编译 Web，再由同一个 NestJS 进程提供 API 和静态页面，访问 http://127.0.0.1:8080。部署时只需调整 `SYNCBOX_PORT`（例如 `SYNCBOX_PORT=16384 docker compose -f infra/docker/compose.yaml up --build -d`）。对外发布时应在入口配置 HTTPS。

## 业务接口

已实现首次设置/登录、会话撤销、设备登记与移除、多设备共享消息、列表/详情/搜索、已读/收藏和删除。详见 [接口文档](../docs/api/README.md)。没有预置账号，首次访问设置唯一用户名和密码。

## 通用附件

会话支持一次发送 1–5 个附件，总大小最多 20 MiB，原文件完整保存在 SQLite；可解码图片生成独立缩略图，其他文件通过鉴权下载。使用迁移 `1794000000005-attachments`，无需新增文件目录。接口、字段和下载约束见 [API 文档](../docs/api/README.md#通用附件web-优先)。反向代理请求体上限须至少 21 MiB，以容纳 multipart 开销。

## 设置与安全

Web 设置面板已接入 `/settings`：可配置闲置文件清理（默认关闭，1–3650 天，后台每 10 分钟检查），可启用 RFC 6238 TOTP 两步认证，也可在密码及动态码确认后删除全部运行数据并回到首次设置状态。TOTP 密钥使用密码派生 AES-GCM 加密保存，恢复码仅保存哈希。删除附件后会保留消息和附件名称元数据并标记为已清理；SQLite 会尝试回收 BLOB 空间。
