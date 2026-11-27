# SyncBox 同步事件影响矩阵（三端统一规范）

> 对应优化计划 **P1-1**。所有端（Web、Flutter、Apple）按同一规则处理服务端下发的 `event: sync` 失效通知与断线补偿。

## 1. 事件载荷约定

服务端通过 `GET /api/v1/events` 下发如下 JSON：

```json
{
  "type": "invalidate",
  "scope": "conversations | messages | favorites | devices | settings",
  "conversationId": "optional-uuid",
  "messageId": "optional-uuid",
  "at": 1730000000000
}
```

- 事件总线**不持久化历史、不重放**；仅用于在线实时通知。
- 客户端收到 150 ms 窗口内的突发事件时，保留 `{ scopes, conversationIds, messageIdsByConversation, hasWildcardMessageEvent }` 并去重合并后一次路由，避免漏掉精确 `conversationId` 或 `messageId`。

## 2. 操作 → 事件 → 视图影响矩阵

| 操作 | 服务端发布的 SSE 事件 | 会话列表 | 当前会话历史 | 收藏视图（若打开） | 文件视图（若打开） | 设备视图（若打开） | 设置视图（若打开） | 在线更新策略 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 发送文字 / 图片 / 附件消息 | `messages(conversationId, messageId)` + `conversations(conversationId)` | 刷新 | 仅当 `conversationId == selectedId` 时更新 | — | 刷新 | — | — | `GET /messages/:messageId` 局部 upsert（若失败或跨页则 `refreshLatest()`） |
| 编辑消息正文 / 标题 | `messages(conversationId, messageId)` + `conversations(conversationId)` +（若已收藏）`favorites(conversationId, messageId)` | 刷新 | 仅当 `conversationId == selectedId` 时更新 | 刷新 | — | — | — | `GET /messages/:messageId` 局部替换；无关会话 0 次历史请求 |
| 修改消息批注 / 收藏状态 | `messages(conversationId, messageId)` +（涉及收藏时）`favorites(conversationId, messageId)` | — | 仅当 `conversationId == selectedId` 时更新 | 刷新 | — | — | — | `GET /messages/:messageId` 局部替换 |
| 标记单条消息已读 | `messages(conversationId, messageId)` + `conversations(conversationId)` | 刷新 | 仅当 `conversationId == selectedId` 时更新 | — | — | — | — | `GET /messages/:messageId` 局部替换 |
| 整会话标记已读（存在未读时） | `conversations(conversationId)` + `messages(conversationId)` | 刷新 | 仅当 `conversationId == selectedId` 时更新 | — | — | — | — | `refreshLatest()`（仅拉最新一页） |
| 删除整条消息 | `messages(conversationId, messageId)` + `conversations(conversationId)` + `favorites(conversationId, messageId)` | 刷新 | 仅当 `conversationId == selectedId` 时移除 | 刷新 | 刷新 | — | — | `GET /messages/:messageId` 返回 404 时本地直接移除该条目 |
| 删除单个附件 / 旧图片 | `messages(conversationId, messageId)` + `conversations(conversationId)` + `favorites(conversationId, messageId)` | 刷新 | 仅当 `conversationId == selectedId` 时更新 | 刷新 | 刷新 | — | — | `GET /messages/:messageId` 局部替换；同步失效本地对应图片内存缓存 |
| 自动清理闲置附件 / 旧图片 | `settings` + `favorites` + 每个受影响会话的 `messages(conversationId)` 与 `conversations(conversationId)` | 刷新 | 仅当 `conversationId == selectedId` 时更新 | 刷新 | 刷新 | — | 刷新 | `refreshLatest()` |
| 创建 / 重命名 / 置顶会话 | `conversations(conversationId)` | 刷新 | — | — | — | — | — | 仅刷新会话列表，不拉当前会话历史 |
| 删除会话 | `conversations(conversationId)` + `messages(conversationId)` + `favorites(conversationId)` | 刷新 | 若 `conversationId == selectedId` 清空当前选中会话 | 刷新 | 刷新 | — | — | 列表刷新后若当前会话已不存在则清空选中状态 |
| 设备登记 / 重命名 / 移除 | `devices`（移除设备时立即断开被移除设备的 SSE 流） | — | — | — | — | 刷新 | 若为当前设备则同步更新名称 | 仅在设备/设置弹窗打开时拉取 `/devices` |
| 修改清理设置 / 开关两步认证 | `settings`（开关 2FA 时立即断开其他设备 SSE 流） | — | — | — | — | — | 刷新 | 仅在设置页打开时拉取 `/settings` |
| SSE 重连 / 切回前台 / 5 分钟低频校对 | — | 刷新 | 若有选中会话则执行区间核对 | 若打开则刷新 | 若打开则刷新 | 若打开则刷新 | 若打开则刷新 | `MessageHistory.reconcile()`（即带 `since` 的完整已加载区间核对） |

## 3. 在线补拉 vs 断线区间核对

1. **在线常规路径（`refreshLatest()` / 单条 `GET /messages/:id`）**：
   - 当会话已加载 300 条历史消息且处于非搜索状态时，收到 `1–3` 条精确 `messageId` 的在线事件仅请求对应 `GET /messages/:id` 局部替换（404 则删除）；收到无 `messageId` 的 `messages` 或同会话 `conversations` 事件时，仅调用 `refreshLatest()` 拉取最新 1 页并更新最新区间，**不重拉更早的历史分页**。
   - **无关会话的历史请求严格为 0**；关闭状态的收藏/文件/设备面板不因远端事件额外请求接口。
2. **离线补偿路径（`reconcile()` / `refresh()`）**：
   - 仅在 **SSE 断线重连后**、**应用/标签页从后台切回前台**、**手动点击刷新** 或 **低频兜底校对（5 分钟）** 时执行带 `since = oldestLoadedCursor` 的全段核对，确保断线期间的旧消息编辑、跨页删除和状态变化最终与服务端一致。
3. **心跳超时与轮询退避**：
   - 服务端每 `20s` 发送 `: heartbeat\n\n`（每 3 次约 `60s` 复核会话有效性并续期 `devices.last_seen_at`）。
   - 三端读取 SSE 流均设 `45s` 无数据超时；超时立即断开并按 `3s -> 6s -> 12s -> 24s -> 30s` 指数退避重连。
   - SSE 健康连接时三端轮询统一放宽（`30s–60s`），仅作极端网络异常兜底；SSE 断开时切回 `5s` 快速轮询（macOS 桌面后台 `15s`）。
