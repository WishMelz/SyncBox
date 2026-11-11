# 附件名称与图片滚动修复（2026-11-10）

## 修复内容

- 后端下载响应使用保存的文件名作为 `filename*`，ASCII fallback 改为 `download`，不再固定返回 `attachment`。
- Flutter、Web、Apple 上传时同时发送 UTF-8 `names` 字段和真实 multipart 文件名。`names` 继续作为规范值，真实 multipart 文件名兼容尚未升级的私有部署。
- Flutter 消息卡片在图片或附件预览异步加载完成后通知消息流。用户原本位于底部时，消息流重新跟随到底部；用户正在浏览历史时保持当前位置。

## 验证

- 后端 20 项测试通过，包含多附件原始名称、下载响应、文件名搜索和权限校验。
- Flutter 全部 46 项测试通过，新增 multipart 文件名回归测试；静态检查无 error，已有两条花括号风格 info。
- Web TypeScript 检查和生产构建通过。
- Apple iOS Simulator 构建通过。

## 交付影响

- 现有已保存为 `attachment` 的历史文件无法从内容中推断原始名称，继续显示原记录名称；新上传文件会保留选择时的名称。
- 发送失败仍保留附件草稿，由用户手动重试，不增加自动补发流程。
