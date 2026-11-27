# SyncBox 数据库备份与恢复演练手册

> 适用于单卷 SQLite 部署（Docker Compose 与本地单进程部署）。**严禁直接覆盖正在运行实例的生产数据卷，请先保留当前数据卷完整副本。**

## 1. 备份特性与边界

- 接口：`GET /api/v1/settings/backup`（需要已登录 Bearer Token；同时受速率限制，同一时间仅允许 1 个快照生成，并发请求返回 `429`）。
- 实现：在 SQLite 序列化队列中执行 `VACUUM INTO '<temp-sqlite>'`，生成包含当前 WAL 状态的一致性完整快照，并计算 `X-SyncBox-Backup-SHA256` 响应头。
- 隐私与权限：快照包含单用户账号凭证哈希、2FA 加密密钥、会话、设备、全部消息与附件 BLOB，请妥善加密保存，勿上传至公开位置。
- 容量提示：生成快照需要与当前数据库有效数据相当的临时磁盘空间（位于 `$DATABASE_PATH` 同级 `backups/` 目录，流式下载关闭后自动删除临时文件）。

## 2. 恢复标准步骤（先在副本卷演练）

1. **停止后端服务**（禁止热替换运行中的 SQLite 文件）：
   ```bash
   docker compose -f infra/docker/compose.yaml stop syncbox
   ```
2. **保留现有数据卷副本**：
   将原数据目录中的 `syncbox.sqlite`、`syncbox.sqlite-wal`、`syncbox.sqlite-shm` 整体复制到安全备份目录。
3. **校验待恢复快照完整性与摘要**：
   ```bash
   sha256sum syncbox-backup.sqlite
   sqlite3 syncbox-backup.sqlite "PRAGMA integrity_check;"
   ```
   确认 SHA-256 与下载时记录的 `X-SyncBox-Backup-SHA256` 一致，且 `PRAGMA integrity_check` 返回 `ok`。
4. **替换主库并清理旧 WAL/SHM 伴随文件**：
   - 将目标目录中的 `syncbox.sqlite`、`syncbox.sqlite-wal`、`syncbox.sqlite-shm` 移走或删除；**切勿将旧 `-wal` / `-shm` 留给恢复后的快照**。
   - 将校验通过的 `syncbox-backup.sqlite` 复制为 `syncbox.sqlite`（权限建议 `0600`）。
5. **启动服务并逐项核验**：
   - 使用与备份兼容或更新版本的 SyncBox 启动服务（注意：SQLite schema 迁移在启动时自动执行且不可回退，禁止用更低版本镜像直接读取高版本库）。
   - 验证 `/api/v1/health` 返回 `{"status":"ok","database":"up"}`。
   - 登录账号（若备份前开启了 2FA，需使用备份时对应的动态码/恢复码）；注意备份中在快照时刻之后产生的新会话不在快照内，需要重新登录。
   - 抽样核对会话列表、消息正文、批注、收藏，以及旧图片与附件下载/预览的字节完整性。
