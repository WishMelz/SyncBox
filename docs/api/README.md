# SyncBox API

基础路径 `/api/v1`，JSON 请求与响应。Web 始终使用同域相对地址，由 Vite（开发）或 Nginx（生产）代理。

## 账号与设备

| 方法 | 路径 | 用途 |
| --- | --- | --- |
| GET | /auth/status | 返回 `{initialized}`，决定显示首次设置还是登录 |
| POST | /auth/setup | 首次设置：`{username,password}`，仅允许成功一次，返回会话 |
| POST | /auth/login | 登录：`{username,password}` |
| GET | /auth/me | 当前用户，包括当前会话绑定的 deviceId |
| POST | /auth/logout | 撤销当前凭证，返回 204 |
| POST | /devices | 登记并绑定当前会话：`{name,platform,id?}` |
| GET | /devices | 当前账号设备列表 |
| POST | /devices/heartbeat | 更新当前设备活动时间，返回 204 |
| DELETE | /devices/:id | 移除设备并撤销该设备所有会话，返回 204 |
| GET | /settings/backup | 下载当前 SQLite 一致性快照（需要 Bearer 鉴权） |

状态查询、首次设置和登录之外均需要 `Authorization: Bearer <accessToken>`。登录响应为 `{accessToken,tokenType:"Bearer",expiresIn:604800,user}`。凭证有效期 7 天，数据库只保存 SHA-256 摘要；密码使用随机盐 scrypt，不存明文。生产必须通过 HTTPS 访问，客户端应安全保存凭证；不提供默认账号。

用户名去除首尾空白并转小写，1–254 字符，不允许内部空白或控制字符；密码 6–128 字符。设备 platform 为 `ios/ipados/macos/web/android/windows/linux/other`；首次登记不传 id，重新登录后可传之前登记的设备 id 重新绑定。设备 id 必须属于当前账号。删除设备保留已发送消息及设备名称快照。设备列表返回 `online` 和 `lastSeenAt`；最近 90 秒内有请求或心跳视为在线。客户端在前台定期调用心跳，进入后台后停止。

每个设备独立登录并登记后，使用 `POST /messages` 创建即发送到当前账号的共享消息列表。其他设备登录同一账号即可读取。工作台使用 `GET /events` 的 SSE 变化通知，并继续通过分页接口读取数据；断线时客户端回退到定时拉取。SSE 必须携带 `Authorization: Bearer <accessToken>`，事件只包含失效范围和资源 ID，不包含消息正文。未登记设备也允许发消息，senderDevice 为 null。已读和收藏在同一账号内共享。

## 消息

| 方法 | 路径 | 用途 |
| --- | --- | --- |
| POST | /messages | 创建/发送消息 |
| GET | /messages | 分页、搜索和筛选 |
| GET | /messages/files | 集中分页查看图片和附件 |
| GET | /messages/:id | 消息详情（不会自动标记已读） |
| PATCH | /messages/:id | 更新标题、正文、已读或收藏 |
| DELETE | /messages/:id | 永久删除当前账号的消息，返回 204 |

发送请求：

```json
{"title":"来自 iPhone 的消息","content":"需要在 Mac 上处理的内容","source":"manual","clientId":"可选 UUID"}
```

标题 1–200 字符，正文 1–50000 字符；source 可选，默认 manual，最长 80 字符。`clientId` 为客户端生成的 UUID；网络超时后用同一值重试只会创建一条消息。正文作为纯文本处理，前端不得直接渲染为 HTML。

详情返回 `id,title,content,source,isRead,isStarred,createdAt,updatedAt,senderDevice`；senderDevice 为 `{id,name,platform}` 或 null。删除设备后保留 name/platform，id 为 null。客户端不能指定其他用户或伪造发送设备字段。

列表查询使用 FTS5 索引搜索正文、批注、标题和附件文件名；包含 `%` 或 `_` 的特殊查询会自动回退到转义后的 `LIKE`。列表仍保留服务端分页，当前页大小最多 100。个人部署可从设置下载 SQLite 备份；备份前会同步 WAL，响应附带 `X-SyncBox-Backup-SHA256`、大小和生成时间，Web 端下载后会校验摘要，最多保留最近 10 个临时快照，下载完成后服务器会删除临时文件。

列表查询示例：

```text
/api/v1/messages?q=关键词&page=1&pageSize=20&isRead=false&isStarred=true&source=manual
```

- page 默认 1，pageSize 默认 20、最大 100。
- q 搜索标题、正文和附件文件名，最长 200 字符，支持中文子串；SQLite LIKE 对 ASCII 大小写不敏感，非 ASCII 不做语言折叠。
- `%`、`_`、反斜杠作为普通字符，所有输入参数化查询。
- isRead/isStarred 查询值必须为字符串 true/false，可省略；多个过滤条件取交集。
- 排序为创建时间倒序，再按 id 倒序。返回 `{items,total,page,pageSize,totalPages}`，items 使用 preview（最多 160 个 Unicode 字符）代替正文。空列表 totalPages 为 0。

更新请求例如 `{"isRead":true,"isStarred":true}`，也支持 title/content，至少一个字段。未知字段、null、错误类型均拒绝。

## 状态码与限流

200 成功；201 创建；204 退出或删除；400 参数错误；401 未登录/凭证过期；404 不存在或不属于当前账号；409 初始化已完成；429 请求过频；503 健康检查发现数据库不可用。

默认每个路由每 IP 每分钟 120 次；首次设置 5 次、登录 10 次。限流存储在单进程内存，重启会清空。反向代理必须覆盖 X-Forwarded-For；仅在后端不能被直接访问且位于单层可信代理后时开启 TRUST_PROXY=true。

`GET /health` 无需登录，返回 `{status:"ok",service:"syncbox-backend",database:"up"}`。

## Web 调用

已在 `frontend/web/src/services/` 提供 api/auth/messages/devices 的 TypeScript 封装，统一走 `/api/v1`。已提供首次设置、登录和共享会话工作空间页面。

## 会话 API（Web 当前使用）

| 方法 | 路径 | 请求/用途 |
| --- | --- | --- |
| POST | /conversations | `{title}`，创建会话，标题 1–80 字符 |
| GET | /conversations | `q,page,pageSize`，搜索标题、会话内正文及附件文件名，按最近活动倒序 |
| PATCH | /conversations/:id/read | 将当前会话消息标记为已读，返回 204 |
| GET | /conversations/:id | 会话详情 |
| PATCH | /conversations/:id | `{title}`，重命名 |
| DELETE | /conversations/:id | 删除会话及其中消息，返回 204 |
| GET | /conversations/:id/messages | `q,page,pageSize`，分页消息历史，返回完整 content；新消息在前 |
| POST | /conversations/:id/messages | `{content,clientId?}`，发送文本/链接，记录当前会话绑定的设备 |

上述接口均要求 Bearer 鉴权，跨账号请求返回 404。分页使用 `{items,total,page,pageSize,totalPages}`，每页默认 20，最大 100。会话列表项包括 messageCount、unreadCount 和 preview；打开会话后客户端应调用标记已读接口。消息增加 conversationId。

迁移将旧消息按账号归入“历史消息”会话；旧 `POST /messages` 兼容保留，创建的消息自动进入“临时传输”。Web 使用 SSE 变化通知并在断线时回退到轮询。发送失败保留当前页面内的会话草稿及附件，由用户手动再次发送；恢复网络和刷新列表不会自动补发。

## 单用户初始化

一个部署仅有一个账号。Web 首次访问先读取 /auth/status，未初始化时显示用户名、密码和确认密码，完成后自动登录。之后只显示登录。/auth/register 已移除。并发初始化最多一个成功，其他返回 409；数据库常量唯一索引也阻止插入第二个用户。

升级已有单账号数据库会保留全部数据，以原邮箱作为用户名继续登录。已有多个账号时迁移会停止并报告错误，不自动删除、合并或挑选账号；须先备份并处理旧账号。初始化状态随 SQLite 数据卷持久保存，正常退出或重启不会重置。

## 图片消息

- `POST /conversations/:id/images`：Bearer 鉴权，`multipart/form-data`，文件字段 `image`（一次一张），可选 `content` 文本说明，最多 50,000 字。创建成功返回普通消息对象并带 `image: {mimeType,width,height,size}`；无文字时 content 为 `[图片]`。
- `GET /messages/:id/image`：Bearer 鉴权，返回 WebP 二进制，`Cache-Control: no-store`、`X-Content-Type-Options: nosniff`。没有公共文件地址，不能把令牌放在 URL 查询参数中。
- 输入 JPEG / PNG / WebP / GIF，单文件最多 8 MiB，最多 2400 万像素；基于实际解码结果校验，拒绝 SVG/伪装文件。GIF 仅首帧。自动校正方向、去除元数据，WebP quality 90 转码（不是原图无损存档）。输出也限制 8 MiB。
- 图片上传每个 IP 每分钟最多 20 次；Nginx 请求体限制为 21 MiB（兼容通用附件及 multipart 开销），普通 JSON 请求仍为 1 MiB。
- 新迁移 `1794000000004-images` 创建 `message_images` 表，图片 BLOB 和消息同一事务写入 SQLite，消息/会话删除级联清理；已有文本消息保持兼容。备份整个 SQLite（包含 WAL 的一致性备份）即可包含图片，无额外目录或卷。
- 消息详情和分页返回 `image` 元数据（文本为 null），不会在 JSON 中返回二进制。关键词搜索说明文字，不做 OCR。

## 通用附件（Web 优先）

文件中心使用 `GET /messages/files?page=1&pageSize=30&kind=image|attachment&q=关键词`，返回当前账号下仍可访问的图片和附件元数据，并带所属会话及消息 ID。文件中心只加载元数据；预览和下载仍使用消息附件接口，点击来源可回到所属会话。闲置清理后已删除的文件不会出现在文件中心。

| 方法 | 路径 | 用途 |
| --- | --- | --- |
| POST | /conversations/:id/attachments | 多附件及可选文字，一次创建一条消息 |
| GET | /messages/:id/attachments/:attachmentId | 下载原始文件 |
| GET | /messages/:id/attachments/:attachmentId/preview | 获取图片 WebP 预览；没有预览时返回 404 |

上传使用 `multipart/form-data`，重复文件字段 `files`（1–5 个），可选 `content`（最多 50,000 字）和 `names`（与文件顺序一致的 JSON 字符串数组，用于可靠传递中文等 Unicode 文件名）。每个文件非空，文件合计最多 20 MiB；超限返回 413，参数/数量错误返回 400；所有验证成功后才事务写入消息和附件。上传每个 IP 每分钟最多 20 次。

返回消息对象新增 `attachments` 数组，每项为 `{id,name,mimeType,size,hasPreview,width,height}`；size 为原文件字节数，width/height 为预览尺寸（无预览时 null）。详情和分页只返回元数据，不返回文件二进制；无附件为 `[]`。无文字时正文为 `[附件] 文件名1、文件名2`，用于旧客户端和会话摘要。

所有接口均要求 Bearer 鉴权并校验消息归属，附件不存在或与消息不匹配时返回 404。原文件按字节完整保存，下载响应固定为 `application/octet-stream`、`Content-Disposition: attachment`（含 UTF-8 文件名）、`Cache-Control: no-store` 和 `X-Content-Type-Options: nosniff`。HTML、SVG 等仅作为下载文件，不内联执行。

实际可解码的 JPEG/PNG/WebP/GIF（最多 2400 万像素）会另生成最大 1600×1600 的 WebP 静态预览，GIF 预览取首帧；其他格式、过大或无法解码的图片仍可作为原文件下载。预览不修改原文件。文件名会去掉路径和控制字符，限制为 180 个 Unicode 字符。

迁移 `1794000000005-attachments` 创建 SQLite `message_attachments` 表，原件和预览作为 BLOB 保存，随消息/会话级联删除。一致性备份整个数据库即可包含附件。文件名支持关键词搜索（转义 LIKE 特殊字符），不读取文件正文或 OCR。旧 `/images`、`/image` 接口不变，Apple/Flutter 通用附件 UI 留待后续接入。

## 设置与数据管理

| 方法 | 路径 | 用途 |
| --- | --- | --- |
| GET | /settings | 获取清理、两步认证和存储占用状态 |
| PATCH | /settings/cleanup | `{enabled,idleDays}` 设置闲置文件清理，天数 1–3650 |
| POST | /settings/two-factor/setup | 使用当前密码生成一次性验证器绑定信息 |
| POST | /settings/two-factor/enable | `{password,code}` 验证动态码并开启两步认证 |
| POST | /settings/two-factor/disable | `{password,code}` 验证后关闭两步认证 |
| DELETE | /settings/data | `{password,code?,confirmation:"删除所有数据"}` 清空账号全部数据 |

闲置清理默认关闭。开启后，后端每 10 分钟检查一次，按照文件最近一次上传、预览或下载时间计算，删除超过 `idleDays` 的图片和附件二进制；消息文字和会话保留，附件元数据会标记为已清理。查看消息列表不会刷新访问时间。SQLite 删除 BLOB 后会尝试回收空间；备份文件不受清理影响。

两步认证使用 RFC 6238 TOTP（30 秒、6 位、SHA-1）。绑定密钥只在开启流程中返回，后端使用密码派生密钥加密保存；开启成功生成 8 个一次性恢复码，服务端只保存哈希。开启或关闭会撤销其他设备会话，动态码和恢复码均防止重复使用。登录开启两步认证后，`POST /auth/login` 需要额外 `code` 字段；缺少时返回 401 和 `code: "TWO_FACTOR_REQUIRED"`。验证器设备时间应保持准确。

删除所有数据是不可逆操作：必须已登录、验证当前密码（以及已开启时的动态码或恢复码），并精确提交确认文字 `删除所有数据`。操作会清除账号、会话、设备、会话消息、图片、附件和设置；完成后部署恢复为首次设置状态，外部备份不会被删除。


## 会话置顶、收藏与设备名称

`PATCH /conversations/:id` 支持 `{pinned:true|false}`，会话列表按置顶优先、最近活动倒序返回，并在会话对象中返回 `isPinned`。标题和置顶可以单独更新。

`GET /messages/starred?q=&page=1&pageSize=20` 返回当前账号完整的收藏消息（包括正文和附件元数据），支持正文、标题和文件名搜索；取消收藏仍使用 `PATCH /messages/:id` 的 `{isStarred:false}`。

`PATCH /devices/:id` 使用 `{name}` 修改设备名称，仅当前账号可修改自己的设备；名称 1–80 字符。设备名称会用于后续发送消息的设备快照，历史消息名称不会被改写。

## 消息批注（所有客户端共享）

每条消息保存一份可编辑批注，文字、图片和附件消息均适用。使用 `PATCH /messages/:id` 提交 `{ "annotation": "备注内容" }`；字符串最多 2000 字符，首尾空白会去除，空字符串清除批注。`null`、非字符串和超长内容返回 400。原消息正文、附件和收藏状态不受影响。接口沿用 Bearer 认证及消息归属校验。

消息详情、消息列表、会话历史和收藏列表返回 `annotation` 字符串，无批注时为 `""`。`GET /messages`、`GET /messages/starred`、`GET /conversations`、`GET /conversations/:id/messages` 的 `q` 同时匹配批注；LIKE 特殊字符按字面值查询。批注使用纯文本，不执行 HTML 或 Markdown。

迁移 `1794000000008-annotations` 添加默认空字符串的列，已有消息保留。应先升级后端，再升级客户端。各端通过现有刷新/轮询读取共享批注；同时编辑时最后成功提交的版本覆盖之前版本，当前不保留批注历史。

## 设备 ID 与浏览器绑定

Web 使用 `POST /devices` 提交 `identityMode: "fingerprint"`、`platform: "web"` 和 `fingerprint`（1–1024 字符），不再依赖随机安装标识。后端保存 SHA-256 摘要，同账号、相同指纹复用已有设备 ID 和自定义名称，并绑定当前登录会话。`identityMode` 响应值为 `fingerprint`、`installation` 或 `legacy`；`fingerprintBound` 表示已绑定指纹。响应不暴露指纹或摘要。

首次升级可以携带旧 `id`，保留原设备 ID、名称和历史；已有指纹的设备不能换绑其他指纹，冲突返回 409，Web 随后去掉旧 ID 登记。查找指纹优先于缓存 ID。新迁移 `1794000000010-browser-fingerprint` 使用独立字段及账号范围内的唯一索引，不会把旧版低区分度环境描述自动当成设备身份。事务串行处理并发登记。

Web v2 指纹包含去版本号的 User-Agent、平台、首选语言、时区、触点数、CPU 逻辑核数、排序后的屏幕尺寸、色深与可用的 WebGL 厂商/渲染器；不包含 Cookie、随机安装标识、窗口尺寸、缩放或隐私模式探测。普通/隐私窗口、清除站点数据或使用不同访问地址时，只要可观察指纹一致且连接同一后端、登录同一账号，就复用 ID。浏览器防指纹、GPU 屏蔽、显示器或系统环境变化可能产生新 ID；完全相同环境的不同物理设备可能合并，因此它不是硬件唯一标识。设备删除会撤销所有绑定该 ID 的会话。

指纹不是认证凭据：仍必须登录，继续支持密码和两步认证，匹配指纹不能继承其他窗口的登录令牌。旧 Apple/Flutter 客户端保持原协议兼容；旧 `installationId` 模式仍要求指纹与安装标识一起提交，且不按旧环境指纹合并设备。

### 原生端安装标识

Apple（iOS/iPadOS/macOS）与 Flutter（Android/Windows）提交持久 UUID `installationId`，不提交 `identityMode` 或环境 `fingerprint`。后端已有安装标识匹配协议直接复用设备记录，响应 `identityMode: "installation"`。登录、恢复登录均登记；用户自定义名称由服务端返回并同步保存。重复登录、应用重启和覆盖安装不会因为会话令牌变化而创建重复设备。清除数据/卸载/迁移备份的具体行为取决于平台存储保留情况，不保证物理硬件级唯一。


## 原生端可靠同步（2026-11-09）

文字、图片和附件的发送接口均接受可选 `clientId`（UUID）。图片 multipart 可同时提交 `content`、`clientId`；附件可同时提交 `content`、`names`、`clientId` 和最多 5 个文件。图片 8 MB、附件合计 20 MB 的限制不变。

一次发送的所有手动重试必须使用相同 `clientId` 和内容。用户更改内容、图片或附件后应生成新 ID；明确发送成功后的下一次发送也应生成新 ID。Web 和原生客户端只在当前运行会话中保存重试状态，不使用持久离线队列，也不自动补发。服务端确认发送成功后，客户端清除已提交的草稿；后续列表读取失败仅提示刷新失败，不将已发送消息恢复为草稿。

Apple 与 Flutter 使用独立的 SSE 连接，令牌通过 Authorization 请求头传递；进入后台或退出工作台立即取消连接。连接成功后补拉数据，多个通知合并刷新；连接失败时按 3–30 秒退避重连，HTTP 401 返回登录页。常态保留 30 秒校验轮询，SSE 不可用时使用 5 秒轮询。界面区分“实时同步”和“定时同步”。

当前未读状态沿用账号共享语义。读取最新消息窗口后标记已读；消息搜索及仅加载更早消息不会标记整个会话已读。Web、Apple 和 Flutter 会话列表不显示未读数字，接口字段保留兼容。

## 连续历史消息（2026-11-09）

`GET /conversations/:id/messages` 保留 `q`、`page`、`pageSize`，新增可选 `before` 和 `since`。游标为 `createdAt|id`，时间使用毫秒 UTC ISO 格式、ID 使用消息 UUID。按 `(created_at, id)` 降序稳定排序。使用任一游标时 `page` 必须为 1；错误格式返回 400，鉴权及会话归属校验保持不变。

- 首次打开：`?pageSize=30` 读取最新 30 条。
- 向上加载：将上次响应的 `nextCursor` 或已加载最旧消息的位置作为 `before`，边界排他。即使边界消息被删除也可继续读取。
- 实时刷新：用已加载最旧消息的位置作为 `since`，边界包含；有多批时保留 `since` 并循环传 `before=nextCursor`，整个范围成功后再替换。这样同步新增、删除、收藏及批注更新时不会丢失已加载的历史。

响应新增 `hasMore` 和 `nextCursor`（没有更多时为 `null`）。`hasMore` 仅表示当前游标范围是否有下一批；`total`、`totalPages` 仍为整个搜索条件的总量，不受游标影响。旧分页客户端仍可继续使用原接口。通用消息列表和收藏接口也返回这两个附加字段。

Web、Apple、Flutter 的会话消息使用连续加载；会话列表和收藏列表保留分页。最近 20 个会话/搜索视图的已加载内容和位置只保存在客户端当前运行内存中，重新加载页面或退出应用后从最新消息打开。加载历史失败时保留内容，顶部提供手动重试；不会自动补发任何消息。新消息在原本位于底部时跟随，浏览历史时保持位置，主动发送或点击“回到底部”可回到最新。
