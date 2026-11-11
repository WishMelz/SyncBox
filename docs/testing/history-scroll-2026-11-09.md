# 连续历史消息验证（2026-11-09）

## 交互

- 会话首次读取最新 30 条，向上滚动继续读取更早消息；搜索结果沿用同样逻辑。
- 历史加载与实时刷新串行处理，按消息 ID 去重。插入新消息、删除游标消息不会打乱读取位置。
- 加载失败保留已显示的内容，在顶部点击重试。发送失败仍由用户手动重发。
- 新消息在原本位于底部时跟随，翻阅历史时保持位置。主动发送和“回到底部”定位到最新消息。
- 客户端内存最多保留 20 个会话/搜索窗口的位置；页面重载、应用重启后从最新消息打开。
- 会话列表和收藏列表保留原有分页。

## 自动验证

测试接口使用 Mock HTTP 或独立内存数据库，不创建或删除个人数据库中的测试消息。

| 范围 | 结果 |
| --- | --- |
| 后端全部测试 | 20 项通过，包含游标排序、同时间戳顺序、新增/删除、范围刷新、旧分页、搜索、鉴权及错误参数 |
| Web 纯逻辑测试 | 19 项通过，包含窗口合并、失败保留、重复请求、刷新串行及发送结果合并 |
| Web 连续加载浏览器测试 | 1280px、390px 通过；可变高度、加载前后内容位置、切换会话恢复、实时消息、手动重试、搜索高亮、搜索中发送回到最新 |
| Web TG 交互回归 | 1280px、913px、390px 布局，消息菜单、日期、图片预览与搜索高亮通过 |
| Web 发送回归 | 手机/PC 失败保留、手动重发、发送中切换会话、附件重试与取消通过 |
| Apple 核心测试 | 26 项通过；1 项需要独立测试服务器的真实 API 联调跳过 |
| Flutter 全部测试 | 43 项通过；包含 390px、1280px 慢加载内容锚点、实时消息、位置恢复及手动重试 |
| 构建 | 后端、Web、macOS、iOS Simulator、Android Debug 通过 |
| Web 反向代理 | `/api/v1/health` 返回后端及数据库正常 |

入口：`backend/tests/history-cursor.test.cjs`、`frontend/web/tests/message-history.test.mjs`、`frontend/web/tests/history-scroll.browser.mjs`、`frontend/apple/Tests/MessageHistoryTests.swift`、`frontend/flutter/test/message_history_test.dart`、`frontend/flutter/test/history_scroll_test.dart`。

## 验证范围

Apple 已通过核心逻辑测试和两平台编译，SwiftUI 使用稳定消息 ID 恢复阅读位置；真机触摸滚动、图片解码后高度变化仍需设备验收。Windows 与 Android 共用 Flutter 实现，Windows 原生 Runner 需在 Windows 主机编译验证。本轮未导出发布版安装包。

Flutter 静态分析没有错误或警告，现存 5 条其他文件的括号风格提示未在本轮处理。Web 构建保留大于 500 kB 的既有分包提示。
