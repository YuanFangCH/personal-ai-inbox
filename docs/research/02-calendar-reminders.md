# 个人 AI 信息收集系统：事项写入日历、到点提醒、三端同步调研

检索日期：2026-10-03  
目标环境：荣耀 Android 手机、三星 Galaxy Tab S7 FE、Windows 11 多台、自有公网 IPv6 服务器。  
结论口径：本文把官方文档、协议规范、项目仓库中直接写明的内容标为【事实】；把基于这些事实给出的工程选择、风险和落地建议标为【判断】。

> **适用范围说明**：本文撰写于 v1.0 的“服务器中心”架构，CalDAV/Nextcloud 在 v2.1 中已降级为可选镜像，日历与待办由 App 自带。结论请以 [个人 AI 收件箱与提醒系统：可执行方案](../personal-ai-inbox-executable-plan.md) 为准；本文的官方资料与能力边界仍然有效。

## 0. 结论先行

【判断】推荐主路线：

1. 权威数据源：自建 Nextcloud Calendar + Tasks，统一使用 CalDAV/VTODO。
2. Android：两台设备安装 DAVx⁵，把 CalDAV 日历和 VTODO 任务映射进 Android Calendar Provider；事件展示用 Etar 或系统日历，任务展示与提醒用 Tasks.org。
3. Windows：Thunderbird 桌面版作为首选 CalDAV 客户端；若必须留在 Outlook/Exchange 工作流，使用 Outlook CalDav Synchronizer，而不是假设新版 Outlook 原生支持任意 CalDAV。
4. 提醒：不能只靠 CalDAV。服务端另建独立提醒调度器，针对关键事项向 ntfy 自建实例或 Telegram Bot、企业微信、飞书推送；Android 用 ntfy F-Droid 版的前台服务保证 Doze 下即时送达，Windows 用原生聊天/协作客户端保证通知体验。
5. 网络：不要只发布 AAAA。优先在公网 IPv4+IPv6 反向代理或隧道前门后面挂 IPv6-only 源站；若短期只能 IPv6-only，要明确接受部分蜂窝网络和 Windows 网络无法直连的风险。

【判断】备选路线：

1. 有 GMS 且接受 Google 生态：Google Calendar API 写事件，Android 由 Google Calendar App 负责本机提醒，Windows 用 Google Calendar Web/PWA 或 Outlook/Thunderbird；服务端仍应维护自己的提醒任务表，因为 Google push 官方明确说明会丢少量消息。
2. 已有 Microsoft 365/Outlook 生态：Microsoft Graph 写事件，Windows Outlook 原生提醒；适合工作场景，但 OAuth 权限、管理员同意、订阅过期和节流规则需要工程化处理。
3. 极简自建：Radicale 或 Baikal 只做日历/任务服务器，Android 继续 DAVx⁵，Windows 继续 Thunderbird，提醒由 ntfy 单点补齐。

【判断】最关键的风险排序：

1. 只发 AAAA 导致 IPv4-only 蜂窝/宽带访问失败。
2. 把 CalDAV 同步成功误当成“到点必定响铃”。
3. Android OEM 省电策略杀掉 DAVx⁵、Tasks.org、ntfy/Gotify 后台进程。
4. Windows 端只有 Web UI 或只在客户端运行时提醒，关机/休眠/未开浏览器时漏报。
5. Google/Microsoft 的 OAuth 授权、配额、push 订阅寿命和通知延迟。
6. AI 写入错误、重复写入、误删，或把私密内容推送到第三方聊天平台。

## 1. 总体架构建议

【判断】推荐把系统拆成两条互不依赖的链路：

```text
AI 解析结果
  -> 审核/去重队列
  -> 日历写入器
       -> CalDAV 服务器（Nextcloud/Radicale/Baikal）
       -> 或 Google Calendar API
       -> 或 Microsoft Graph

同一事项
  -> 提醒调度器（服务端数据库中的独立 job）
       -> Android/iOS/Windows 通知通道
       -> ntfy / Telegram / 企业微信 / 飞书 / Email
```

【判断】日历写入链解决“事项在哪里、三端看得到、可修改”。提醒链解决“到点叫人”。两条链必须共享同一个事项 ID，但状态分离：日历同步失败不能阻止提醒，提醒通道失败也不能只靠日历补偿。

【判断】如果 AI 自动写入生产日历，建议至少做：

- 专用日历账户或专用日历集合，例如“AI 收集”。
- 写入前区分“已确认”和“待确认”；高风险事项默认只创建待办，不直接改已有日程。
- 使用稳定 UID/transactionId 防重复；记录源消息、写入结果、ETag/事件 ID。
- 删除和改期只允许操作本系统创建的日历项；不碰用户手写日程。
- 私密事项推送到外部聊天工具时用中性标题，不发送正文、地点、参会人。

## 2. CalDAV/VTODO 路线

### 2.1 协议事实

【事实】RFC 4791 定义 CalDAV 是 WebDAV 的日历扩展，用于访问、管理和共享基于 iCalendar 的日历与调度信息，并定义 “calendar-access” 能力。来源：[RFC 4791](https://www.rfc-editor.org/rfc/rfc4791.txt)。

【事实】RFC 5545 定义 iCalendar 数据格式，覆盖事件、待办、日记、忙闲信息；VTODO 是标准组件。来源：[RFC 5545](https://www.rfc-editor.org/rfc/rfc5545.txt)。

【事实】RFC 6638 定义 CalDAV 调度扩展 “calendar-auto-schedule”，用于邀请、参会人状态、调度收件箱等。来源：[RFC 6638](https://www.rfc-editor.org/rfc/rfc6638.txt)。

【判断】VTODO 天然适合“AI 解析出的事项”，但不同服务器/客户端对子任务、提醒、完成状态、重复任务的支持并不完全一致。工程上应把标题、开始/截止时间、提醒、状态、备注作为最小公共字段，其他字段视为增强能力。

### 2.2 服务端比较

| 方案 | 官方定位 | 优点 | 主要限制 | 适合度 |
|---|---|---|---|---|
| Radicale | 小型 CalDAV/CardDAV 服务器，支持事件、待办、日记、通讯录 | 部署轻，文件系统存储简单，认证、权限、TLS、插件可配 | 官方定位是“小而强”的服务器，不提供完整办公 UI/提醒引擎；提醒要另做 | 【判断】极简自建首选之一 |
| Baikal | 轻量 CalDAV+CardDAV 服务器，PHP，Web 管理界面，SQLite/MySQL/PostgreSQL | 比 Radicale 更接近“可直接给家庭/小团队使用”的管理形态 | 仍主要是服务器，不解决三端提醒；提醒和自动化需外部服务 | 【判断】想要管理 UI 时优于 Radicale |
| Nextcloud Calendar | Nextcloud 的 Calendar/VTODO/CalDAV 生态 | Web UI、共享、订阅、任务、事件提醒、邮件提醒、WebDAV-Push 生态完整 | 组件重，需要 cron/occ；官方提醒依赖后台任务，不是天然实时 | 【判断】最适合作为个人 AI 系统主库 |

【事实】Radicale 官方说明它支持 CalDAV、CardDAV、HTTP、事件、待办、日记、TLS、认证、权限与插件，并默认使用简单文件系统存储。来源：[Radicale 文档](https://radicale.org/v3.html)、[Radicale README](https://github.com/Kozea/Radicale/blob/master/README.md)。

【事实】Baikal 官方说明它是轻量 CalDAV+CardDAV 服务器，有 Web 管理界面，数据可存 MySQL、PostgreSQL 或 SQLite，面向 Thunderbird 等 CalDAV/CardDAV 客户端。来源：[Baikal 官网](https://sabre.io/baikal/)、[Baikal README](https://github.com/sabre-io/Baikal/blob/master/README.md)。

【事实】Nextcloud 管理文档说明它发送两类事件提醒：内置 Nextcloud 通知和电子邮件；要让提醒准时发送，建议专用 cron 每 5 分钟执行 `occ dav:send-event-reminders`，并把 `sendEventRemindersMode` 改为 `occ`；否则提醒只会在后台任务运行时“尽快”发送。来源：[Nextcloud Calendar/CalDAV 管理文档](https://docs.nextcloud.com/server/latest/admin_manual/groupware/calendar.html)。

【事实】Nextcloud 的默认限制包括每用户每小时最多创建 10 个日历或订阅、最多 30 个日历/订阅，并可通过 occ 调整。来源同上。

【判断】如果要求“日期数据是权威源、可分享、可网页编辑、支持 VTODO 和邮件提醒”，Nextcloud 是主路线。如果只想让 AI 写入一个轻量 CalDAV 仓库，Radicale 或 Baikal 更省资源，但提醒必须由独立服务负责。

### 2.3 Android 端：DAVx⁵、Etar、Tasks.org

【事实】DAVx⁵ 是 Android 的 CalDAV/CardDAV 同步客户端，不是日历、任务或联系人 UI，也不保存业务数据；它把服务器数据同步到 Android 的 Contacts/Calendar Provider 和 OpenTasks provider。来源：[DAVx⁵ 手册：Introduction](https://manual.davx5.com/introduction.html)。

【事实】DAVx⁵ 明确说明：若希望它定期在后台同步，必须豁免 Android 电池优化；华为、小米等设备还可能需要厂商自启动权限。来源同上。

【事实】DAVx⁵ 使用 Android WorkManager、sync framework 和 AccountManager 集成；Android 7 及以上不允许小于 15 分钟的同步间隔。来源：[DAVx⁵ 手册：Settings](https://manual.davx5.com/settings.html)。

【事实】DAVx⁵ 官方技术文档说明它把 iCalendar `VALARM` 映射到 `CalendarContract.Reminders`，因此服务器上的提醒可以进入 Android 日历提供器。来源：[DAVx⁵ 技术信息](https://manual.davx5.com/technical_information.html)。

【事实】DAVx⁵ 默认通过固定间隔轮询服务器；WebDAV-Push 可以做到更接近实时，但官方明确当前服务端实现只有 Nextcloud 的 `nc_ext_dav_push`，且客户端需要 UnifiedPush 分发器或 Google FCM。来源：[DAVx⁵ WebDAV-Push](https://manual.davx5.com/webdav_push.html)。

【判断】没有 GMS 时，DAVx⁵ 可用 F-Droid 版。没有 WebDAV-Push 时，DAVx⁵ 的同步延迟取决于系统同步窗口和电池策略；对“数分钟内看到日历变化”通常可接受，对“秒级三端实时”不够。

【事实】Etar 官方 README 说明它使用 Android calendar storage 展示所有已同步日历；CalDAV 客户端不包含在 Etar 内，需要 DAVx5 等外部同步 App。来源：[Etar README](https://github.com/Etar-Group/Etar-Calendar/blob/master/README.md)。

【判断】Etar 适合作为轻量、无 GMS 依赖的系统日历替代 UI；它本身不是同步器，不能单独完成 CalDAV 写入。若荣耀手机的系统日历能正确读取 DAVx⁵ 提供的账户，也可不装 Etar，但 Etar 的优势是行为更可控、公开源代码。

【事实】Tasks.org 官方同步文档说明它支持 CalDAV、DAVx⁵、Google Tasks、Microsoft To Do、EteSync 等，并列出标题、截止日期、截止时间、开始时间、子任务、说明、优先级、位置、标签、重复、提醒等同步字段。来源：[Tasks.org Synchronization](https://tasks.org/docs/sync/)。

【事实】Tasks.org 的同步条件是：打开 App 时同步、创建/更新后 1 分钟同步、App 未打开时每小时同步、手动下拉同步。来源同上。

【事实】Tasks.org 官方通知排障文档警告：Android 6+ 可能延迟通知，需要关闭电池优化；OEM 还可能杀后台；Android 14 起不再支持真正的 persistent/sticky 通知，改用 “swipe to snooze”。来源：[Tasks.org Notification troubleshooting](https://tasks.org/docs/troubleshooting_notifications/)。

【判断】Android 上最稳的组合是：

- 事件：DAVx⁵ + Etar/系统日历。
- 任务：DAVx⁵ + Tasks.org。
- 关键提醒：Tasks.org 的本地提醒 + 独立 ntfy/Telegram 推送双保险。
- 荣耀 MagicOS 与三星 One UI 都单独测试“锁屏 8 小时 + 勿扰 + 省电模式 + 重启”。不要只信 Android 通用设置。

### 2.4 Android 原生日历 intent / DAV 同步的可行性

【事实】Android Calendar Provider 官方文档说明：应用的 manifest 若直接读写日历，需要 `READ_CALENDAR`/`WRITE_CALENDAR`；但若只通过 Calendar Intents 交给日历 App 插入、查看、编辑事件，则不需要这些权限。来源：[Calendar Provider overview](https://developer.android.com/guide/topics/providers/calendar-provider)。

【事实】`CalendarContract` 定义日历事件插入 intent、`EXTRA_EVENT_BEGIN_TIME`、`EXTRA_EVENT_END_TIME`、`EXTRA_EVENT_ALL_DAY` 等 extras；`ACTION_EVENT_REMINDER` 是系统在需要发布提醒时触发的广播。来源：[CalendarContract API](https://developer.android.com/reference/android/provider/CalendarContract)。

【判断】“无需自建 App”的路有两条：

1. Intent 路线：AI 端生成 `ACTION_INSERT`，手机上由现有日历 App 打开展示预填事件，用户确认保存。优点是无需权限、无需自建 App；缺点是不能静默写入，且荣耀/Samsung 系统日历对 extras 的处理可能不同。
2. DAV 路线：AI 写服务端 CalDAV，DAVx⁵ 同步进 Calendar Provider，现有日历 App 负责展示和提醒。优点是三端一致、可静默写入服务端；缺点是需要 DAVx⁵ 和电池优化设置。

【判断】Android 平台本身没有面向所有机型、开箱即用的通用“CalDAV 账户”入口。AOSP 的同步机制是 sync adapter，第三方 CalDAV 同步器需要提供 sync adapter；因此 DAVx⁵ 是最现实的“无自建 App”桥梁。

## 3. Google Calendar API 与 Microsoft Graph

### 3.1 Google Calendar API

【事实】Google Calendar API 提供 `calendar`、`calendar.events`、`calendar.events.owned`、`calendar.app.created` 等 scope；scope 最小化是官方建议，公开应用使用敏感/受限数据时需要 OAuth 验证。来源：[Choose Google Calendar API scopes](https://developers.google.com/workspace/calendar/api/auth)。

【事实】创建事件使用 `POST https://www.googleapis.com/calendar/v3/calendars/{calendarId}/events`；需要 `calendar`、`calendar.events`、`calendar.app.created` 或 `calendar.events.owned` 之一。`sendUpdates` 控制通知参会人，默认 `false`；官方警告 `none` 可能导致外部日历不同步甚至事件丢失。来源：[Events: insert](https://developers.google.com/workspace/calendar/api/v3/reference/events/insert)。

【事实】2026-05-01 后新 Cloud project 的 Calendar API 配额为：项目每分钟 10,000 requests，用户每分钟 600 requests，项目每天 1,000,000 requests 免费阈值；超额可能返回 403/429。来源：[Usage limits](https://developers.google.com/workspace/calendar/api/guides/quota)。

【事实】Google 支持 push notifications，但要求 HTTPS webhook、有效证书、watch channel；通知只给 header 和状态，不包含完整变更内容，应用需再调 API。官方明确说通知“不是 100% 可靠”，会丢少量消息，必须能无推送仍完成同步。channel 靠近过期时需要手动 watch 续订，没有自动续订。来源：[Push notifications](https://developers.google.com/workspace/calendar/api/guides/push)。

【判断】Google 路线的最大优势是 Android/Windows 官方客户端体验好，尤其 Android 端提醒基本不用自己维护；最大代价是数据经 Google、OAuth 验证/同意页、scope 受限、API 配额和国内网络不确定性。若“不要求必须使用 Google 服务但可评估 GMS”，它应作为可选增强，不应作为唯一主链路。

### 3.2 Microsoft Graph

【事实】Graph 创建事件使用 `POST /me/events` 等端点；需要 `Calendars.ReadWrite`，该权限支持 delegated（工作/学校、个人账号）和 application。创建带参与者的事件时，服务器会自动向参与者发邀请，且此行为不可关闭。来源：[Create event](https://learn.microsoft.com/en-us/graph/api/user-post-events?view=graph-rest-1.0)。

【事实】Graph `event` 资源支持 `isReminderOn`、`reminderMinutesBeforeStart`、`transactionId`、`iCalUId` 等字段；`transactionId` 用于客户端重试时防止重复创建。来源：[event resource](https://learn.microsoft.com/en-us/graph/api/resources/event?view=graph-rest-1.0)。

【事实】Graph 节流不公开固定云级配额，按场景、租户、应用和请求类型动态变化；超限返回 429 和 `Retry-After`，官方建议不要立即重试，应遵循 `Retry-After` 或指数退避。来源：[Microsoft Graph throttling](https://learn.microsoft.com/en-us/graph/throttling)。

【事实】Graph 订阅必须有 HTTPS notification URL。Outlook `event` 订阅最长约 7 天，富通知含资源数据时最长 1 天；请求低于 45 分钟会自动提升到 45 分钟。订阅需主动续订。来源：[subscription resource](https://learn.microsoft.com/en-us/graph/api/resources/subscription?view=graph-rest-1.0)、[Change notifications overview](https://learn.microsoft.com/en-us/graph/change-notifications-overview)。

【事实】Graph 通知延迟表中，`calendar` 资源平均小于 1 分钟、最大约 3 分钟；`event` 资源延迟为未知。订阅寿命和延迟之外，还需要处理 lifecycle notifications、reauthorizationRequired、missed notifications 等。来源同上。

【判断】如果用户已有 Microsoft 365，Graph 是 Windows 端体验最好的方案，尤其 Outlook 就是权威客户端。代价是 OAuth/管理员同意、订阅续订、节流处理和工作/个人账号差异；对私人自建系统而言治理成本高于 CalDAV。

## 4. 到点提醒替代通道

### 4.1 对比表

| 通道 | Android 后台可靠性 | Windows 通知体验 | 隐私/依赖 | 结论 |
|---|---|---|---|---|
| ntfy 自建 + F-Droid | 高：F-Droid flavor 始终 instant delivery，前台服务，可在 Doze 下即时 | 中：Web/PWA 可用；桌面浏览器不运行时不可靠 | 自托管、低外部依赖 | 【判断】无 GMS 主备通道首选 |
| Gotify 自建 | 中高：Android App，需关闭电池优化，否则可能被杀 | 弱：官方仓库主打 server + Android；Windows 基本靠 Web/API | 自托管 | 【判断】Android 可，Windows 不作为主提醒 |
| Telegram Bot | 高：官方 Android/Windows 客户端独立云同步 | 高：Telegram Desktop 原生通知 | 消息经 Telegram 云 | 【判断】最省心的跨端提醒，但隐私要接受 |
| Email | 中：依赖邮件客户端同步，实时性差 | 中高：Outlook/Thunderbird 运行时通知可靠 | 企业邮件可控 | 【判断】审计与兜底，不适合精确分钟提醒 |
| 企业微信 | 高：官方 Android/Windows 客户端 | 高：官方 Windows 桌面端 | 企业租户/管理策略 | 【判断】组织已用时优先，私人事项慎用 |
| 钉钉 | 高：官方多端客户端 | 高：官方 Windows 客户端 | 企业租户/管理策略 | 【判断】同企业微信，需避开敏感内容 |
| 飞书 | 高：官方多端客户端 | 高：官方 Windows 客户端 | 企业租户/管理策略 | 【判断】webhook 和机器人能力明确，适合团队场景 |

### 4.2 ntfy

【事实】ntfy 通过 HTTP PUT/POST 发布消息，手机安装 Android App 后订阅 topic 即可接收通知。来源：[ntfy Getting started](https://docs.ntfy.sh/)。

【事实】ntfy Android F-Droid flavor 不包含 Firebase；官方说 F-Droid 构建所有订阅默认使用 instant delivery，即时模式通过前台服务实现，可在 Doze 下即时收到消息；若关闭即时模式，消息可能延迟几分钟甚至几小时。Google Play flavor 只在 `ntfy.sh` 主站使用 Firebase，自建服务器不使用 FCM。来源：[ntfy phone subscription](https://docs.ntfy.sh/subscribe/phone/)、[ntfy FCM config](https://docs.ntfy.sh/config/#firebase-fcm)。

【事实】ntfy 桌面 Web 端在开启 background notifications 时使用 Web Push；桌面 Chrome/Firefox/Edge/Opera 在浏览器不运行时不能接收通知，Safari 桌面才支持浏览器不运行。若 App 超过一周未打开，后台通知会暂停。来源：[ntfy Web app](https://docs.ntfy.sh/subscribe/web/)。

【事实】ntfy 默认监听 `:80` 为 IPv4-only；要监听 IPv6 需显式 `[::]:80`，若要同时 IPv4+IPv6 官方建议放在 nginx 等反向代理后。来源：[ntfy IPv6 support](https://docs.ntfy.sh/config/#ipv6-support)。

【判断】ntfy 是无 GMS Android 端最可靠的独立通道，但 Windows 端不应当作唯一提醒源。除非保证 Windows 浏览器常开或使用其他原生客户端，否则 Windows 关键提醒应同时走 Telegram/企业微信/飞书/邮件。

### 4.3 Gotify

【事实】Gotify 官方服务端文档把 client 定义为接收消息并管理 client/application/message 的设备或程序，message 有 content、title、creation date、application id、priority。来源：[Gotify Intro](https://gotify.net/docs/)。

【事实】Gotify Android README 说明它连接 gotify/server 后显示推送通知，并要求关闭电池优化，否则 Gotify 会被 Android 杀死而收不到通知；前台通知可降低打扰。来源：[Gotify Android README](https://github.com/gotify/android/blob/master/README.md)。

【判断】Gotify 与 ntfy 类似，但 Windows 端官方生态明显弱于 ntfy；更适合作为 Android 自建推送的实验方案，不适合作为三端主提醒。

### 4.4 Telegram Bot

【事实】Telegram Bot API 支持 HTTPS 请求，`sendMessage` 可向指定 chat 发送消息；获取 update 有 getUpdates 和 webhook 两种互斥方式，update 最多保留 24 小时。来源：[Telegram Bot API](https://core.telegram.org/bots/api#sendmessage)。

【事实】Telegram 官方 FAQ 给出广播限制：单个 chat 避免超过 1 条/秒；群组不超过 20 条/分钟；批量通知约 30 条/秒，超额返回 429。来源：[Telegram Bots FAQ](https://core.telegram.org/bots/faq)。

【事实】Telegram 官方提供 Android、Windows/Mac/Linux Desktop、Web 客户端。来源：[Telegram Applications](https://telegram.org/apps)。

【判断】Telegram 是三端通知体验最稳定的低成本选择之一：Android 推送和 Windows 原生桌面通知都成熟。缺点也清楚：消息进入 Telegram 云，用户需先与 bot 建立会话并允许通知；不适合敏感日程。

### 4.5 Email

【事实】SMTP 定义邮件传输与提交，RFC 6409 把 message submission 通常放在 587 端口；IMAP4rev2 定义客户端访问邮箱、离线重同步、IDLE 等能力。来源：[RFC 5321](https://www.rfc-editor.org/rfc/rfc5321.txt)、[RFC 6409](https://www.rfc-editor.org/rfc/rfc6409.txt)、[RFC 9051](https://www.rfc-editor.org/rfc/rfc9051.txt)。

【判断】Email 适合作审计、失败告警和兜底，不适合作为唯一到点提醒：端侧提醒依赖邮件客户端和系统通知设置，手机省电/推送策略会影响实时性，Windows 端必须保证 Outlook/Thunderbird 运行或系统邮件客户端有推送。

### 4.6 企业微信 / 钉钉 / 飞书

【事实】企业微信消息推送（原群机器人）通过 webhook URL 发 HTTP POST，支持 text、markdown、markdown_v2、image、news、file、voice、template_card；官方提醒必须保护 webhook，并写明“每个消息推送发送的消息不能超过 20 条/分钟”。来源：[企业微信消息推送配置说明](https://developer.work.weixin.qq.com/document/path/91770)。

【事实】企业微信官网提供 Windows 桌面端、Mac 桌面端、iOS、Android 下载入口，并提供日程、会议、待办等能力。来源：[企业微信官网](https://work.weixin.qq.com/#indexDownload)。

【事实】飞书自定义机器人通过 webhook 推送消息，支持 text、post、interactive card 等；官方说明单租户单机器人 100 次/分钟、5 次/秒，请求体不超过 20 KB；安全设置支持自定义关键词、IP 白名单、签名校验。来源：[飞书自定义机器人使用指南](https://open.feishu.cn/document/client-docs/bot-v3/add-custom-bot)。

【事实】钉钉官方提供自定义机器人 webhook 文档入口，但网页主体为动态应用内容，本次终端抓取未能读取到其中限流细节。来源：[钉钉自定义机器人文档](https://open.dingtalk.com/document/orgapp/custom-robot-access)。

【判断】企业微信/钉钉/飞书适合“已经在组织里用”的场景：Android 和 Windows 都是官方原生客户端，通知比自建 Web UI 稳。但它们不是个人隐私工具，webhook 泄露可直接发垃圾消息，租户管理员也可能有可见性/保存策略。敏感日程只推中性标题或干脆不用。

## 5. Windows 11 端 CalDAV 与提醒可靠性

### 5.1 Thunderbird

【事实】Thunderbird 官网把桌面版定位为 Windows、Linux、macOS 上的 email、calendar、contacts 一体化 App，提供 64-bit/32-bit Windows 下载。来源：[Thunderbird 官网](https://www.thunderbird.net/en-US/features/)。

【事实】Thunderbird 内置 Calendar 功能；CalDAV 日历和提醒属于客户端功能，具体配置和通知方式应在安装版本中验证。Mozilla 支持页在本次检索中触发反自动化挑战，因此本文不把未读到的细节写成事实。

【判断】Thunderbird 是 Windows 11 上最现实的开源 CalDAV 客户端：能同步事件/任务、界面成熟、无 GMS 依赖。提醒可靠性取决于 Thunderbird 是否运行。若要求电脑关机/睡眠/未登录时仍提醒，必须使用系统级计划任务、ntfy/Telegram/企业 IM 客户端等外部通道，不能只依赖 Thunderbird 内部 alarm。

### 5.2 Outlook / Windows 集成

【事实】Outlook CalDav Synchronizer 官方仓库说明它同步 Outlook 与 Google、SOGo、Horde 或任意 CalDAV/CardDAV 服务器，支持 Outlook 2021、2019、2016、2013、2010、2007 和 Office 365 Desktop；支持事件、任务、联系人、提醒、重复事件、类别、TLS、代理、时间触发同步、变更触发同步、WebDAV Collection Sync，并带系统托盘通知。来源：[Outlook CalDav Synchronizer](https://github.com/aluxnimm/outlookcaldavsynchronizer)。

【事实】Microsoft 官方“Add an email account to Outlook for Windows”列出的账户类型包括 Outlook.com、Microsoft 365、Gmail、Yahoo、iCloud 和 Exchange，以及经典 Outlook 的 POP/IMAP 或第三方 MAPI。该页面没有给出“任意自建 CalDAV 账户”的原生添加方式。来源：[Add an email account to Outlook for Windows](https://support.microsoft.com/en-us/office/add-an-email-account-to-outlook-for-windows-6e27792a-9267-4aa4-8bb6-c84ef146101b)。

【判断】Windows 端若坚持 Outlook：

- 用经典 Outlook + Outlook CalDav Synchronizer 是可行路线。
- 新版 Outlook for Windows 与经典 Outlook/COM 插件兼容性要单独验证，不能假定插件可用。
- 插件同步的是 Outlook 本地日历/任务，Outlook 必须运行或同步代理可用；这比 Thunderbird 多一层 COM/插件依赖，但通知体验更贴近 Windows 用户习惯。

## 6. IPv6-only 服务的现实风险与解决方案

### 6.1 风险

【事实】Happy Eyeballs v2 规定客户端在有 A 和 AAAA 时并发探测，以降低双栈连接延迟，并优先 IPv6；如果只发布 AAAA，就没有 IPv4 fallback。来源：[RFC 8305](https://www.rfc-editor.org/rfc/rfc8305.txt)。

【事实】NAT64 让 IPv6-only 客户端访问 IPv4-only 服务；DNS64 从 A 记录合成 AAAA，两者配合可让 IPv6-only 客户端按域名访问 IPv4-only 服务。来源：[RFC 6146](https://www.rfc-editor.org/rfc/rfc6146.txt)、[RFC 6147](https://www.rfc-editor.org/rfc/rfc6147.txt)。

【事实】464XLAT 用 CLAT/PLAT 在 IPv6-only 网络上提供 IPv4 客户端-服务器模型支持，但明确不支持从 IPv4 主动入站连接到私网主机，且架构核心是让 IPv6 网络承载 IPv4 流量。来源：[RFC 6877](https://www.rfc-editor.org/rfc/rfc6877.txt)。

【事实】RFC 7050 定义用 `ipv4only.arpa` 发现 DNS64/NAT64 前缀。来源：[RFC 7050](https://www.rfc-editor.org/rfc/rfc7050.txt)。

【事实】DoH 用 HTTPS 传输 DNS 查询，客户端配置 DoH 后可能绕过运营商 DNS64 行为。来源：[RFC 8484](https://www.rfc-editor.org/rfc/rfc8484.txt)。

【判断】IPv6-only 服务的关键风险不是“手机能否解析 AAAA”，而是：

- 蜂窝网络是原生 IPv6、IPv6-only + 464XLAT，还是仅 IPv4。
- Windows 所在宽带是否有原生 IPv6；很多家庭/公司网络仍无可用 IPv6。
- DNS64/NAT64 只能解决 IPv6 客户端访问 IPv4 服务，不能反向解决 IPv4 客户端访问 IPv6-only 服务。
- DoH/私有 DNS 可能绕过运营商 DNS64，导致域名看起来解析失败或得到不可达地址。
- 服务器只有 AAAA 时，证书签发、反向代理健康检查也要支持 IPv6。

### 6.2 推荐方案

【判断】优先级从高到低：

1. 双栈前门：公网 IPv4+IPv6 反向代理/负载均衡，回源到服务器 IPv6 私网或公网地址。DNS 同时发布 A 和 AAAA。客户端有 IPv6 走 IPv6，没有就走 IPv4。这是最稳方案。
2. Cloudflare/托管反向代理：把域名代理到源站，客户端看到 Cloudflare 的 IPv4/IPv6 anycast 地址；源站只允许 Cloudflare 回源。官方说明 proxied A/AAAA/CNAME 会用 Cloudflare 地址响应，访问者不直接看到源站 IP。来源：[Cloudflare IP addresses](https://developers.cloudflare.com/fundamentals/concepts/cloudflare-ip-addresses/)、[Proxy status](https://developers.cloudflare.com/dns/manage-dns-records/reference/proxied-dns-records/)。
3. IPv4 VPS 反向代理：小 VPS 做 HTTPS 入口，IPv6 回源；可控性高于托管代理，但要维护证书、防火墙和 DDoS 防护。
4. Tailscale/组网：客户端安装 Tailscale，经 DERP 或直连访问 IPv6-only 服务。官方说明大多数情况无需开放防火墙端口，困难网络会用 DERP relay，但速度会下降；客户端需要能出站到 443 等端口。来源：[Tailscale firewall ports](https://tailscale.com/kb/1082/firewall-ports)。
5. IPv6-only + DNS64/NAT64 依赖：只适合已经确认所有网络都有 IPv6/464XLAT 的实验室环境，不宜作为主路线。

【判断】HTTPS 必须使用正规域名和受信任证书。IPv6-only 时推荐 DNS-01 challenge 签发/续期证书，避免 HTTP-01 因入口无 IPv4 而失败。反向代理需正确设置 Host、X-Forwarded-*、WebSocket/HTTP stream，并且 ntfy/CalDAV 等长连接或 WebDAV 方法不能被 WAF 误拦。

## 7. 各路线落地建议

### 7.1 主路线：Nextcloud + DAVx⁵ + Tasks.org/Etar + Thunderbird + ntfy/Telegram

【判断】架构：

```text
Windows/Android 客户端
  -> HTTPS 双栈前门或 Cloudflare/Tailscale
  -> Nextcloud CalDAV + Tasks
  -> PostgreSQL/MySQL + 定时备份

服务端提醒调度器
  -> 读取 CalDAV/数据库中的事件与 VTODO
  -> 生成 reminder_jobs
  -> ntfy (Android F-Droid, Windows 兜底) + Telegram/企业 IM
```

【判断】Android 配置：

- 荣耀手机、Galaxy Tab S7 FE 都安装 DAVx⁵。
- 数据源选择 DAVx⁵ 的 Nextcloud 账户，不保存到设备本地账户。
- 关闭 DAVx⁵ 和 Tasks.org 的电池优化，确认厂商自启动/后台白名单。
- 日历事件用 Etar 或系统日历；任务用 Tasks.org。
- ntfy F-Droid flavor 打开永久 instant delivery。
- 为重要事项同时开启 Tasks.org/系统日历提醒和 ntfy 提醒，防止一条链路失效。

【判断】Windows 配置：

- 首选 Thunderbird + CalDAV，安装后测试提醒、系统通知、休眠唤醒。
- 如果必须用 Outlook 工作流，用经典 Outlook + Outlook CalDav Synchronizer，测试新版 Outlook 是否影响插件。
- 关键提醒同时推 Telegram Desktop 或企业 IM；不要只依赖 Thunderbird 在后台。

【判断】服务端配置：

- Nextcloud 后台任务改为 systemd timer/cron，事件提醒走 `occ dav:send-event-reminders`，并监控执行失败。
- 独立提醒调度器不要依赖 Nextcloud 的 5 分钟后台任务；可以自己用数据库 job 精确定时。
- 所有 reminder 发送写幂等键 `calendar_uid + occurrence + channel + scheduled_at`。
- 用 PostgreSQL 或可靠 SQLite + 备份；CalDAV 文件存储方案也要每日快照。

### 7.2 备选路线 A：Google Calendar API

【判断】适用条件：

- 用户接受 Google 账号和云端数据。
- Android 有 GMS。
- Windows 用户愿意使用 Google Calendar Web/PWA 或配置 Outlook/Thunderbird 订阅。

【判断】落地要点：

- OAuth 使用最小 scope，优先 `calendar.events.owned` 或专用 secondary calendar。
- 自建服务端保存 refresh token 加密版本；不要放到客户端。
- `events.insert` 写事件和 reminders；不要把 `sendUpdates=none` 用在需要外部日历同步的场景。
- 建 push channel 作为优化，但必须定时 full sync 兜底，官方说明 push 会丢消息。
- 对 AI 自动写入加人工确认或“撤销窗口”，避免 OAuth 权限直接改错日历。

### 7.3 备选路线 B：Microsoft Graph

【判断】适用条件：

- 已有 Microsoft 365/Outlook，且 Windows 端是主战场。
- 能处理应用注册、管理员同意或用户 delegated consent。

【判断】落地要点：

- 私人工具优先 delegated `Calendars.ReadWrite`，减少租户管理员审批。
- 事件写入设置 `isReminderOn` 和 `reminderMinutesBeforeStart`。
- 用 `transactionId` 做重试幂等。
- 订阅设 lifecycleNotificationUrl，提前续订，处理 429/Retry-After，定期 full sync。
- 不要用 application permission 随意写全租户邮箱，除非确实是企业集成。

## 8. 推荐通知通道组合

【判断】最稳的“个人 + 无 GMS”组合：

1. Android 主通道：ntfy 自建 + F-Droid 版，instant delivery 前台服务。
2. Windows 主通道：Telegram Desktop；若不接受 Telegram，则用企业微信/飞书桌面端。
3. 数据主链路：Nextcloud CalDAV/VTODO + DAVx⁵ + Tasks.org/Etar + Thunderbird。
4. 兜底：Email + 服务端监控告警；每日 summary 而不是只发到点提醒。

【判断】如果隐私优先级高于一切：

1. Android 用 ntfy 自建 F-Droid。
2. Windows 用 ntfy Web/PWA + 保证浏览器常开，或加 Windows Task Scheduler 本地拉取/Toast 脚本。
3. 数据用 Nextcloud/Radicale/Baikal。
4. 接受 Windows 端可靠性下降，并用桌面系统通知和邮件双写补强。

## 9. 最小验收测试

【判断】上线前至少跑这些场景：

1. 服务端创建事件，Android 锁屏 30 分钟后同步并提醒。
2. 服务端改期，Android 旧提醒取消，新时间提醒。
3. 服务端删除，Android 不出现幽灵提醒。
4. VTODO 截止提醒在 Tasks.org 触发。
5. Windows 重启、休眠、睡眠后提醒仍按预期触发。
6. 断网 24 小时再连接，三端最终一致且无重复。
7. IPv4-only 网络访问域名，确认有 A/反代/隧道兜底。
8. 蜂窝网络切换 Wi-Fi、VPN、省电模式、勿扰模式。
9. 跨时区、夏令时、全天事件、重复事件。
10. 重复写入 3 次同一 AI 事项，只生成一个日历项和一个提醒。

## 10. 尚未完全验证 / 需实测

【判断】以下内容受设备、版本、网络影响，不应仅凭文档拍板：

- 荣耀 MagicOS 具体版本的省电、自启动、后台弹窗和通知折叠策略。
- Samsung One UI 对 DAVx⁵、Tasks.org、ntfy 的长期后台限制。
- Thunderbird 在 Windows 11 关机、休眠、快速启动、未登录状态下的提醒边界。
- 新版 Outlook for Windows 与 Outlook CalDav Synchronizer 的兼容性。
- 钉钉自定义机器人官方限流细节，本次抓取未能读取动态文档正文。
- Cloudflare proxied WebDAV/CalDAV 全方法兼容性与 WAF 行为。
- 荣耀手机蜂窝网络是否长期提供原生 IPv6 或 464XLAT，以及运营商 DNS64/DoH 行为。

## 11. 主要官方来源

协议与标准：

- [RFC 4791: CalDAV](https://www.rfc-editor.org/rfc/rfc4791.txt)
- [RFC 5545: iCalendar](https://www.rfc-editor.org/rfc/rfc5545.txt)
- [RFC 6638: CalDAV Scheduling](https://www.rfc-editor.org/rfc/rfc6638.txt)
- [RFC 8305: Happy Eyeballs v2](https://www.rfc-editor.org/rfc/rfc8305.txt)
- [RFC 6146: Stateful NAT64](https://www.rfc-editor.org/rfc/rfc6146.txt)
- [RFC 6147: DNS64](https://www.rfc-editor.org/rfc/rfc6147.txt)
- [RFC 6877: 464XLAT](https://www.rfc-editor.org/rfc/rfc6877.txt)
- [RFC 7050: NAT64 Prefix Discovery](https://www.rfc-editor.org/rfc/rfc7050.txt)
- [RFC 8484: DNS over HTTPS](https://www.rfc-editor.org/rfc/rfc8484.txt)

CalDAV/VTODO 与客户端：

- [Radicale](https://radicale.org/v3.html)
- [Baikal](https://sabre.io/baikal/)
- [Nextcloud Calendar/CalDAV admin manual](https://docs.nextcloud.com/server/latest/admin_manual/groupware/calendar.html)
- [DAVx⁵ manual](https://manual.davx5.com/)
- [Tasks.org synchronization](https://tasks.org/docs/sync/)
- [Tasks.org notification troubleshooting](https://tasks.org/docs/troubleshooting_notifications/)
- [Etar README](https://github.com/Etar-Group/Etar-Calendar/blob/master/README.md)
- [Thunderbird](https://www.thunderbird.net/en-US/features/)
- [Outlook CalDav Synchronizer](https://github.com/aluxnimm/outlookcaldavsynchronizer)

Google/Microsoft：

- [Google Calendar API scopes](https://developers.google.com/workspace/calendar/api/auth)
- [Google Calendar Events.insert](https://developers.google.com/workspace/calendar/api/v3/reference/events/insert)
- [Google Calendar usage limits](https://developers.google.com/workspace/calendar/api/guides/quota)
- [Google Calendar push notifications](https://developers.google.com/workspace/calendar/api/guides/push)
- [Microsoft Graph Create event](https://learn.microsoft.com/en-us/graph/api/user-post-events?view=graph-rest-1.0)
- [Microsoft Graph event resource](https://learn.microsoft.com/en-us/graph/api/resources/event?view=graph-rest-1.0)
- [Microsoft Graph throttling](https://learn.microsoft.com/en-us/graph/throttling)
- [Microsoft Graph subscription](https://learn.microsoft.com/en-us/graph/api/resources/subscription?view=graph-rest-1.0)
- [Microsoft Graph change notifications](https://learn.microsoft.com/en-us/graph/change-notifications-overview)

提醒通道：

- [ntfy docs](https://docs.ntfy.sh/)
- [ntfy Android](https://docs.ntfy.sh/subscribe/phone/)
- [ntfy Web](https://docs.ntfy.sh/subscribe/web/)
- [Gotify docs](https://gotify.net/docs/)
- [Gotify Android README](https://github.com/gotify/android/blob/master/README.md)
- [Telegram Bot API](https://core.telegram.org/bots/api)
- [Telegram Apps](https://telegram.org/apps)
- [企业微信消息推送](https://developer.work.weixin.qq.com/document/path/91770)
- [飞书自定义机器人](https://open.feishu.cn/document/client-docs/bot-v3/add-custom-bot)
- [钉钉自定义机器人](https://open.dingtalk.com/document/orgapp/custom-robot-access)

Android/Windows：

- [Android Calendar Provider](https://developer.android.com/guide/topics/providers/calendar-provider)
- [CalendarContract API](https://developer.android.com/reference/android/provider/CalendarContract)
- [Android Doze and App Standby](https://developer.android.com/training/monitoring-device-state/doze-standby)
- [Android Sync adapters](https://developer.android.com/training/sync-adapters)
- [Windows app notifications](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/notifications/app-notifications/)
- [Outlook account setup](https://support.microsoft.com/en-us/office/add-an-email-account-to-outlook-for-windows-6e27792a-9267-4aa4-8bb6-c84ef146101b)
