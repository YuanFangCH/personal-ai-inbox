# RM 交接总文档

> 本文件是本项目的当前交接入口；保留产品状态、关键决定和待办。

## 1. 文档状态

| 字段 | 当前值 |
|---|---|
| 项目名称 | 懒狗秘书 |
| 最后更新时间 | 2026-11-10 |
| 时区 | Asia/Singapore |
| 最后修改 Agent | Codex |
| 当前阶段 | `v1.6.0+14` Android 手机预览版发布准备完成：API 35 模拟器完成 50 例、900 秒长测、多表小组件与旧版覆盖升级门禁；荣耀 90 真机延期 |
| 总体状态 | Android、Windows 与 Web 共用 Flutter 客户端。本地 Markdown 为成果正文权威副本，SQLite 保存索引与操作状态。Android 发布包自 v1.1.4 起使用固定长期签名；Windows 安装包未做代码签名。v1.6.0 本次只发布 Android；OneDrive 双向同步、百度网盘归档和到点提醒尚未接入 |

## 2. 一句话交接

2026-11-10 `v1.6.0+14` Android 手机预览版进入发布流程：API 35 模拟器完成手机适用秘书矩阵 50/50、921 秒长测与 47 条写入/读回，并完成多表桌面小组件的尺寸、滚动、深色、多实例、独立绑定、归档恢复、冷进程点击和 `v1.5.1+13` 同签名覆盖升级。荣耀 90 真机与 API 24–30 固定行仍明确未覆盖。

当前验证入口为 `test-results/phone-release-v1.6.0/VALIDATION.md`，小组件合同见 `docs/home-widget-contract.md`，发行说明见 `docs/releases/v1.6.0.md`。
## 3. 当前目标与范围

- 当前任务：完成 `v1.6.0+14` Android 手机预览版 GitHub 更新、发布和公开资产复核；荣耀 90 真机、API 24–30 和平板/Windows 专项继续单独处理。

- Android 手机、Android 平板和 Windows 作为独立客户端运行。
- 每个成果保存为一个 Markdown 文件；本地索引由 SQLite 管理。
- AI 使用 OpenAI 兼容接口，凭据保存在系统安全存储。
- 真实 OneDrive、百度网盘、到点提醒和跨端同步仍属于后续产品工作；Android 后台任务所需的前台服务通知已接。
- 现行 P0–P9 已实现本地表/内容类型、首页/日历投影、AI 权限和旧事项迁移首轮；现行全局知识人工确认，下一版按 ADR 0024 区分权限模式。真实资料迁移仍由应用迁移门单独确认。

## 4. 权威文件

| 文件 | 用途 |
|---|---|
| [README.md](README.md) | 项目介绍、当前版本和运行入口 |
| [AGENTS.md](AGENTS.md) | 项目协作及仓库维护约定 |
| [CONTEXT.md](CONTEXT.md) | 正式术语 |
| [个人 AI 收件箱方案](docs/personal-ai-inbox-executable-plan.md) | 产品目标、架构和路线 |
| [同步协议](docs/sync-protocol.md) | 成果同步语义 |
| [模型接入](docs/model-integration.md) | API 与凭据边界 |
| [ADR 索引](docs/adr/README.md) | 已接受的架构决定 |
| [前端改版方案](docs/frontend-visual-redesign-plan.md) | 当前 UI 设计规格 |
| [表与笔记改版规划](docs/table-notebook-redesign-plan.md) | 用户已确认的目标规则、实施建议与未完事项；当前进度见执行计划 |
| [表与笔记执行计划](docs/table-notebook-implementation-plan.md) | P0–P9 共 80 步首轮状态、文件落点、验证证据与剩余边界 |
| [表与内容数据契约](docs/table-data-contract.md) | 已实现的本地 schema/归属/迁移/投影/恢复及尚未接入的跨端同步边界 |
| [表交互契约](docs/table-interaction-contract.md) | 页面层级、AI 工具和确认交互基线；当前实现文案见应用 |
| [专用秘书 Agent 设计](docs/secretary-agent-design.md) | 已确认的秘书完整规格、权限/查重/检索/恢复 interface、A–F 实施包与36项验收；当前实施与验收中 |
| [DSH 参考研究](docs/research/04-dsh-agent-permissions-and-runtime.md) | 固定提交源码事实、真实引擎钉住版本、借鉴建议与未证实边界；不自动成为运行能力 |
| [Android 桌面小组件合同](docs/home-widget-contract.md) | 逻辑卡片、渲染快照、实例绑定和秘书工具 |

## 5. 已锁定决定

- 2026-11-03 新目标优先级：ADR 0024/专用设计取代本节旧目标中“默认表永久不可删”和“所有模式全局知识均逐项确认”。实现已在 `111f996` 切换到新行为，并由 v1.3.0 Android 手机候选承载；旧版本及历史验证不改写。
- 完全权限由用户为会话显式选择，可直接操作任意表、字段、内容和全局知识；标准模式继续结构/知识确认，升级不扩大授权。完全权限包含预置表删除，删除后启动不重建，缺少收纳目标的原文保留待归表。
- 正式自动入库统一查重：同操作幂等，同一件事复用或自动补充；同标题不同时间/对象保持独立，未解决的身份/事实冲突才询问。权限、版本和必要本地检查不因完全权限或预算边界被省略。

- 各设备独立运行本地核心，不依赖集中式后端。
- Markdown 是成果正文的权威副本；SQLite 是可重建索引与本地状态存储。
- 仅确认后的成果进入同步；未确认候选留在本机。
- 普通成果操作受会话权限约束；全局知识在标准模式确认，完全权限直接生效并记录策略授权来源。
- Web 仅作界面预览，不作为可靠备份或迁移来源。
- 表采用可写正文的笔记页，可混合承载内容；待办/日程/事件预置收纳表可调整、删除和恢复，自定义表及预置表删除时连内容进入回收站。收纳目标由独立映射决定，删除后启动不重建。
- 新目标：日程表示未来要做且时间明确的安排；事件缺少上述任一条件，事件可以引发已有日程修改。普通笔记仅加时间标签不进入日历。
- 首页保留现有区块和无日期待办，下方支持添加表展示、排序、默认五行与展开；AI 表内内容操作和跨表移动按权限执行，标准模式的结构变更在对话确认，完全权限可直接执行；没有独立待处理页。
- 旧事项迁移为表并保留正文和关联待办、事件；普通知识进入表，全局知识继续独立管理，确认方式按 ADR 0024 区分。ADR 0020/0021 的本地存储及权限已实现；跨端同步格式仍旧，真实资料迁移由应用迁移门确认。
- 新目标细化：带截止时间的待办仍是待办；无指定表且无其他明确归属的普通笔记进入事件表但保持笔记类型。自定义字段按表定义、逐条填写，首版为文本、数字、日期时间、单选、多选、勾选六种类型。
- 新目标细化：调整通知保留为事件并更新原日程；自定义表连内容删除后进入回收站，保留 30 天，期间整表恢复，到期自动清理。
- 秘书导航更新：秘书页在 AppShell 中常驻；主页面切换保留会话、未发送草稿、已选附件、思考选项和阅读位置，回复生成不中断。手机保留底部导航，宽屏用统一应用侧栏；新建/历史/分享定位不增加对话路由。全局约定见 ADR 0022。
- 2026-11-09 完全体模式采用设置页设备级覆盖层：默认关闭，开启后统一覆盖全部现有和新会话为应用内完全权限，关闭后恢复会话原策略；不批量改写持久授权。取消应用层累计上下文、检索、附件和瞬时故障重试上限，但保留模型硬限额、磁盘、网络、系统生命周期、幂等、CAS、写日志和不确定副作用核对。会话/附件删除保留 30 天；单条消息、推理内容和工具回执不可改写。见 [ADR 0026](docs/adr/0026-device-full-agent-mode.md)。
- 2026-11-10 Android 多表桌面小组件采用逻辑卡片、Flutter 快照和原生实例三层模型；API 31+ 使用标准集合滚动并采用可变广播模板处理行点击，固定尺寸使用直接 RemoteViews。日期只在 App 活跃时重算，配置和快照留在本机 `noBackupFilesDir`。见 [ADR 0027](docs/adr/0027-android-table-widget-projection.md)。

## 6. 当前进度与验证

- 2026-11-10 Android 多表桌面小组件 API 35 验收通过：2×2 摘要、4×2 短列表、4×4 滚动、多表/自定义字段/日期筛选、深色、同卡多实例同步、不同卡独立绑定、取消固定、归档恢复、标题/条目点击、`am kill` 冷进程点击均通过。荣耀 90 真机延期；API 24–30 未在对应 AVD 实测。详见 [发布验证](test-results/phone-release-v1.6.0/VALIDATION.md)。
- 2026-11-10 Android 手机发布门禁重跑：50/50 个唯一秘书用例通过，用时约 4 分 06 秒；900 秒长测实际 921 秒，47 条写入/读回、219 次请求，切后台、锁屏 12 秒、唤醒、重开和最终流式答复通过。长测 runner 修正成功 `.bat` 进程空退出码与正常 stderr 的 Windows PowerShell 兼容问题。
- 2026-11-10 最终 Debug 候选构建通过：`1.6.0+14`、minSdk 24、targetSdk 36，APK 241,453,479 字节，SHA-256 `5fc70664d8c03fdf416a3239f880a8fcfacb88b0a13ac80cd515e55a05f00ab7`；`flutter analyze --no-pub` 0 issue，格式 289 文件 0 change。PDF 依赖升级到 `pdfrx 2.12.0` 并保留 `pdfium_dart 0.4.1` 本地许可副本修复上游下载路径，文件输入测试 9/9。

- 2026-11-09 修复中断任务恢复死循环：物理手机任务 `agent_1794204476923870_1` 的 `tool_transcript_json` 约 66 KB，错误内容反复写回助手消息；根因是 `AgentContextManager` 只能裁剪工具结果，不能处理超大工具调用参数，随后又被额外 10% 缩小余量二次阻断。现新增安全摘要回退并标记 `latest_tool_round_compacted`，同时改为只要求最终请求低于模型窗口硬上限。`AgentContextManager` 3/3、`ChatService` 31/31、完整 Android 发布门禁 295/295、`flutter analyze --no-pub` 0 issue、formatter 271 文件 0 change。
- 2026-11-09 物理手机 `1.5.1+13` 恢复复验：覆盖安装同正式证书的测试包后，原任务从 `needs_review` 转为 `running`；检查点请求数由 7 增至 12、工具调用由 28 增至 53，界面出现多张“已移动内容 / 已执行”卡片，发送按钮变为“停止生成”。无线 ADB 在继续等待最终完成后掉线，尚未取得最终完成态；需重连后确认任务结束和内容归属。
- 2026-11-09 `v1.5.1+13` 正式签名 Release 本地构建通过：`versionName=1.5.1`、`versionCode=13`、非 Debuggable、v2 签名和长期证书 `51b5e2f3...523f4816` 均正确。本地 APK SHA-256 `e9067ecba38757fe40ec0af7ca23d0ea78e0268094060829c81e5af9bbc60783`；公开资产以 GitHub 流水线结果为准。
- 2026-11-09 Android 手机 v1.5.1 发布完成：Release `phone-v1.5.1`（pre-release）；main CI `42600289991` / job `129102767208` success，Android Release `42600311129` / job `129102839728` success。公开 APK `90,977,347` 字节，SHA-256 `3e084f2ae788acf7f7a34b550abd62ec1aa4ed26d9bb808be2440c12dac44c7e`，版本 `1.5.1+13`、非 Debuggable、v2 签名和长期证书均复核通过。详见 `test-results/ai-context-stuck-recovery-20261109/VALIDATION.md`。
- 2026-11-09 物理手机签名迁移完成：`HONOR REA-AN00` / Android 15 原安装 `1.4.0+11` Debug 包；设备安装证书 `f026fcff0c43fb75287ba91a64cea8cf0aaba071aa07f532a12dd26f3b775aff`，正式长期签名证书 `51b5e2f3f44ce9374cb680a0173c6498a4e13c718c602a355a8b6a50523f4816`。完整快照含 179 个文件、SHA-256 `0bd72320ed10a686a7f4c14037b71c029f13bf03ae60980e8c1fbfcc2c43d2d8`；恢复时排除 3 个卸载后失效的 Keystore 凭据文件，最终 176 个文件恢复。正式覆盖安装成功，设备 APK 哈希 `e4bd3d65e3b02a05258670e9d8fc6e545dbc758456102f18d0030788c578a71b` 与公开 Release 完全一致，非 Debuggable，通知权限已恢复，首页无迁移门且原待办可见。详见 `test-results/phone-signature-migration-20261109/VALIDATION.md`。
- 2026-11-09 Android 手机 v1.5.0 发布完成：Release `phone-v1.5.0`（pre-release）；main CI `42585275215` / job `129053480590` success，Android Release `42585293796` / job `129053543183` success。公开 APK `90,977,347` 字节，SHA-256 `e4bd3d65e3b02a05258670e9d8fc6e545dbc758456102f18d0030788c578a71b`，版本 `1.5.0+12`，API 24/36、必要权限、v2 签名和长期证书均复核通过。详见 `test-results/phone-release-v1.5.0/VALIDATION.md`。
- 2026-11-09 `v1.5.0+12` Android 手机发布准备：版本升至 `1.5.0+12`；新增 `docs/releases/v1.5.0.md`；main CI 与 Android Release 定向门禁加入完全体模式设置、迁移、重试、恢复、附件、回收站和上下文测试。待推送、打 `phone-v1.5.0` 标签并核验公开资产。
- 2026-11-09 手机 50 例、真实模型与 900 秒长测通过：`SEC-001`–`SEC-100` 中手机适用 50/50，4 分 08 秒；标准 `integration_test` 路径真实 DeepSeek 完全体模式 `table_list` 工具往返 1/1；900 秒业务实际 907 秒，完成 37 条写入与读回、154 次模型请求，后台任务在切后台、锁屏 12 秒、唤醒重开应用后继续并完成最终答复。首次长测暴露检查点用量断言不允许 fixture 请求数领先一拍，已修正为容许 `requestCount ± 1`。未执行全量测试、平板、Windows 或物理手机。详见 `test-results/phone-50-longrun-20261109/VALIDATION.md`。
- 2026-11-09 完全体模式实现：设置快照升级到 v6、可移植设置 v2、会话库 v7；新增全局策略覆盖、启动安全检查点续跑、`finish_reason=length` 自动续写、瞬时故障无限退避重试、无累计本地检索、完整文件/压缩包输入、批量图片输入、会话/附件 30 天回收站、整段会话与普通设置工具。受保护控制面继续拒绝 API Key、模型端点/名称、图片出网、权限策略和完全体开关。`flutter analyze --no-pub` 0 issue，主机定向 179/179，Android AVD `full_agent_android_test.dart` 1/1；详见 `test-results/full-agent-mode-20261109/VALIDATION.md` 与 [ADR 0026](docs/adr/0026-device-full-agent-mode.md)。
- 2026-11-09 AI 页面超大工具回合压缩修复：真机 `HONOR REA-AN00` / Android 15 / `1.4.0+11` 确认设置连接成功且新短对话可返回 `OK`，旧会话失败原因是安全前缀摘要与完整工具回合共 `49,557` 字符超过 `48,000` 字符窗口。`AgentContextManager` 现保留最新工具调用/结果配对，并对超限工具正文按剩余预算压缩；状态、operation ID、对象 ID/revision、回执与 coverage 保留，完整 transcript 仍本地持久化。新增纯压缩回归与 ChatService 恢复工具回合集成回归，定向 29/29、目标 analyze 0 issue。详见 `test-results/ai-page-context-compaction-20261109/VALIDATION.md`。
- 2026-11-09 真机 Debug 数据恢复：用户授权卸载重装。Honor 系统本地 restore set 显示恢复完成但实际为空；重新安装后确认 `files/` 只有默认空表。随后导入 `H90y-v1.1.1-20261021` 实机备份，应用迁移门识别 `47` 条旧资料并创建 `1` 张表、`46` 条内容。迁移后 `items/*.md` 为 `46`、`tables/*.md` 为 `4`，首页重新显示原待办。完整 `files/`、`shared_prefs/`、`app_flutter/` 已导出为 `D:\Dsk\aitext-backups\phone-debug-20261109\aitext-full-data-20261109.tar`，SHA-256 `74581ca778e4a1037d0167e78fb7a1e0fc8285278e40b0eb991a807cb9eb184f`；同目录保存 Debug APK 和 `SHA256SUMS.txt`。
- 2026-11-09 Android 手机 v1.4.0 发布完成：Release `phone-v1.4.0`（pre-release）；main CI `42539611481` / job `128911389363` success，Android Release `42539816724` / job `128912007915` success。公开 APK 90,764,203 bytes，SHA-256 `68b8656703019b2628857540bcc2dfd64b69c2c961f6760a74f956a4a2677255`，版本 `1.4.0+11`，API 24/36、必要权限、v2 签名和长期证书均复核通过。详见 `test-results/phone-release-v1.4.0/VALIDATION.md`。
- 2026-11-09 `v1.4.0+11` Android 手机发布准备：新增 `docs/releases/v1.4.0.md`；版本升至 `1.4.0+11`；main CI 与 Android Release 定向门禁加入 Harness 测试；Android Release 改为从 `pubspec.yaml` 动态读取 build 号。待推送、打 `phone-v1.4.0` 标签并核验公开资产。
- 2026-11-09 GitHub main CI 通过：run `42499993545` 在提交 `21b3e11` 上完成 Dart 格式、`flutter analyze` 和迁移/秘书定向回归，全部 success。
- 2026-11-09 GitHub 发布：Harness 实现与真实模型验证已快进并推送到 `main`（`cbf1d9f`）。首轮 Flutter CI `42499771243` 仅在 Dart 格式门禁失败，4 个 Harness 文件已按 formatter 修正；本地全量格式检查 0 change、`flutter analyze --no-pub` 0 issue，修复提交推送后复验 CI。
- 2026-11-08 Android 真实模型 Harness 验证通过：`emulator-5620`（Android 15/API35，AVD `aitext_agent_c_phone`）真实 DeepSeek 用例 1/1，覆盖连接 `connection-ok`、普通回复、`table_list` 三默认表读取，以及完全权限在事件表 `content_create` 写入 `note`、操作卡 `applied` 和本地读回。设备最近 3000 行日志未发现 HTTP 400、FATAL 或未处理 Flutter 异常；临时测试已清理。详见 `test-results/android-real-model-20261108/VALIDATION.md`。
- 2026-11-08 AI Harness 升级：所有权限模式取消 2 小时/240 次请求累计预算和追加额度；用量账本升级为 v3，仅记录请求、工具和活动时长。完全权限新增回收站列表/预览/恢复与收纳目标读取，查重无法证明同一对象时新建并标记待核对；只读工具并行、写工具独占屏障，重复工具只提醒不硬暂停。`dart analyze lib test integration_test` 0 issue，定向主机 149/149，Android 15 AVD `table_ai_android_test.dart` 1/1 通过。详见 `test-results/harness-unbounded-full-access/VALIDATION.md` 与 [ADR 0025](docs/adr/0025-unbounded-flutter-agent-harness.md)。
- 2026-11-08 Android 手机 v1.3.0 发布完成：Release `phone-v1.3.0`（pre-release）；main CI `42403931513` success，Android Release `42403946155` / job `128497527923` success。资产为 `personal-ai-inbox-v1.3.0-android.apk`（90,731,435 bytes）和 `SHA256SUMS.txt`。
- 2026-11-08 公开 APK 独立复核：SHA-256 `a81c32f7382d194e42151a9ba59816ddaf9a3e91fdc417cb3afe4b95c9754fbb` 与 Release 清单一致；`versionName=1.3.0`、`versionCode=10`、minSdk 24、targetSdk 36；必要权限齐全；`apksigner` v2 通过，长期证书 SHA-256 `51b5e2f3f44ce9374cb680a0173c6498a4e13c718c602a355a8b6a50523f4816`。详见 `test-results/phone-release-v1.3.0/VALIDATION.md`。
- 2026-11-08 Android Release 失败修正：run `42403556704` 在 `Validate phone release tag` 失败，原因是工作流查找 `docs/releases/1.3.0.md`，实际文件为 `docs/releases/v1.3.0.md`。该轮未读取签名密钥、未构建 APK、未创建 Release；路径已修正。
- 2026-11-08 Android 手机发布准备：版本升至 `1.3.0+10`；新增 `.github/workflows/android-release.yml`，仅响应 `phone-v*` 标签，校验版本、API 24/36、必要权限和长期证书后发布 Universal APK 与 `SHA256SUMS.txt`，不构建 Windows。
- 2026-11-08 手机回归：`conversation_lifecycle_test.dart` 4/4、`conversation_large_history_ui_test.dart` 1/1；长历史覆盖 220 条消息、滚到最早位置、流式长回复、停止后保留草稿，生命周期延迟关停计时器在测试卸载后推进完成。
- 2026-11-08 最近任务划掉设备场景：phone AVD `aitext_agent_c_phone`、API35、ADB5041、serial `emulator-5620`，最终 source manifest `f9c8c219edb3218bb21b96d5225d2257fc8042bb0d2f101f5170537740cfde50`；真实打开最近任务并滑动移除 app task，冷启动 15 秒无新增模型请求，显式继续传入原 task ID，原 operation 幂等回执重复出现但均绑定同一 entry/table，最终仅一条内容。证据：`test-results/secretary-agent-implementation/luna-c/20261107T183122Z-phone-recents_swipe_recovery/`。
- 2026-11-07 最终设备候选通过：manifest `c283f93b19703686ab7caa0da802e43ff8bb5c557051156c070c9e94f07f49bd`；phone 50/50、tablet 27/27；双端 `activity_recreate`、`force_stop_recovery`、`service_interrupted`、`service_restricted`、`service_timeout`、`notification_denied` 全部通过；phone 900秒长测916.934秒/47条、tablet 900秒长测917.914秒/47条，均通过后台/锁屏恢复、预算、回执及最终 SSE 文本渲染。详见 `test-results/secretary-agent-implementation/final-device-20261107/VALIDATION.md`。
- 2026-11-07 主机定向回归：`secretary_conversation_ui_test.dart` 5/5，新增当前活动会话挂载和主动新建对话隔离回归；`app_background_lifecycle_test.dart` 6/6；相关四文件 analyze 无 warning/error，format/diff-check 通过。组合运行中的 pending timer/长历史输入可见性问题已由 2026-11-08 修复并通过。
- 2026-11-06 当前候选 host 重绑：`chat_service_agent_test.dart` 27/27，`model_client_stream_test.dart` 19/19，`secretary_host_smoke_test.dart` 15/15（SEC-083两次请求/287ms），`content_intake_test.dart` 25/25、`content_intake_recovery_test.dart` 3/3、`model_duplicate_decision_source_test.dart` 16/16；退出码均0。ChatService、ModelClient 与 smoke test SHA 及范围见 `test-results/secretary-agent-implementation/host-smoke-current-rebind/VALIDATION.md`。这替代 SEC-083 的11/05旧 host失败结论，但不代表设备矩阵或 A01–A36 全部闭合。
- 2026-11-06 phone 专用 AVD 当前源短场景复验：A31 Activity recreation、A32 force-stop 后冷启动无自动请求且显式继续原 task、A33 service_interrupted 均通过；Android API35 / Emulator37.2.12 / ADB5041，source manifest `733b7fbd6c53b158b98d032bbe70dfe935ef3a5a111a4ad568c4c1803248538a`。逐项命令与 APK SHA 见 `luna-c/20261106T115952Z-phone-activity_recreate/VALIDATION.md`、`20261106T120153Z-phone-force_stop_recovery/VALIDATION.md`、`20261106T115525Z-phone-service_interrupted/VALIDATION.md`。A32最近任务划掉、平板复验、A33通知拒绝/服务限制/超时、设备矩阵及双端900秒长测仍开放。
- 2026-11-06 phone `service_interrupted` 当前源设备短场景通过：显式恢复原 task ID，核验同一 assistant/task ID、第二轮 `content_verify`、条目唯一及写入回执复用；Emulator37.2.12/API35/ADB5041，exit0，manifest/APK 哈希及命令见 `luna-c/20261106T115525Z-phone-service_interrupted/VALIDATION.md`。定位前一失败为验收等待条件漏掉续跑验证回执，非生产恢复缺陷；只关闭此手机短场景，A33其余子项、A32及长测仍未闭合。
- 2026-11-06 专用 phone AVD 当前源 UI 矩阵：SEC-001+SEC-083 2/2，剩余48项48/48，合计50/50；manifest `621b70f1a444a55435b554ca966bd6d8fda607c9a08c337a9baead28635f88aa`，Emulator37.2.12/API35/ADB5041，`aitext_agent_c_phone`、serial `emulator-6200`、端口6200/6201。SEC-083两次模型请求后仍可继续提问。源清单、APK哈希、命令及日志见 `luna-c/phone-matrix-current-candidate-20261106/VALIDATION.md`。A31/A32/A33和长测尚未覆盖。
- 2026-11-06 A24 host closure: ManualContentIntake 7/7 and explicit keep-both UI 1/1 pass. Credential is checked against the reviewed candidate set and the kept item is persisted; prior or stale credentials cannot authorize a new save. Responsive UI test teardown initially exposed an unadvanced 2s lifecycle timer; advancing the fake clock fixed the test, which then passed 1/1. Source hashes and commands: `a24-manual-duplicate-authorization/VALIDATION.md`. Android UI and remaining A24 scope combinations remain open.

- 2026-11-06 phone longrun attempts 8–10：attempt 8 (`20261106T065144Z`, manifest `e246f5cde1536b2489d5ca3b23c58418218e6ad9fcce15506fd908ed75465619`) 修正无工具语义请求路由后暴露生产缺陷：ContentIntake 对完整模型 `create` 决策仍在 prepare/commit 两处返回 conflict。连续三次 fixture 错误后停止，保存事件与 `needsReview` checkpoint，未取得 Flutter exit code。新增回归修复为全部候选完整比较、决定为 create 且快照不变时允许新建；回归先红后绿，`content_intake_test.dart` 25/25，目标 analyze clean。attempt 9 (`20261106T065722Z`, manifest `8859787b81aa76cbe796835a7d1c34bb47f32e52ab87b3220128df4a7f731600`) 业务704.5秒/50次验证触及240请求上限，转 `needsReview`，未通过；事件和检查点已保存。attempt 10 (`20261106T071420Z`, manifest `7af72aeb2793c64687e151f99f668d221dd45512d029e60f3fb2a418c4035cbe`) 完成929秒业务、45条验证与205次请求，但最终流 UI 断言失败：已发出首段 SSE，10秒内未观察到匹配的 streaming assistant 消息。失败归档未生成 ZIP，且原 runner 无直接文件兜底。详见对应目录的 stdout/stderr/orchestration 日志。
- 新 phone attempt 11 (`20261106T073826Z`, manifest `19155ae127fba1401b925abb3fa7cb0df05e718ad4a822511f14d49f972ed76e`) 加入最终会话/消息状态诊断，归档失败时直接导出合成事件和检查点。业务从 `07:39:54.769Z` 开始，最后检查已有4条进度；仍在运行，尚未通过。`dart analyze integration_test/agent_task_longrun_android_test.dart` exit0（58条 style info，无 error）；本次最终状态代码尚待设备运行结论。完成/失败证据追加至 `test-results/secretary-agent-implementation/luna-c/`。

- 2026-11-06 phone longrun attempt 7：`20261106T063810Z-phone-longrun` 构建安装并进入业务（开始 `06:39:53.512Z`，task `16950`，后台锁定及进度1写入），约25秒后失败。实际只有6个 tool delta 帧，测试原断言要求8，属于断言下限过高；编排器同时因专用 AVD 无可见 keyguard 而拒绝 screen-off 状态。此尝试不计入900秒。App级临时跟踪还证明之前的“pumpWidget卡住”实际是 AVD 睡眠、渲染宽度为0；唤醒后 `pumpWidget`/`pump` 和 ready marker 均快速通过。候选将断言改为每个 verified action 至少2帧，并把后台屏幕测试定义为screen-off + Activity暂停，不强制无安全锁的模拟器显示keyguard。长测入口临时设置stay-on并唤醒设备，最后恢复原设置。新候选尚未复验。详见验收矩阵与 `luna-c/20261106T063810Z-phone-longrun/`。

- 2026-11-06 状态纠正：旧段落中 SEC-083 host 未通过、ADB 不可用的描述已由本日复验取代。使用 Emulator 37.2.12、ADB server 5041 和专用 `aitext_honor_phone`/`aitext_galaxy_tab` AVD，手机 SEC-001 与 SEC-083、平板 SEC-003 通过。手机 SEC-083 两次模型请求，6.655秒。平板 SEC-001/002 误选了仅手机场景，在加载时因平台过滤为0失败，不是业务失败。设备 manifest/APK哈希及完整日志见 `test-results/secretary-agent-implementation/ACCEPTANCE.md` 和 `luna-c/20261106T...` 目录。此证据不代表矩阵或900秒长测通过。

- 2026-11-06 SEC-083 host 通过：ModelClient stream tests 19/19、ChatService HTTP body cancellation barrier 1/1、SEC-083 host smoke 1/1（2 requests/684ms）。详见 `host-smoke-20261105/VALIDATION.md` 的后续复验节。该复验仍需绑定冻结源码清单。

- 2026-11-06 phone longrun 历史 attempts 1–7均未通过900秒。最新在运行候选 `20261106T064433Z-phone-longrun` 已完成业务启动、任务后台运行、两条进度写入和 screen-off/Activity暂停/唤醒恢复段；尚待至少900秒、暂停检查点、恢复或完成终态与写入回执。此前“本轮不得重启”及手机尝试耗尽已过时：主 SDK Emulator 与独立 ADB 5041 已恢复，可使用专用 phone/tablet AVD。每轮实际 boot/API/AVD读值目前尚未写入脚本日志，后续补足证据落盘。历史失败日志保留，见 ACCEPTANCE.md 和对应 `luna-c/` 目录。

- 2026-11-06 phone longrun attempt 5：`20261106T060959Z-phone-longrun` 构建安装成功；阶段 marker 证明应用支持目录读取、合成目录删除/创建、SQLite index 打开及 `AppRuntime.bootstrap` 全部完成。`ss` 确认 loopback 模型 fixture 在 `127.0.0.1:47631` 监听。随后 8 分钟仍未出现 `AGENT_TEST_READY`，故停在 harness 返回与首次 widget pump 之间，没有开始业务计时。新增 `harness_open` 与 pump 前后 marker，待按新 manifest 再定位；该次不计入900秒。详情见 `luna-c/20261106T060959Z-phone-longrun/`。

- 2026-11-06 phone longrun attempt 6：`20261106T061900Z-phone-longrun` 在同一启动门内进一步定位。标记到达 `harness_open` 和 `pump_widget_start`，未到 `pump_widget_done`；设备 Activity 进程存在且 loopback 47631 正监听。故障位于 app widget 首帧构建/泵送范围，8分钟门禁终止并完成进程清理，没有开始业务计时。下一步在 App initState/build 与首帧边界加可移除诊断，或最小化模块定位阻塞依赖。该次不计入900秒。详情见 `luna-c/20261106T061900Z-phone-longrun/`。

- 本轮三名 `gpt-6-luna/high` 子代理已完成本阶段分工：手工查重/接收预审、执行内核暂停结算修复、Android长测归档与设备预检。代码仍为未提交候选；Android长测闭环未通过，当前可复核进度以本节最新日期条目和 `luna-c/PROGRESS.md` 为准。

- 2026-11-05 最新宿主 smoke：SEC-034/036/038 首轮因 lifecycle gate timer 在 teardown 失败；runner 显式卸载并推进假时钟后，修复候选合并复验3/3通过（缓存预算1150字符、无命中结果389字符、第21次检索 `batch_boundary`）。SEC-083 最新 runner 候选正式复验仍超时；诊断看到 completed 已到 ChatService，但 Workspace 未收到 terminal，ModelClient onDone 延迟约30.55秒。关闭屏障回归仍失败，临时插桩/不验证改动已清理，根因修复未完成。报告见 `test-results/secretary-agent-implementation/host-smoke-20261105/VALIDATION.md`。A05 Workspace 主机回归不替代 UI/设备验收。


- 后续组合验证：文件/索引写日志回滚再补索引失败、日志删除失败两例，共9/9通过；查重准备中撤权的真实processor回归1/1通过，写前guard重读原新增与目标修改授权（processor-prepare-revocation.log）。手机首轮完成但有4项失败（3项旧检索契约断言、1项停止后续问待诊断）；未通过最终设备门禁。原runtime子代理因自身线程额度停止已交回写权，新代理Laplace接手主辅预算、追加原子性与恢复ID修复。

- 2026-11-04 后续：写日志新增内容新建/更新及文件写入前/后的四种中断恢复，共7/7通过（table-write-journal-recovery.log）。修复后 SEC-001 手机冒烟通过（emulator-phone-smoke-SEC001-20261104-091232/phone.log），手机矩阵已执行到业务场景并出现检索相关失败，正在区分修复与旧契约断言；完整矩阵仍未通过。查重写前新增授权guard，父代理负责processor接线，语义召回/捕获责任代理继续合流，暂不能宣称相关回归已收敛。

- 组合审查发现预算漏计、读取策略 scope、恢复回执复用等问题，已分配原责任代理修复。父代理完成操作位置请求指纹与旧回执保护、批内逐项重读策略：处理器/会话存储 16/16、运行时/接收集成 5/5 通过，见 parent-replay-permission.md。Android 首轮 VM 消失根因为 Application 内同步启动引擎触发启动 ANR，已有源码修复但新设备 smoke 尚待结果。

- 2026-11-05 tablet longrun attempt 1/2 在页面切换后显式暂停时，测试于 `isChatGenerating == false` 后立即读取检查点，未见 paused turn。根因是生成完成信号先于 worker 的最终检查点保存；`pauseGeneration` 现等待当前 turn completion（worker 在保存 paused turn 后完成）。定向主机红绿通过；设备长测未复验，不能据此记 Android A36 通过。详情见 `test-results/secretary-agent-implementation/pause-generation-checkpoint/VALIDATION.md` 与 `luna-b/PROGRESS.md`。

- 2026-11-05 平板长测归档修复候选已通过静态复核：失败时先有界暂停，按原 conversation/task/assistant ID 核对最终 checkpoint；不能确认一致则只导出 best-effort 证据并标 `snapshot_consistent=false`。41 项 fake/static 检查通过，manifest `6b307fa94c0d75aaf948a6d6d02ce47e18ade7dbdb6a4508f454c34ea5e95b33`；这不是 Flutter integration 或设备运行证据。平板 attempt 2/2 启动 AVD 后，模拟器自报 boot complete，但宿主5622/5623都无listener；ADB 5037与5041均为空，设备/guest状态不可读。未build/install、未改权限、未进入长测。随后只读检查找到精确环境冲突：Emulator 37.3.6仅支持偶数控制台端口5554–5584及其后一个ADB端口；Windows IPv4/IPv6 TCP排除范围包含5120–5619，阻止所有支持端口，而5622/5623虽可绑定但不受emulator支持。未改全局设置，不再在当前主机盲目启动。细节见 `luna-c/20261105T-tablet-longrun-attempt2-adb-preflight/phase-summary.md`、`avd-port-diagnostic/VALIDATION.md` 和 `luna-c/20261105T-longrun-quiescence-final-static/phase-summary.md`。

- 2026-11-05 A01–A36 预审及 A26 retry receipt recovery 定向修复完成：A26 两个回执/检查点撕裂点通过主机红绿，A26 malformed/重复关联按需转 `needsReview`；修复只更新本地 receipt，不重扫、不重写表、不自动派发。pending action 的持久化和用户显式继续（含预算/权限恢复、重启后继续原 action）已有主机证据；预算或权限恢复本身自动续扫未覆盖。A31/A33设备失败；A32 文件后端恢复主机回归现已通过但 Android force-stop/冷启动设备验证仍未覆盖；A36手机/平板均无15分钟业务通过。证据见 `a26-pending-intent/VALIDATION.md`、`a32-file-backed-recovery/VALIDATION.md` 与 `a01-a36-preliminary-audit.md`。手机 longrun此前已达场景尝试上限；平板第二次未能建立ADB，不能继续盲目重启。候选未完成设备闭环，禁止创建“验收完成”提交。
- 2026-11-05 A33 host runner identity check：service-restricted READY/RESULT 现绑定 assistant message ID 和持久 task ID；恢复 barrier 与 Dart fixture 同时校验两者，duplicate/malformed marker fail-closed。9项定向 PowerShell自检、PowerShell AST和Dart analyzer通过。旧设备 `DENIED→Activity thaw→READY→resume ACK→业务写入/回执` 链仍未成功；notification_denied 安装后权限拒绝修复也未设备复验。证据见 `luna-c/a33-service-restricted-host/VALIDATION.md`。设备尝试上限和 ADB 启动阻塞保持不变，不推定设备通过。

- 2026-11-05 A22/A25 当前查重源码复验绑定：旧通过日志哈希未覆盖现工作树，故重跑 `content_intake_test.dart` 与 `table_repository_test.dart`，47/47通过，两个测试文件 analyze 无诊断；绑定 `content_intake.dart` 与 `table_repository.dart` 当前 SHA。覆盖同标题不同课程/日期保持独立、prepare 后版本变化拒绝、commit 精确重复重检、语义证据补充及撤权；设备并发仍未覆盖。证据见 `test-results/secretary-agent-implementation/a25-source-rebind/VALIDATION.md`。

- 2026-11-05 A35 迁移源哈希重绑：旧 coordinator/test manifest 不匹配当前工作区，定向重跑迁移协调器与 file migration 两组测试，15/15通过；两个目标文件 analyze 无诊断。当前 coordinator 和测试哈希见 `test-results/secretary-agent-implementation/a35-migration-source-rebind/VALIDATION.md`。Android/Windows迁移与完整撤权组合仍未覆盖。

- 2026-11-05 A29 摘要压缩持久化失败：ChatService 回归3/3，Workspace runtime suite 18/18。真实 Workspace callback 故障注入验证摘要消息写入后 task checkpoint 失败时，旧代码的最终 failed assistant 仍带摘要；修复改为候选 assistant，message 与 checkpoint 都保存成功后才替换内存 transcript。失败时保留原 transcript、failed generation 终态且模型请求为0。证据与四份源哈希见 `test-results/secretary-agent-implementation/a29-compaction-save-failure/VALIDATION.md`；容量/三步停滞与跨进程恢复组合仍待审查。

- 2026-11-05 A32 文件后端 runtime 重建回归：将原 generation/receipt 恢复测试改用隔离临时目录、`IoVaultStore`、SQLite index 与 conversation store，并在重建时使用全新 adapter 实例。定向测试 1/1、单文件 analyze 无诊断；证明冷启动逻辑不自动重放请求、原 task/assistant/generation 和回执可恢复、显式继续后内容仍唯一。该主机测试不能代替 Android force-stop/划掉/冷启动验收。完整命令及边界见 `test-results/secretary-agent-implementation/a32-file-backed-recovery/VALIDATION.md`。A32 仍等待设备验证；A36 端口环境阻塞不变。

- 2026-11-05 A23 重复改期通知业务幂等：稳定键改用日程 ID + UTC 规范化原通知发生时间；恢复批账本校验通知正文、目标和对象状态，来源相同但内容冲突时 fail-closed。工具说明/系统规则要求模型使用原通知发生时间并保持稳定；缺少有效时间不派发工具。Workspace→SSE→ChatService→TableActionProcessor→TableRepository 四份定向主机测试 66/66，覆盖跨消息复用、日程跨表移动后复用、不同通知时间独立、恢复状态与损坏账本拒绝重放；analyze/diff-check通过。Android/平板尚未复验。详见 `test-results/secretary-agent-implementation/a23-schedule-notice-dedup/VALIDATION.md`。A01–A36和设备闭环未完成。

- 2026-11-04 收敛验证：收纳目标重选与表页 7/7 通过（inbox-ui-recheck.log）；新增连续 100 轮普通对话确定性用例通过（ordinary-100-turns.log），检查每轮完成及上一轮上下文保留。这些属于主机定向验证；Android VM isolate 中断与原生长任务验收仍在处理，不能代替手机/平板结果。

- 任务恢复界面定向 2/2 通过（agent_task_status_card_test.dart）：额度耗尽明确提供追加入口，未知副作用未核对时不继续。集成期间 late conversations 的取消回调提前取值导致编译失败，已改成延迟 closure 后通过重验；日志 agent-task-status-ui.log。模拟器连接故障及其余计划验收继续处理。

- 模拟器首轮业务驱动连接失败：emulator-phone-20261103-235751/result.json exitCode=1，构建/安装成功但 isolate 连接后消失，未执行到业务用例；正在排查，不能写成已验收。deleted_inbox_ui_test 的假时钟 teardown 等待已修复，最新 1/1 通过见 deleted-inbox-ui-test.md；旧10分钟超时日志保留。逐项未完成审计见 test-results/secretary-agent-implementation/ACCEPTANCE.md。

- 2026-11-04 父代理补齐本地表写入 before/after 日志与启动恢复：文件/索引提交之间中断可结算，遇外部修改保留日志并阻断覆盖。table_repository_test.dart 23/23、table_write_journal_test.dart 3/3 通过（日志 table-write-journal*.log）。隔离 Android 15 手机模拟器 emulator-5580、ADB 5041 已启动且 debug APK 安装/前台启动通过；秘书业务矩阵仍待完整结果，不能据此宣称模拟器验收完成。

- 后续界面接线：表页新增收纳目标选择/保存入口，会话新增暂停任务继续与额度追加卡，三项相关目标 analyzer 无诊断。缺目标进入独立表页时发现 Material 祖先缺失，已修复容器；deleted-inbox-ui-fixed.log 对应重验仍未结束，禁止据此写成通过。Android Kotlin 会话缓存加入忽略规则，避免生成文件进入正式提交。

- Agent 集成审查继续：修复首页删除待办收纳目标后 firstWhere 崩溃，改用 InboxAssignments 并提示归表；日历无表时明确提示，预置表卡开放改名/删除。三个页面定向 analyzer 无诊断。新增 deleted_inbox_ui_test.dart 与既有表页/首页回归仍在运行，暂未得出通过结论（日志 test-results/secretary-agent-implementation/deleted-inbox-ui.log）；同时审查捕获入口查重和默认保守语义比较器尚未接生产模型的问题。

- Agent 实施进行中：集成检查 test/table_ai_runtime_test.dart、chat_service_agent_test.dart、conversation_workspace_agent_runtime_test.dart、conversation_workspace_scheduler_test.dart、conversation_policy_store_test.dart 合计 27/27 通过，日志 test-results/secretary-agent-implementation/integration-check.log。会话库 v6 已同步迁移协调器支持版本，专门验证 v5 不得完成升级；sqlite_migration_coordinator_test.dart 5/5 通过。未执行全量测试；完整任务恢复和模拟器场景尚未验收。

- 2026-11-03 专用设计已完成：四种权限预设、可删预置表/收纳映射、全局知识策略授权、中文检索/分页/分段、写前查重/自动补充、提交后核对、持久化任务与后台承载均有目标规格。分成 A–F 实施包，列出 A01–A36 定向验收。当前只核对文档/源码事实，业务场景均未执行；验证报告见 test-results/secretary-agent-design-20261103/VALIDATION.md。

- 2026-11-02 Android 模拟器验收：API 35 手机 AVD 411.4dp 与平板 AVD 1280dp 串行运行全部 75 个 Android 秘书场景，手机 50/50、平板 25/25 通过；真实 DeepSeek 连接测试、寒暄和 `table_list` 工具往返通过，首页往返保留回复，应用日志无 HTTP 400 或崩溃。Windows 25 场景按范围未跑。环境绕过与证据见 `test-results/secretary-ai-emulator-20261102/VALIDATION.md`。

- 2026-11-02 真实 DeepSeek 秘书修复：设置页纯文本诊断成功而完整聊天请求返回 HTTP 400，服务端明确拒绝 `tools[0].function.name` 的点号。12 个表工具已改为 `table_search`、`content_create` 等下划线出网名，本地动作和持久化操作卡继续使用点号操作名；相关定向测试 13/13、目标分析目标无诊断、同长期证书 release 构建与 v2 验签通过。APK SHA-256 `8B9F21665DEEEE09065E9D46FB94E88434AEB4E9B0E42249837B1E86B2A8B26D`。真机覆盖安装未执行，因为无线调试连接在构建期间变为 `offline`；详见 `test-results/secretary-ai-tool-names-20261102/VALIDATION.md`。

- 2026-11-02 H90y 升级阻断已复现并完成最小代码修复，定向迁移测试 10/10、analyzer、格式与签名 release 构建通过。已完成 H90y 初次迁移及后续正常修改引起的重启阻断修复，并按用户要求清理非全局旧源、保留备份/全局知识/完成凭据；最新同签名包安装成功，4 张表/66 条内容保持，旧源横幅消失，清理后两次冷启动通过。详见 test-results/h90y-upgrade-20261102/VALIDATION.md。

- 2026-11-01 发布收尾核验：Release `41218586972` success（head `7b42167`），main CI `41219403100` success（head `34b8543`）。资产 4/4 完整，APK/setup/portable 的本地 SHA-256 与 GitHub API digest、`SHA256SUMS.txt` 一致；APK 经 `aapt2` 核验 `versionName=1.2.0`、`versionCode=8`、minSdk 24、targetSdk 36，经 `apksigner` 核验证书 SHA-256 `51b5e2f3…`（v2 方案）；Windows 便携包 23/23 条目与 zip 一致，EXE `FileVersion/ProductVersion=1.2.0+8`。证据见 `test-results/v1.2.0-release-acceptance-20261101/`。
- 未验收项：Android 秘书页 AVD 定向集成测试未执行（`adb devices` 为空，有界搜索无 `emulator.exe`，本机 SDK 无 system-images）；Windows 启动未执行（`%APPDATA%\com.yuanfang.aitext` 存在真实数据，无法证明隔离）。二者不得写成已通过。
- 已将改版细化为 10 个工作包、80 个执行步骤，并映射 13 类需求。P0/P1和P2首轮本地存储/repository/runtime接线通过 28 项定向测试和 analyzer。P2记录的 Flutter integration driver VM Service掉线为历史失败；之后 `flutter test -d emulator-5554 integration_test/...` 的相关AVD场景已通过。详情见 `test-results/table-notebook-p2-20261030/VALIDATION.md` 和 P8/P9最新验证记录。
- P3数据层首轮已实现：SQLite v10恢复账本、单条10分钟撤销、整表30天恢复/到期硬化、跨表日程引用清理/复原，以及通知事件与原日程同批更新/撤销。P5b增加v9→v10字段恢复scope迁移；P3原21项用例及Android默认表重启核验通过。
- P4 迁移工具只扫描旧 Markdown，不改旧源：预检/阻断、确定性映射、vault与SQLite/会话/设置备份清单、journal重放/hash回滚和 Android/Windows容量探测已实现。发现旧资料时AppRuntime启动进入只读门；用户确认后生成新格式副本并保留源件。迁移完成后主应用的表、首页、日历、秘书、全局知识与设置可用；普通旧条目不再编辑，已迁移身份跳转至表格式，全局知识仍确认后改动，旧同步入口关闭。Android15 AVD用合成资料验证，真实旧事项未迁移。
- AI 秘书对话和首页已按 DeepSeek 手机端/网页端的层级重整。
- 日历整合日程、我的一天与待办；成果详情、知识和待处理由独立页面承载。
- P8旧入口替换完成：表页接管捕获审核和旧草稿复制；全局知识候选保留独立确认；同步冲突在同步页处理；事项与独立待处理页面已移除。捕获高置信内容进入默认表，低置信/失败回退为普通笔记；表搜索覆盖笔记标题和正文。
- 笔记列表已按参考图增加跨表卡片，显示笔记总数、最近7天/月份、标题摘要、日期和所属表；表管理通过“查看表”进入。确定性捕获也新增“今天老师调整了考试范围”的发生事件规则，普通日期笔记仍保持 note。
- P8/P9最新主机回归51/51、旧会话恢复/AI工具回归8/8、22个改动分析目标无诊断；迁移服务主机14/14、迁移后 runtime/global knowledge/sync路径17/17。Android15 AVD表页/笔记列表/事件捕获1/1、AI建考试日程/改期/筛选/删表重启恢复1/1、迁移后完整主导航/全局知识修改重启/旧事项跳转3/3通过。
- 最终 Android Debug 候选已安装到此前没有 Aitext 包/数据的 Android15 AVD。向该独立应用目录放入4个合成旧 Markdown 文件后，启动只读迁移门、人工确认迁移、强制停止/重启均通过；旧源4个 SHA-256 全部保持一致，新表和3条内容的 ID/正文/归属可读。迁移后主应用首页、日历、秘书、表页、全局知识均可达；旧事项链接跳转到迁移表，旧同步入口关闭。截图与源文件在 `tests/agent-temp/table-notebook-p9-avd/`。Windows Release候选只构建，未启动验收。
- 本轮无真实用户资料迁移、真实模型API、真实云同步、真实通知或物理设备验收。AVD迁移样例均为合成资料；不能据此宣称真实资料升级完成。
- P5a–P5c已接表与笔记、字段、跨表映射、选项安全维护和整表预览恢复；P5d表页通过320/800/1280宽度主机回归26/26。P6接入表日历投影/筛选、日期上下文创建和首页排序表模块。P7接入按表检索与内容操作、日程改期联动及对话结构确认卡。P8首页笔记区现在按参考图分组显示卡片，管理表作为独立视图。完整分析视觉对照未做。
- 2026-10-31 秘书嵌入式导航改动：AppShell 保持同一秘书实例，手机底栏/桌面侧栏始终由主壳显示；隐藏时关闭输入焦点、附件面板、语音和对话抽屉，主页面往返保留未发送草稿及会话。分享请求队列按到达顺序处理，取消目标切换后消费请求，避免重复确认。宽度回归覆盖 320/800/1280。会话生命周期和秘书 UI 定向测试 8/8、9 个 Dart 分析目标无诊断。Android 15 AVD 可启动，但集成测试 APK 构建未完成：系统默认 E: 路径不可用；D: 缓存缺少 AGP 8.11.0 依赖，联网解析时 TLS 读取无进展；真实设备流程未验证。报告见 `test-results/secretary-embedded-20261031/VALIDATION.md`。
- 首轮 15 个 Markdown 文件的静态核对通过：95 个本地链接、空白检查及既有交接历史保留检查通过；未运行应用测试、构建、模型调用或设备验证。详情见 `test-results/table-notebook-plan-20261029/VALIDATION.md`。
- 上轮收敛内容分类、普通笔记兜底与字段范围；5 个 Markdown 文件、22 个本地链接、空白及全部既有交接历史保留检查通过，详情见 `test-results/table-notebook-rules-20261029/VALIDATION.md`。未运行应用测试或修改业务代码。
- 本轮确认事件联动和回收站 30 天规则；5 个 Markdown 文件、22 个本地链接、空白及全部既有交接历史保留检查通过，见 `test-results/table-notebook-lifecycle-20261029/VALIDATION.md`。仍未实现联动或恢复功能。

## 7. 风险、阻塞与下一步

- API 35 模拟器的小组件门禁已完成；荣耀 90 真机、API 24–30 固定行、平板与 Windows 专项仍未覆盖。荣耀真机未验收不阻塞本轮模拟器通过的 Android 预览发布，但发行说明必须明确标注。


### 风险与边界

- 2026-11-09 完全体模式取消的是应用层累计上限，不取消模型供应商硬上下文/输出/额度、网络、磁盘或 Android/Windows 生命周期。系统强制停止或设备重启后只能在下一次打开应用时自动恢复安全检查点；不确定副作用先核对回执，不盲目重放。AI 仍不可读取/修改 API Key、模型端点、权限策略、完全体开关、系统文件或执行系统命令，也不新增互联网搜索。
- 2026-11-09 当前手机安装的是 Android Debug 签名包，不是公开长期签名包；后续正式版覆盖安装需要先处理签名差异，不能直接假定可平滑升级。Honor 系统本地备份此前恢复为空，因此 `2026-10-21` 之后的会话、附件、设置及新增/修改内容未恢复，旧备份也未包含 API Key。设置页当前停在 API Key 输入位置且显示“模型未配置”，需用户重新输入 Key。
- 2026-11-08 Harness 无累计任务预算不等于无限请求超时或无限上下文：单请求响应头/流空闲/总期限、网络重试、上下文压缩、CAS、幂等、写日志和 Android 生命周期限制继续有效。完全权限仍不包含 API Key、任意文件、SQL、Root/OS 权限或修改自身授权。
- Windows 当前 TCP 排除范围包含 `6172–6271`，因此最终设备验收使用未排除的 `5620/5621` 与独立 ADB 5041，serial 为 `emulator-5620`。phone/tablet 最终矩阵、双端恢复场景和双端900秒长测均已通过；若系统排除范围或 Emulator 版本变化，先重跑端口/AVD预检再执行设备验收。
- A26 `conversation_workspace.dart` 后续有源码变化，旧20项测试的源绑定过期。本轮重跑当前源码下 retry recovery 3/3、A32 文件后端恢复 1/1，并对 Workspace 及两份测试 analyze 无诊断；详情与当前 SHA 见 `test-results/secretary-agent-implementation/a26-pending-intent/VALIDATION.md` 和 `a32-file-backed-recovery/VALIDATION.md`。完整20项组合与设备进程终止仍未复验。

- 发现专用设计第9节仍残留设计阶段‘本轮不执行A–F／没有执行业务用例’，与当前实施状态冲突。本轮将其改成验收目标和实际证据入口，不据文档文字声称已完成；历史设计验证记录保留。



- 隔离模拟器的旧5580/5600端口位于Windows管理的排除TCP范围5520–5619，Android启动成功不等于ADB传输可用。C使用未排除端口与显式TCP连接排查，不修改全局网络或排除设置；原设备失败证据保留。


- v1.2.1 是上一公开版本，v1.3.0 是当前 Android 手机候选。不得用旧版设备证据替代 v1.3.0；也不得把 Android 专用发布解释为新的 Windows 或平板验收。



- 2026-11-03 记录的新旧语义冲突已由 `111f996` 的实现收敛：预置表删除/收纳映射、标准与完全权限、全局知识策略授权和写前查重已进入 v1.3.0 Android 手机候选。A01–A30、A34–A35 的剩余主机组合仍不能据此宣称全部完成。
- DSH 手机壳运行清单固定的是上游 1f81c047，当前 master 8bd07339 不能当作 APK 实际能力证据；未下载/解包 APK。参考项目未证实表业务语义查重。本项目自动合并仍需实现后的语料与并发验证，不能承诺绝对无误合并或跨设备唯一。

- 2026-11-05 的 tablet longrun attempt 1/2 与 ADB 启动失败保留为历史证据；2026-11-07 manifest `c283…49bd` 已在 `emulator-5620` 上通过 tablet 矩阵、全部恢复场景与900秒长测，旧阻塞不再作为当前风险。

- 本机 Android Emulator 需要将 `ANDROID_EMULATOR_HOME` 指向可写的隔离目录，否则 `C:\Users\18377\.android` 的异常会使其反复创建特性标志锁失败。两个模拟器同时运行时资源不足，应按手机、平板串行执行。

- D 盘容量极低，当前生成的 `app/build` 已迁到 `C:\CodexBuild\app-build` 并以目录联接保留原路径；这是本机构建环境安排，不进入 Git。D 盘后续仍不宜承载大型 Flutter/Gradle 产物。

- 2026-11-02 为定位 HTTP 400，真机设置页 Base URL 曾临时切到 `http://127.0.0.1:7077`，通过 ADB reverse 让电脑代理转发到 DeepSeek；诊断结束后无线调试掉线，尚未恢复手机配置。重新连上设备后的第一步必须覆盖安装当次同签名 APK，并把 Base URL 恢复为 `https://api.deepseek.com`。代理与诊断临时文件不得提交。

- 用户于 2026-11-02 要求迁移后清理老数据。ADR 0023 取代旧文档活动目录保留源件的规则：核验备份后清理非全局旧源，保留备份/完成凭据，清理可续跑；历史验证记录不改写。

- 2026-11-02 后续真机复现迁移完成后正常修改内容引起的启动阻断；此前立即重启通过不覆盖此场景。已修正完成凭据读取，不把当前内容要求恢复成旧快照；真机现有已修改数据上两次冷启动通过，状态见最新记录。

- 2026-11-02 真机发现旧规划把“过去有日期的安排”也列为阻断项，与保留原安排且不推断发生状态的升级目标冲突，造成 H90y 升级停在只读门。本轮修正为有开始时间即保留为日程；无开始时间仍阻断。此前“过去/无日期均阻断”的记录描述历史实现，由本条取代。

- 新目标替代旧文档中的事项聚合、固定四类成果和独立待处理页设计；这是有意的产品改版。旧方案/现行同步协议保留已发布 v1.1.5 的格式与历史规则；本地新 schema 和迁移契约已首轮实现，跨端表同步和协议切换仍待设计。
- P3 的本地恢复与事件联动事务已实现首轮，并由表页/AI 表工具接入；尚未纳入真实同步协议。整表删除的跨端墓碑/恢复前像同步策略仍需专门同步 ADR；现阶段只能承诺本机 30 天恢复。
- P4 已接只读启动门和确认迁移副本入口；候选已在空 AVD 的合成旧文件目录上通过迁移确认、主应用导航、重启及源哈希检查。旧数据源和新格式副本可同时读回；普通旧格式编辑和旧同步入口关闭，全局知识独立确认仍可用。vault与数据库快照在迁移 journal 中关联；跨进程或外部同步同时写入不能由当前进程 barrier 阻止，真实生产资料的备份恢复仍须单独完成。
- 真实云盘、跨端同步和到点提醒尚不可用；Android 专用 Agent 前台服务通知已接。
- Windows 包未进行代码签名。
- Android 旧版 v1.1.3 及更早版本的预览包不保证可直接升级至固定签名版本；升级前需备份应用数据与 Markdown 主库。

### 下一步

1. 将 `v1.6.0+14` 发布准备提交推送至 `main`，等待该提交 main CI 成功。
2. 推送 `phone-v1.6.0` 标签，等待 Android Release 成功并从公开 Release 复核 APK、SHA-256、版本、API 与长期证书。
3. 荣耀 90、API 24–30、平板/Windows、云盘同步和到点提醒继续单独验收。

## 8. 变更记录

### 2026-11-10 / 准备 Android 手机 v1.6.0 多表小组件预览版

- 交付：修复 API 31+ 集合项点击、4×2 短列表和 4×4 滚动阈值；新增集合点击 receiver；版本升至 `1.6.0+14`；新增 v1.6.0 发行说明并更新合同、ADR、README 与交接。
- 验证：API 35 AVD 手机矩阵 50/50；900 秒长测实际 921 秒、47 条写入/读回、219 次请求；小组件主机定向 33/33；多尺寸、多实例、独立绑定、归档恢复和冷进程点击通过；`v1.5.1+13` 同签名升级保留 5 张合成表、17 条条目和 1 个会话。
- 状态：发布准备中；尚未提交、推送、打标签或创建 GitHub Release。
- 风险/下一步：荣耀 90 真机与 API 24–30 固定行未实测；需完成 GitHub main CI、标签 Release 和公开资产复核。

### 2026-11-10 / Android 多表桌面小组件接入

- 交付：Android 设置、可配置多表投影、启动器实例绑定和点击，普通模式只读、完全权限可管理逻辑卡片；新增 ADR 0027 与定向 CI 检查。
- 验证：定向宿主 45/45、目标 Dart 分析无诊断、Debug APK 构建及 APK 元数据核验通过。详见 `test-results/home-widget-v1/VALIDATION.md`。
- 状态：用户同意设备验收延期；模拟器和真机安装、桌面交互、覆盖升级及发布均未执行。

### 2026-11-10 / 冻结 Android 多表小组件合同

- 交付：配置、投影、原生通道、秘书权限合同与共享合成快照。
- 验证：隔离 Android 原型 APK 已构建并验签，共享合成快照解析通过。按用户要求未安装到模拟器或手机；生产代码尚未接入。验证及剩余项目见 `test-results/home-widget-v1/VALIDATION.md`。

### 2026-11-09 / 发布 Android 手机 v1.5.1 补丁预览

- 任务：发布超长工具回合恢复死循环修复，并验证 APK、签名和公开资产。
- 变更：版本升至 `1.5.1+13`；新增 `docs/releases/v1.5.1.md`；安全摘要回退低于模型硬上限时允许继续；补充完整发布门禁和物理手机恢复验证记录。
- 验证：main CI `42600289991` success；Android Release `42600311129` success，耗时 14 分 22 秒；完整 Android 发布门禁 295/295、Analyze 0 issue、公开 APK 哈希/版本/v2 签名/长期证书核验通过。
- 状态：GitHub Release `phone-v1.5.1` pre-release 已发布；物理手机当前运行同签名测试包并已证明任务恢复运行。
- 风险/下一步：无线 ADB 掉线，尚未用公开 APK 覆盖测试包和确认原任务最终完成态；设备重连后继续。

### 2026-11-09 / 修复中断任务反复卡在等待核对

- 任务：修复物理手机 AI 页面的任务中断卡死，并避免通过删除软件和重导 10 月数据造成后续数据丢失。
- 诊断：临时安装同签名可调试包并读取检查点及 SQLite。唯一任务 `agent_1794204476923870_1` 的 `needs_review` 恢复时，最新工具回合约 66 KB；`AgentContextManager` 无法压缩超大的工具调用参数，只能返回 `上下文无法安全压缩`，每次确认都会再次失败并写回同一错误。
- 变更：新增完整工具回合无法压入窗口时的安全摘要回退；摘要保留用户目标、补充要求、对象 ID/版本、操作回执、待核对冲突，并标记 `latest_tool_round_compacted`。新增上下文管理器和 ChatService 回归。
- 验证：新增回归先红后绿；`agent_context_manager_test.dart` 3/3、`chat_service_agent_test.dart` 31/31、完整 Android 发布门禁 295/295、`flutter analyze --no-pub` 0 issue、formatter 271 文件 0 change。物理手机安装 `1.5.1+13` 测试包后，原任务由 `needs_review` 转为 `running`，请求数和工具调用继续增长并出现多批移动回执。
- 状态：代码修复和“恢复后不再卡死”验证完成；待发布正式 `1.5.1+13` 并在设备重连后确认最终完成态。提交元数据使用仓库既有 `Distant-scout` 身份。
- 风险/下一步：安全摘要会丢弃无法保留的完整工具参数正文，但对象身份、版本、回执与冲突仍保留；完整原始 transcript 继续保存在本机。

### 2026-11-09 / 物理手机从 Debug 签名迁移到正式长期签名

- 任务：解释并解决物理手机无法用正式 `v1.5.0` 覆盖旧版本的问题，保留已恢复的表、内容和会话数据。
- 诊断：设备原安装 `1.4.0+11`，包属性含 `DEBUGGABLE`，证书 `f026fcff...3b775aff`；公开 `v1.1.4`、`v1.4.0`、`v1.5.0` 均使用 `51b5e2f3...523f4816`，正式发布签名没有变化。
- 变更：完整归档应用私有数据；构建正式长期签名且可调试的临时迁移 APK，恢复 176 个非凭据文件；覆盖安装公开 `v1.5.0+12` 后核验设备 APK 与公开资产哈希一致，并恢复通知权限。
- 验证：迁移包和正式包均冷启动成功，首页显示原待办，无迁移只读门和 Flutter/SQLite 异常；正式包非 Debuggable，证书及 APK SHA-256 正确。备份、迁移包、截图和 SHA256SUMS 位于 `D:\Dsk\aitext-backups\phone-signature-migration-20261109`。
- 状态：物理手机签名迁移完成；API Key 因 Keystore 凭据随旧包卸载失效而未恢复，需要重新输入。
- 风险/下一步：迁移包仅用于本机签名切换，不应公开发布；继续验证 API Key、真实 AI 调用和正式包中的内容持久化。

### 2026-11-09 / 发布 Android 手机 v1.5.0 预发布

- 任务：发布包含设备级完全体模式的 Android 手机预览版并核验公开资产。
- 变更：版本升至 `1.5.0+12`；新增 `docs/releases/v1.5.0.md`；main CI 与 Android Release 门禁加入完全体模式设置、迁移、策略、附件、回收站、输出续写、无限重试、上下文和启动恢复定向测试；README 与本交接记录公开下载、哈希和验证结论。
- 验证：main CI `42585275215` success；Android Release `42585293796` success，耗时 15 分 27 秒；Dart 格式、Analyze、292 项定向回归、秘密扫描、APK 构建、版本/API/权限、v2 签名和长期证书均通过。公开 APK `90,977,347` 字节，SHA-256 `e4bd3d65e3b02a05258670e9d8fc6e545dbc758456102f18d0030788c578a71b`，与 `SHA256SUMS.txt` 一致。
- 状态：Android 手机发布完成；GitHub Release 为 `phone-v1.5.0` pre-release。
- 风险/下一步：本次只发布 Android 手机资产，未构建新的 Windows/平板/全平台资产；未执行全量测试、物理手机、真实资料迁移、真实云同步或提醒验收。

### 2026-11-09 / 准备 Android 手机 v1.5.0 预发布

- 任务：将完全体模式作为新的 Android 手机预览版更新到 GitHub 并建立可下载 pre-release。
- 变更：版本升至 `1.5.0+12`；新增 `docs/releases/v1.5.0.md`；main CI 与 Android Release 门禁加入完全体模式设置、迁移、策略、附件、回收站、输出续写、无限重试、上下文和启动恢复定向测试；更新 README 与交接入口。
- 验证：`flutter analyze --no-pub` 0 issue；Dart formatter 271 文件 0 change；扩展发布门禁 292/292；完全体主机定向 179/179；Android AVD 开关 1/1；真实 DeepSeek `table_list` 1/1；手机矩阵 50/50；900 秒长测 907 秒/37 条/154 次请求；版本、标签、发行说明一致性和公开秘密扫描通过。证据说明和失败/最终日志在 `test-results/phone-release-v1.5.0/`。
- 状态：发布准备完成；尚未推送、打标签或创建 GitHub Release。
- 风险/下一步：标签流水线仍需验证格式、Analyze、扩展后的定向门禁、签名密钥、APK 版本/API/权限、v2 签名和长期证书；完全体模式不绕过模型硬限额、网络、磁盘或系统生命周期。

### 2026-11-09 / 完成手机 50 例、真实模型和 900 秒长测

- 任务：使用上一轮测试 Key，在 Android AVD 执行手机 50 例矩阵、真实 DeepSeek 工具冒烟和 15 分钟长测。
- 环境：Flutter 3.47.6，`aitext_agent_c_phone` / Android 15 / API 35，Emulator 37.2.12，隔离 ADB server 5041。
- 变更：长测检查点用量断言由“fixture 请求数到 +1”放宽为“fixture 请求数 ±1”，覆盖检查点先于或滞后一次在途请求结算；未修改产品业务逻辑。
- 验证：真实 DeepSeek 完全体模式 `table_list` 工具往返 1/1；手机矩阵 50/50，4 分 08 秒；900 秒长测 907 秒、37 条写入/读回、154 次模型请求，切后台、锁屏 12 秒、唤醒、重开应用和最终流式答复通过。测试 Key 未进入日志，秘密特征扫描 0 命中。详见 `test-results/phone-50-longrun-20261109/VALIDATION.md`。
- 状态：验证完成，待原子提交测试修复与交接记录。
- 风险/下一步：50 例矩阵使用脚本化模型，真实模型只覆盖普通回复与 `table_list` 工具轮；平板、Windows、物理手机和全量测试仍未执行。

### 2026-11-09 / 实现设备级完全体模式

- 任务：按用户要求增加设置页完全体模式，让 AI 在应用内获得全局完全权限、无应用层累计预算、自动续跑和无固定附件/检索上限，同时保护凭据与系统边界。
- 变更：新增 `fullAgentMode` 设置与 v6/v2/v7 迁移；全局覆盖现有/新会话策略；会话权限面板锁定；安全启动续跑；输出长度自动续写；瞬时故障无限退避；本地检索取消累计调用/结果上限；全文件/压缩包/图片输入；会话与附件回收站；整段会话、附件和普通设置工具；新增 ADR 0026、术语与模型/检索文档。
- 验证：`flutter analyze --no-pub` 0 issue；设置、迁移、策略、会话库、附件输入、回收站、工具发现、输出续写、无限重试和启动安全恢复主机定向 179/179；Android AVD `emulator-5620` 完全体开关与策略恢复 1/1。详见 `test-results/full-agent-mode-20261109/VALIDATION.md`。
- 状态：代码、主机定向测试、格式、静态检查和 Android AVD 验证完成。
- 风险/下一步：完全体模式仍不绕过模型硬限额、网络、磁盘、系统生命周期或凭据边界；真实模型 429/网络恢复、Windows、平板和物理设备强制停止后的自动续跑仍未验证。

### 2026-11-09 / 真机卸载重装与 10-21 数据恢复

- 任务：按用户授权导出数据、卸载旧包、安装含压缩修复的 Debug 包并恢复可用数据。
- 诊断：Honor 系统本地 restore set `1` 的 `bmgr restore` 返回 `restoreFinished: 0`，但新包 `files/` 仅有默认空表；`adb backup` 只生成 47 字节空包，系统本地备份不能作为恢复依据。
- 变更：安装 Debug APK；导入 `D:\Dsk\aitext-backups\H90y-v1.1.1-20261021\prepared-v1.1.4\vault` 旧格式数据，经应用迁移门创建 1 张表和 46 条内容。迁移后保存完整私有数据 tar、Debug APK 与 SHA-256 清单到 `D:\Dsk\aitext-backups\phone-debug-20261109`。
- 验证：迁移预检显示 47 条旧资料、1 张表、46 条内容；迁移后 `items/*.md` 46 个、`tables/*.md` 4 个，首页显示恢复的待办。数据 tar 为 131,865,088 字节，内容清单可读取；Debug APK SHA-256 `9092072da04becc1f2e266374b3756c8a4c8ecab9eb866ba7a28fe7a7cc888fe`。
- 状态：数据恢复和 Debug 安装完成；API Key 缺失，AI 页面显示“模型未配置”，等待用户输入后复验。
- 风险/下一步：10-21 之后的真实数据无法从本次空系统备份恢复；正式长期签名包覆盖仍需另行处理。当前设备临时息屏时间已恢复为 60 秒，设备内临时导入 tar 已删除。

### 2026-11-09 / 修复 AI 页面超大工具回合压缩阻断

- 任务：修复真机 AI 页面旧会话反复显示“任务中断，等待核对”和错误任务卡的问题。
- 诊断：设备已安装公开 `1.4.0+11`；模型连接返回 `connection-ok`，新无工具短对话返回 `OK`。失败消息明确为安全前缀摘要与完整当前工具回合 `49,557` 字符超过 `48,000` 字符窗口。
- 变更：`AgentContextManager` 保留最新 assistant/tool 调用配对，对超预算工具结果按 JSON 可解析的有界回执压缩；保留 status、operation ID、对象 ID/revision、错误码、retryable、coverage 和分页读取提示；完整工具 transcript 继续由 ChatService 本地持久化。新增 `agent_context_manager_test.dart` 和 ChatService 恢复工具回合集成回归。
- 验证：压缩回归修复前 exit 1，修复后 `agent_context_manager_test.dart` + `chat_service_agent_test.dart` 29/29；目标 `flutter analyze` 0 issue。详见 `test-results/ai-page-context-compaction-20261109/VALIDATION.md`。
- 状态：源码与主机定向修复完成；未创建新 APK/Release。
- 风险/下一步：本机无长期 release keystore，当前真机仍运行旧包且未清除用户数据；下一版同签名 APK 覆盖后需复验旧任务恢复。

### 2026-11-09 / 发布 Android 手机 v1.4.0 预发布

- 任务：发布包含无预算 Harness 的 Android 手机新版本并核验公开资产。
- 变更：版本升至 `1.4.0+11`；新增 `docs/releases/v1.4.0.md`；main CI 与 Android Release 加入 Harness 定向回归；Android Release 从 `pubspec.yaml` 动态读取 build 号并校验 APK `versionCode`；README 与本交接记录公开下载、哈希和验证结论。
- 验证：main CI `42539611481` success；Android Release `42539816724` success，耗时 15 分 20 秒；格式、Analyze、189 项定向回归、秘密扫描、APK 构建、版本/API/权限、v2 签名和长期证书均通过。公开 APK SHA-256 `68b8656703019b2628857540bcc2dfd64b69c2c961f6760a74f956a4a2677255`，与 `SHA256SUMS.txt` 一致。
- 状态：Android 手机发布完成；GitHub Release 为 `phone-v1.4.0` pre-release。
- 风险/下一步：本次只发布 Android 手机资产，未构建新的 Windows/平板/全平台资产；未执行全量测试、真实资料迁移、真实云同步或提醒验收。

### 2026-11-09 / 准备 Android 手机 v1.4.0 预发布

- 任务：发布包含无预算 Harness 的 Android 手机新版本。
- 变更：版本升至 `1.4.0+11`；新增 `docs/releases/v1.4.0.md`；main CI 与 Android Release 加入 Harness 定向回归；Android Release 从 `pubspec.yaml` 读取 build 号并校验 APK `versionCode`。
- 验证：全量格式检查 265 文件 0 change；`flutter analyze --no-pub` 0 issue；发布门禁定向回归 189/189；版本/tag/发行说明本地校验一致（`1.4.0+11`）；本地 Debug APK 经 Gradle 网络重试后构建成功，`versionCode=11`、`versionName=1.4.0`、minSdk 24、targetSdk 36。
- 状态：发布准备中；尚未推送、打标签或创建 GitHub Release。
- 风险/下一步：Android Release secrets、长期证书、APK 版本/权限/API、公开资产哈希与安装包签名需在标签流水线完成后核验。

### 2026-11-09 / GitHub main CI 通过

- 任务：确认格式修复后的 Harness 在 GitHub main CI 完整通过。
- 变更：仅追加 CI 结果与交接状态。
- 验证：Flutter CI run `42499993545` / job `128790458499` success，耗时 1 分 23 秒；格式、Analyze、迁移与秘书定向回归步骤均通过。
- 状态：GitHub `main` 发布完成；本地工作区在文档收尾提交后保持干净。
- 风险/下一步：本次只发布代码与 CI 结果，未创建新版本标签或 APK Release；版本仍为 `1.3.0+10`，现有 `phone-v1.3.0` 资产不变。

### 2026-11-09 / 修复 GitHub CI Dart 格式门禁

- 任务：将已验证的无预算 Harness 发布到 GitHub，并处理首轮 main CI 失败。
- 变更：按 Dart formatter 修正 `agent_usage.dart`、`agent_context_manager.dart`、`agent_tool_executor.dart` 与 `agent_tool_executor_test.dart`；同步更新交接状态。
- 验证：`dart format --output=none --set-exit-if-changed lib test integration_test tool` 265 文件 0 change；`flutter analyze --no-pub` 0 issue；diff whitespace 检查通过。
- 状态：格式修复完成，提交后推送触发 GitHub CI 复验。
- 风险/下一步：首轮 CI `42499771243` 的后续 analyze 与定向测试步骤因格式门禁未执行；以修复后的新 run 为准。

### 2026-11-08 / 完成 Android 真实模型 Harness 验证

- 任务：使用当前提供的模型凭据在 Android 模拟器验证真实 DeepSeek 连接、普通回复、只读工具和完全权限写入链路。
- 变更：新增真实模型验证记录；README 与交接补充当前证据入口。临时测试源和 `app/integration_test` 硬链接不进入仓库。
- 验证：Android 15 / API35 AVD `aitext_agent_c_phone`、Flutter 设备 `emulator-5620`；目标文件 analyze 无问题，真实模型测试 1/1 通过，构建 34.6 秒、安装 1.603 秒、用例 9 秒；最近 3000 行设备日志无 HTTP 400、FATAL 或未处理 Flutter 异常。详见 `test-results/android-real-model-20261108/VALIDATION.md`。
- 状态：验证通过；凭据未写入仓库、日志或测试记录，临时测试已清理。
- 风险/下一步：本次不覆盖平板、Windows、真实 OneDrive、通知、跨进程恢复或 900 秒长测；这些边界保持未验收。

### 2026-11-08 / 升级 Flutter 原生无预算 Harness

- 任务：按用户要求学习当前 `dsh-mobile-apk` 与钉住上游 `deepseek-harness 66491b05`，升级单 Agent Harness 并取消累计任务预算。
- 变更：新增 `AgentToolRegistry`、`AgentToolExecutor`、`AgentContextManager`、`AgentUsageMeter`；任务检查点 v3；完全权限新增回收站与收纳目标工具；查重冲突自动新建并标记待核对；状态卡移除追加额度。
- 验证：`dart analyze lib test integration_test` 0 issue；定向主机 149/149；Android 15 AVD `emulator-5620` 的 `table_ai_android_test.dart` 1/1；格式与 diff-check 通过。详见 `test-results/harness-unbounded-full-access/VALIDATION.md`。
- 状态：实现、文档和交接完成，准备原子提交。
- 风险/下一步：未运行全量、平板/Windows、真实模型、真实资料迁移、真实同步或本轮 900 秒长测；旧长测证据不替代本轮结论。

### 2026-11-08 / 发布 Android 手机 v1.3.0 预发布

- 任务：完成 Android 手机专用 GitHub 发布并核验公开资产。
- 变更：README、发布验证和交接记录真实 workflow run、APK 哈希、签名、版本、API、权限和下载链接。
- 验证：Release `phone-v1.3.0` 为 pre-release；main CI `42403931513` success，Android Release `42403946155` / job `128497527923` success。APK 90,731,435 bytes，SHA-256 `a81c32f7382d194e42151a9ba59816ddaf9a3e91fdc417cb3afe4b95c9754fbb`，长期证书指纹匹配，v2 验签通过。
- 状态：Android 手机发布完成；工作区提交后应保持干净。
- 风险/下一步：未做平板/Windows UI、A01–A30/A34–A35 剩余组合和真实资料迁移；OneDrive/百度网盘同步仍未接入。

### 2026-11-08 / 修正 Android Release 发行说明路径

- 任务：修复 `phone-v1.3.0` 首轮 Android 专用发布在 tag 校验阶段的失败。
- 变更：Android Release 工作流改查 `docs/releases/v$tagVersion.md`；发布验证记录补充失败 run 与未构建边界。
- 验证：失败 run `42403556704` 的 job `128496313900` 显示仅 `Validate phone release tag` 失败，后续安装依赖、签名、构建和发布步骤均 skipped；失败前秘密扫描与工具链准备成功。
- 状态：等待修正提交与移动后的标签触发重跑。
- 风险/下一步：重跑需继续验证长期 Android 签名 Secret、APK 版本/权限/证书、GitHub Release 创建及公开资产哈希。

### 2026-11-08 / 准备 Android 手机 v1.3.0 预发布

- 任务：按用户要求只完成 Android 手机可交付事项，提供长期签名 GitHub APK。
- 变更：版本升至 `1.3.0+10`；新增 `phone-v1.3.0` Android 专用发布工作流；修复长历史测试稳定性与生命周期延迟关停测试收尾；验收脚本新增真实最近任务滑动恢复场景；新增 v1.3.0 发行说明并更新当前交接。
- 验证：最终手机定向套件 68/68、`flutter analyze --no-pub` 0 issue、259 文件格式门 0 change；PowerShell AST 与 diff-check 通过；phone AVD 最近任务划掉恢复两阶段通过，source manifest `f9c8c219edb3218bb21b96d5225d2257fc8042bb0d2f101f5170537740cfde50`。既有 phone 50/50、A31–A33 与 900 秒长测复用。
- 状态：发布准备中；尚未推送 `main`/标签，尚未创建 `phone-v1.3.0` GitHub Release。
- 风险/下一步：Android Release secrets 必须可用；发布完成后下载公开 APK 独立核验并补记 workflow/run/hash。A01–A30、A34–A35、平板和 Windows 不在本轮门禁。

### 2026-11-07 / 专用秘书最终设备验收与长测闭环

- 任务：修复通知权限对话框识别、空会话终态和长测末轮回显计数，恢复 A31/A32/A33 与双端长测。
- 变更：验收脚本对权限对话框执行有界重试、语义节点匹配和失败层级导出；秘书页首次构建采用 workspace 当前会话，主动新建对话不重新吸附旧会话；消息列表增加稳定键，长测终态前切回秘书页并滚动到底部；末轮 `content_verify` 允许少一次后续 transcript 回显。
- 验证：最终 manifest `c283f93b19703686ab7caa0da802e43ff8bb5c557051156c070c9e94f07f49bd` 下 phone 50/50、tablet 27/27；双端六类恢复场景全部通过；phone 916.934秒/47条、tablet 917.914秒/47条长测通过。`secretary_conversation_ui_test.dart` 5/5、`app_background_lifecycle_test.dart` 6/6；相关 analyze、format、PowerShell AST 和 diff-check 通过。详见 `test-results/secretary-agent-implementation/final-device-20261107/VALIDATION.md`。
- 风险/下一步：A01–A30、A34–A35 的遗留主机组合与交叉审查仍未闭合；额外组合运行中 `conversation_lifecycle_test.dart`、`conversation_large_history_ui_test.dart` 暴露既有 pending timer/长历史输入可见性问题，未在本轮修改。补齐主机证据后更新最终文档并提交；不推送、不发布、不操作真实资料。

### 2026-11-06 / 手机 A31–A33 短场景重绑

- 诊断：service_interrupted 前一轮在显式恢复后过早判断任务已完成；等待谓词未覆盖新的 `content_verify` 回执。主 SDK Emulator 37.2.12、ADB5041、serial `emulator-6200` 当前通过脚本预检。
- 修正：集成验收等待条件增加续跑验证回执门槛，无生产恢复逻辑改动。
- 验证：手机 A31 Activity recreation、A32 force-stop/冷启动后不自动请求且显式继续原 task、A33 service_interrupted 均 exit0。manifest `733b7fbd6c53b158b98d032bbe70dfe935ef3a5a111a4ad568c4c1803248538a`；逐项命令与 APK SHA 见三个 `luna-c/20261106T.../VALIDATION.md`。格式检查 exit0、0文件变更；定向 analyze exit0，61条 info 级样式提示，无警告/错误。
- 风险/下一步：平板矩阵与 A31/A32需以同候选执行；A32最近任务划掉及A33 notification_denied/service_restricted/timeout未闭合；双端900秒长测和A01–A36仍开放，不提交、不推送、不发布。先切换专用tablet AVD，跑SEC-001/SEC-083及矩阵缺项，再验证恢复场景。

### 2026-11-06 / 长测诊断导入修复与手机复验

- 结果：attempt20 (`20261106T103655Z`) 在启动构建时退出，原因是新诊断漏导入 `ValueKey` 与 `debugDumpApp`；未进入业务阶段，不计入长测。模拟器 ADB 5041 在线、boot_completed=1、`stay_on_while_plugged_in=1`，脚本清理成功。
- 修正：补齐 Flutter Material 诊断符号导入。`dart format` 无改动；定向 `flutter analyze integration_test/agent_task_longrun_android_test.dart` 完成，0 error，59条 info（既有风格项）。
- 验证：attempt21 (`20261106T104048Z`，manifest `a2c00b538ded373b172c937a60f9cb925b8dad49e27a45ab2601307fcff0a4d2`) 于 `aitext_honor_phone` 运行923.914秒、44个业务进度检查点、198次请求；前后台/锁屏恢复成功，但终态 UI 检查失败：SSE 已送达 Workspace，秘书页未选中、消息行未挂载，当前 assistant 仍 streaming。失败归档无数据库快照，因为测试进程卸载了包；仅保留 stdout 诊断。该轮因 AVD 名称不符也不计A36。脚本现将输出设备 serial/AVD/boot/API/emulator版本/进程命令，两个专用 AVD 已创建。
- 修正：移除 ModelClient/Workspace 临时 SSE 插桩；最终 UI 检查改为核对 NavigationBar 选中索引，并以“秘书”标签重新导航。脚本增加 AVD 进程唯一性和设备预检落盘；首次专用 AVD 预检又发现脚本仍期望旧 `aitext_honor_phone`，已改为计划指定 `aitext_agent_c_phone` / `aitext_agent_c_tablet`。旧映射导致的失败发生在构建/安装前，未运行任何业务场景。
- 风险/下一步：attempt21 未满足 UI 断言且 AVD 不符。须先验证脚本 AST、格式和当前源定向测试，再依次在 `aitext_agent_c_phone`、`aitext_agent_c_tablet` 完成矩阵与各900秒长测；随后补 A01–A36缺项及交叉审查。所有门禁通过前不提交、不推送、不发布。

### 2026-11-06 / 手机长测流式 UI 可见性诊断

- 结果：attempt18 (`20261106T095635Z`, 916.536s) 在导航秘书页后仍找不到 RichText；attempt19 (`20261106T101526Z`, manifest `bf5e22f1…ff14d5`) 919.519s/45条/205请求，SSE→ModelClient→Workspace均成功，但 `SelectableText` finder仍为空。两次 A36 都未通过。
- 诊断：项目使用 `MarkdownBody(selectable: true)`，其 builder 实际生成 `SelectableText.rich`，所以已把 finder 改到 SelectableText，仍无匹配，说明最终时刻页面/消息 widget 未挂载；可能系统 Home/重新打开后 AppShell 回到首页。需读取 page key 与 message row 状态确认。
- 修正：新候选在最终 UI 检查前输出 Home/Secretary 页面、persistent secretary 与目标 message row 的挂载状态；如 nav_inbox 可见则再次选择秘书并推进300ms，再校验首段 SelectableText 可视位置。模型流已可正确交付。
- 验证：attempt19达到业务919.519秒，但终态UI断言失败；当前诊断候选尚未运行。模拟器stay-on恢复1，runner清理无失败。
- 下一步：按当前源再跑手机900秒以定位重开后的页面状态；终态通过后才启动tablet长测和A01–A36剩余验收。未满足门禁，不提交、不推送、不发布。

### 2026-11-06 / 长测页面挂载与流式文本查找修正

- 结果：attempt16 (`20261106T091703Z`) 在900秒任务中完成44条/198请求，SSE已到Workspace，但AppShell从首页启动且测试未选秘书页。attempt17 (`20261106T093632Z`, manifest `15409893…ba64e4b`) 业务914.570秒、44条/198请求，显式切到秘书页后仍因 `find.textContaining` 不查找 MarkdownBody 的 RichText 失败。
- 修正：任务开始前点击 `nav_inbox` 并推进300ms挂载页面；最终渲染断言改为匹配 `RichText.text.toPlainText()`，仍核对文本几何范围处于设备可视区。保留关闭HTTP输出缓冲、100ms通知pump及中间单条预留预算容差，终态预算保持精确核对。
- 验证：目标 integration analyze exit0（style info only）。attempt17 A36未通过；当前 RichText-aware 候选尚待设备复验。
- 下一步：手机当前候选正式长测；通过后才继续平板长测、A01–A36未闭合项与交叉审查。双端长测与矩阵未全闭合，不提交、不推送、不发布。

### 2026-11-06 / 长测流式传输与预算检查点断言校正

- 诊断：attempt13 (`20261106T082158Z`, manifest `4c93fe…9e06`) 业务935.395秒，HTTP 200但最终SSE行未被客户端读取。attempt14 (`20261106T084046Z`, manifest `b42384…e36f3`) 业务927.170秒，禁用fixture输出缓冲后，SSE、ModelClient解码、Workspace接收均出现标记；测试在UI 100ms通知批次前查询，finder未命中。attempt15 (`20261106T090855Z`, manifest `ab734f…c878`) 在3m23s因中途预算31与fixture已收到请求30不等失败。
- 修正：最终文本 fixture 设置 `HttpResponse.bufferOutput=false`；UI查找前推进100ms；中间预算检查容忍恰好一个已预留但尚未到达fixture的请求，终态预算仍须精确相等。
- 验证：phone SEC-083 在manifest `2b4d4938…c5c2b6`设备矩阵通过；目标分析需对新的预算断言改动复跑。attempt14确认网络传输修正，A36仍未通过。关闭900秒门槛的独立短测调用未完成且已中止；stay-on设置恢复为1。
- 下一步：当前候选重跑手机900秒，检查UI流与预算终态；通过后验证平板900秒，再补A01–A36缺项/交叉审查。交付门槛未满足，不提交、不推送、不发布。

### 2026-11-06 / 手机长测最终流诊断与失败现场兜底

- 结果：attempt10 在业务929秒、45条验证、205次请求后失败；首段 SSE 已发出，但测试未在会话状态中观察到 streaming assistant 内容。未满足 A36，设备故障现场 ZIP 未生成。
- 结果：attempt11 (`19155ae…ed76e`) 与 attempt12 (`2b4d4938…c5c2b6`) 分别运行927.673秒，46条验证、212次请求后均失败。两次都确认会话/活动会话 ID 相同、生成与后台任务仍 running，但 assistant 内容为空。attempt12 确认 fixture 写出并 flush 首个最终文本 SSE chunk；ModelClient decoded-content 与 Workspace receive 标记均未出现。归档导出 stdout JSON 成功（`failure-evidence/final-stream-diagnostic.json` SHA `c21fc47b14201794515f8346f605c5e8a18e2f146a2155211b7d1969cc39f07f`）；Flutter 卸载包后设备数据不可读。
- 修复/诊断：兜底校验 `run-as` 输出并拒绝保存 shell 错误文本；已在 ModelClient 响应状态/原始 SSE/解码和 Workspace delta 增加合成前缀诊断。phone SEC-083 在 manifest `2b4d4938…c5c2b6` 通过设备矩阵（`20261106T075843Z-phone-secretary_matrix`）。
- 验证：目标 Dart analyze exit0（60条 info、0 error），PowerShell AST parser clean；attempt12 A36 未通过，且仍未确定为何 HTTP 响应体未送达 ModelClient。诊断状态与失败运行日志在 `luna-c/20261106T075959Z-phone-longrun/`。
- 下一步：读取新增响应状态/原始 SSE 诊断，定位 HTTP response send/consume 的停点并修复；通过后重做手机900秒，再验平板、A01–A36和交叉审查。当前不提交、不推送、不发布。

### 2026-11-06 / 长测设备睡眠诊断及手机长测门槛校正

- 诊断：手机长测第6次的首次挂载卡顿并非 Flutter App 构建阻塞。临时分段日志显示首次挂载/首帧和下一次 pump 均能完成；复现时 Android `mWakefulness=Asleep` 且 Flutter renderer 报 `Width is zero`。唤醒 AVD 后测试立即发出 ready marker。诊断用 app/app_shell 打印已移除。
- 修正：长测脚本运行期间临时将 `stay_on_while_plugged_in` 设为3、唤醒并解锁 AVD，退出时在 `finally` 中恢复旧值；screen-off后台段校验模拟器确实关屏且 Activity 已暂停，允许专用无锁屏凭据 AVD 不显示 keyguard。业务进度 fixture 的 tool delta 下限从每次验证4帧调整为2帧；每个实际工具仍拆成至少两段 SSE delta。
- 验证：第7次使用源码清单 `244bdf327b5c73c4292b089d154c18718dfe393af387ef98f3d464ece81cc360`，启动成功、业务开始、后台服务运行和首项进度写入通过，但6帧小于旧断言8而失败；屏幕注入另因 keyguard 条件失败。脚本 PowerShell AST clean；目标 Dart analyze 退出码0（55条既存 info，无 error）。失败详情与真实尝试时序见 `test-results/secretary-agent-implementation/ACCEPTANCE.md` 及 `luna-c/20261106T063810Z-phone-longrun/`。
- 下一步：对调整后候选重跑手机短启动/业务断言并进入900秒；同一错误不重复盲测。平板、矩阵、A31–A33与全部A01–A36仍未闭合，不提交、不推送、不发布。

### 2026-11-05 / 宿主 SEC smoke 失败分类与复验边界

- 状态：按优先设备闭环计划复核 SEC-083；旧 runner 两次失败，最新候选正式复验仍未完成，续问等待超时。一次 breadcrumb 运行已定位 terminal 到 Workspace 的交付断点；尝试 controller 主动关闭仍未通过可控屏障回归，相关插桩及未验证业务逻辑均已清理。SEC-034/036/038 runner teardown 修复候选合并复验3/3通过。
- 证据：`test-results/secretary-agent-implementation/host-smoke-20261105/VALIDATION.md`。独立 A01–A36 审计确认 A05/A28 局部验证哈希匹配，但整体无冻结 manifest，设备历史失败仍未复验。
- 下一步：基于新的 stream关闭语义证据提出最小可验证修复；不得盲目重跑当前 SEC-083 候选。Android设备仍不可用；不创建提交。

### 2026-11-05 / A05 停止竞态与 A28/A30 文件后端恢复组合回归

- 改动：SEC-083 Workspace 测试明确验证首段可见、SSE 仍打开时一秒内停止和传输取消；完成/停止竞态用例改为同一运行实例继续下一轮，核对迟到回调不改变旧/新轮状态。新增文件后端 Runtime 重建回归，覆盖暂停检查点、零自动请求、原 task/assistant ID、并发追加额度去重和其他会话预算隔离。
- 验证：预算恢复回归1/1；主请求后生产语义查重预算检查点2次持久预留1/1；Workspace scheduler 25/25（含请求预留持久化失败不派发、内存/磁盘不加额、暂停和FIFO排队等待冻结活动时间）；ChatService agent 26/26（含240次/两小时边界与429退避活动计时）；真实 Runtime `waitingInput` 等待50ms预算不增长/零额外请求1/1；停止/完成竞态1/1；受影响 A23 四文件调用链组66/66；A26 retry recovery 3/3、A32 file-backed recovery 1/1；相关测试及直接依赖 analyze 无诊断，diff-check通过。当前源哈希及命令见对应 `test-results/secretary-agent-implementation/` 子目录 `VALIDATION.md`。
- 边界：A28/A30 主机计时与队列行为有定向证据；Android 设备队列/等待审批仍未验证。SEC-083 Android/UI验收未运行。模拟器支持端口仍被 Windows excluded range 阻塞，手机/平板矩阵及各900秒业务长测未完成；A01–A36未通过，不提交、不推送、不发布。

### 2026-11-05 / A23 重复改期通知业务幂等与主机调用链验证

- 缺陷：`schedule.change` 将每条助手消息不同的 action ID 当作改期批次幂等键。同一通知在新消息中再次分享会重复修改日程并创建第二个事件。
- 修复：用日程稳定 ID 与 UTC 规范化原通知发生时间生成来源键；恢复批账本保存并校验目标时间、发生时间、标题和正文。重复来源若内容/目标变化则失败并要求核对，避免盲目重放。跨表移动保留原日程 ID，可复用事件回执。
- 验证：修复前 Workspace→SSE 回归失败，观察到两个不同事件 ID；修复后四份定向测试 66/66、相关 analyzer 无诊断、diff-check 通过。独立复核补出已撤销批次、损坏 end 元数据和缺少有效发生时间的 fail-open 边界，均已修复并回归。命令、源 SHA 与边界见 `a23-schedule-notice-dedup/VALIDATION.md`。
- 边界：确定性 SSE 主机链通过；真实模型提取稳定发生时间和 Android/平板矩阵仍未验。A01–A36未完成，不提交、不推送、不发布。

### 2026-11-05 / A29 Workspace 双写失败时保留旧 transcript

- 缺陷：Workspace callback 在摘要持久化前先替换内存 assistant；任务检查点随后失败时，最终 failed message 仍可能包含未完成提交的摘要。
- 修复：先持久化候选 assistant message 与 task checkpoint；二者均成功后才更新内存 assistant/transcript。失败终态沿用旧 transcript。
- 验证：新增 Workspace 级真实 callback 故障注入，修复前红、修复后绿；runtime suite 18/18，ChatService 压缩组3/3，相关 analyzer 与 diff-check通过。详见 `a29-compaction-save-failure/VALIDATION.md`。
- 边界：容量/三步停滞全组合和设备运行仍未覆盖；A01–A36未完成，不提交。

### 2026-11-05 / A29 摘要持久化失败时暂停

- 缺陷：上下文摘要持久化回调失败会从 ChatService stream 逸出异常，调用方未得到明确的可恢复暂停终态。
- 修复：仅在摘要 checkpoint 持久化成功后替换内存 transcript；回调缺失或写入失败时发出暂停消息并以 `incomplete` 结束，不派发下一次模型请求。
- 验证：新回归先红后绿；压缩事实保留、摘要写入失败、无法安全压缩三项3/3通过；目标 analyze 与 diff-check 通过。详情见 `a29-compaction-save-failure/VALIDATION.md`。
- 边界：容量/溢出与跨进程唯一恢复仍需核对；A01–A36未通过，不提交。

### 2026-11-05 / 重新绑定 A35 当前迁移源码验证

- 发现：既有迁移通过记录的 coordinator/test 哈希与当前工作树不一致。
- 验证：运行 `sqlite_migration_coordinator_test.dart` 与 `table_migration_io_test.dart`，15/15通过；目标 analyze 和 diff-check 通过。当前源哈希见 `a35-migration-source-rebind/VALIDATION.md`。
- 边界：Android/Windows 设备验收和完整撤权组合未完成。
- 交付：A01–A36仍未全部通过，不提交、不推送、不发布。

### 2026-11-05 / 重新绑定 A25 当前源码验证

- 发现：既有 A25 通过记录的 `content_intake.dart` 与测试 SHA 已与当前工作区不同；原记录没有当前哈希绑定。
- 验证：重跑 `content_intake_test.dart` + `table_repository_test.dart`，47/47通过；目标 analyze 与 diff-check通过。当前源码及测试哈希见 `a25-source-rebind/VALIDATION.md`。
- 边界：仅主机定向证据；Android并发设备复验未做。整体 A01–A36仍未通过。
- 交付：不提交、不推送、不发布。

### 2026-11-05 / 增强 A32 文件后端恢复证据

- 改动：generation/receipt 恢复回归从内存 adapter 切换到隔离目录里的 IoVaultStore 与 SQLite index/conversation store；每次 runtime 启动都创建新 adapter 实例。
- 验证：目标 Flutter 测试 1/1、Dart analyze 单文件无诊断、diff-check 通过。测试断言启动无新增模型请求、恢复原 task/assistant/generation 与工具回执、显式继续只留一份写入。
- 边界：未运行 Android 设备；系统 force-stop、划掉与冷启动仍待设备验收，A32/A36 未完成。
- 交付：整体候选未通过 A01–A36，不提交、不推送、不发布。

### 2026-11-05 / 定位平板 AVD/ADB 启动阻塞的宿主端口根因

- 证据：安装的 Android Emulator 37.3.6本地 `-help-port` 说明控制台端口仅支持偶数5554–5584、ADB为控制台+1；Windows IPv4/IPv6 excluded ranges覆盖5120–5619。只读loopback绑定探针显示5554/5555/5584/5585均被拒绝，5622/5623可绑定但超出emulator支持范围。
- 结论：tablet attempt 2/2使用5622/5623没有合法监听端口；guest boot complete 但无 ADB设备与此环境冲突一致。无全局设置更改，无设备重启。报告见 `test-results/secretary-agent-implementation/avd-port-diagnostic/VALIDATION.md`。
- 下一步：仅在支持端口可用的隔离主机/VM，或明确授权修改系统端口排除后，恢复 Android验收；A36仍未通过。
- 交付：不推送/发布/提交，整体候选仍未完成。

### 2026-11-05 / A33 service-restricted 恢复身份双绑定

- 改动：READY marker 保存 assistant message ID 与持久 task ID；宿主恢复 barrier与RESULT必须与两者同时匹配，Dart fixture也校验双 ID，实际恢复仍使用 checkpoint 的原 task ID。重复或畸形 READY/RESULT marker fail-closed。
- 验证：A33 PowerShell 定向自检9/9、runner/self-check AST 0错误；Dart format无变化，integration test analyzer无错误。详见 `test-results/secretary-agent-implementation/luna-c/a33-service-restricted-host/VALIDATION.md`。
- 设备边界：未操作设备。A33历史 service_restricted 在 READY/ACK 前失败；`notification_denied`旧运行未进入目标权限状态。宿主身份校验不等于 Android 设备闭环。
- 工具限制：额外的宽泛旧 runner 自检在过时的 `Set-AppOpState` helper 名称断言处 exit 1；本次未扩展该旧脚本，仅使用聚焦 identity self-check。
- 交付：A01–A36未通过，未提交、未推送、未发布。

### 2026-11-05 / 修复 A31 Activity 重建时共享 Runtime 被提前关闭

- 缺陷：设备 Activity recreation 后 `tables.refresh()` 遇到数据库已关闭；主机 idle-status root 重建红测复现同一错误。
- 修复：同一 `AppRuntime` 的 App State 共享生命周期 gate；idle/终态关停使用可取消的2秒宽限，resumed 会取消；宽限到期复查任务状态，若已重新运行则继续等待任务终态。未创建第二份 Runtime。
- 验证：`app_background_lifecycle_test.dart` 6/6，相关 analyze 3目标无诊断，diff-check通过。覆盖 idle root 重挂后 refresh、终态期间重挂、宽限期内任务重新运行再终止后只关闭一次。详见 `test-results/secretary-agent-implementation/a31-activity-recreate/VALIDATION.md`。
- 边界：未做设备复验；两秒宽限对实际 Android Activity 时序的覆盖仍需设备证据。其他设备失败不受此主机通过替代。
- 交付：未提交、未推送、未发布；A01–A36与手机/平板长测仍未完成。

### 2026-11-05 / A26 retry 回执恢复与 A01–A36 预审更新

- 状态：已修复 retry 副作用提交后、action/generation receipt/task checkpoint 分步落盘造成的崩溃恢复不一致。启动时只在 action、tool call、fingerprint、receipt 唯一吻合时重建本地 succeeded receipt；同一任务暂停供用户显式继续，不重扫、不重写表、不自动派发。关联畸形或歧义进入 needsReview。
- 验证：基线红测能复现 applied action 与旧 conflict receipt；最终两项定向文件20/20通过，相关 analyze、diff-check通过。测试覆盖两个撕裂点、重复/损坏关联、其他待确认项保留、无新增模型请求、表版本仍为2。完整命令及源哈希见 `test-results/secretary-agent-implementation/a26-pending-intent/VALIDATION.md`。
- 状态边界：pending action、原 proposal 与覆盖度会持久化；用户在权限/预算恢复、重启后可以显式继续原 action，相关主机测试与 UI 测试通过。权限或预算恢复时自动触发续扫未覆盖，当前不据此宣称通过。A01–A36仍是预审，不是最终验收；A31/A33设备失败、A32未覆盖、A36手机/平板长测未通过。设备证据和逐项缺口见 `a01-a36-preliminary-audit.md` 与 `luna-c/`。
- 交付：未提交、未推送、未发布；设备失败未结算前不创建完成提交。

### 2026-11-05 / 平板第二次长测启动门禁失败与证据结算

- 状态：pauseGeneration checkpoint 与持久化失败路径已有主机回归；longrun failure archive/quiescence 候选经静态复核，182源manifest `6b307fa94c0d75aaf948a6d6d02ce47e18ade7dbdb6a4508f454c34ea5e95b33`、自检41 PASS。静态结果不等于设备验收。
- 设备：tablet longrun attempt 2/2 未进入业务。AVD自报boot complete但宿主5622/5623无监听，`adb -P 5037 devices` 与 `adb -P 5041 devices` 均为空；无build/install/权限写入/模型请求。AVD/QEMU已退出。证据见 `luna-c/20261105T-tablet-longrun-attempt2-adb-preflight/phase-summary.md`。
- 完成状态：手机长测此前在权限设置阶段失败且场景尝试已耗尽；tablet attempt 1/2在paused检查点断言失败，attempt 2/2停于启动门禁。A26、A31–A33等预审缺口仍在，A01–A36未通过；不创建完成提交，不推送或发布。
- 后续：仅在出现新的、可复核ADB启动根因/修复证据后再评估设备运行；先完成A26与设备故障分类，并更新 `test-results/secretary-agent-implementation/a01-a36-preliminary-audit.md` 为最终证据表。

### 2026-11-05 / pauseGeneration 检查点失败时保证 completion settle

- 状态：新增活动 turn 暂停的两阶段 task-store 故障回归：paused checkpoint 保存失败，worker catch 的 needsReview 保存也失败。旧实现 pause Future 在 500ms 有界等待中超时，worker 在完成 completer 前因 catch 中保存异常逸出；新实现即使 catch 保存失败也会通过 finally settle completion，并让 `pauseGeneration()` 抛出可观察错误。
- 回执/状态：写入仍失败时持久 store 保留最近成功的 running checkpoint；Workspace 内存队列将原 task 置为 needsReview 并保留待处理项，不伪称 paused 已持久化。回归验证 pause Future 和对应 send Future 都收到错误、无需等待挂起。
- 红绿与验证：受控旧实现红测 exit 1（500ms TimeoutException及 worker 存储异常）；修复后目标 exit 0。scheduler 与 background workspace 测试 26/26，Dart analyze 无诊断，diff-check 通过。详见 `test-results/secretary-agent-implementation/pause-generation-checkpoint/VALIDATION.md`。
- 风险/下一步：候选仍未经过 Android 设备复验；tablet longrun attempt 1/2 已消耗，attempt 2/2 仅在父代理冻结候选后执行。未提交。




### 2026-11-05 / pauseGeneration 等待 paused 检查点结算

- 状态：tablet longrun attempt 1/2 失败在“页面切换后显式暂停”断言。Workspace 的生成完成信号早于 turn worker 最终保存 paused checkpoint，原 `pauseGeneration()` 因此可能在检查点仍为 running 时返回。现改为等待同一 active turn 的 `completion`；worker 在最终检查点保存完成后才 complete turn。属于当前未提交候选修复，不表示设备长测通过。
- 红绿与验证：红测用可控 task-store gate 阻塞 paused checkpoint 写入；旧实现的 `pauseGeneration()` 在 gate 未释放时已返回，目标测试 exit 1。修复后目标回归 exit 0；scheduler 与 background Workspace 两文件 25/25，目标 Dart analyze 无诊断，详情见 `test-results/secretary-agent-implementation/pause-generation-checkpoint/VALIDATION.md`。
- 风险/下一步：tablet longrun 设备 attempt 1/2 已消耗；未重跑设备，候选冻结后尚有 attempt 2/2 可复验。手机与其它设备验收仍依照各自记录，不据此次主机修复推断通过。

### 2026-11-04 / Luna定向验证与语义候选分页缺口

- 状态：A手工service7/7、exact reuse UI专项1/1、响应式专项1/1已有记录；A25授权等待交错/锁内复核17/17通过，尚待最终合流。B已用红测复现旧pending在fullAccess下静默批准，正在修A12持久授权来源与A30按run调度。C手机与独立tablet均恢复ADB连接，最终业务验收仍未执行。
- 新缺口：语义候选在policy和model source双重take10，调用链没有后续分页。A已获model_duplicate_decision_source独占权，按每页最多10、跨页冲突保守处理、预算/权限中断如实覆盖补齐原设计。
- 验证入口：luna-a/PROGRESS.md、luna-b/PROGRESS.md、luna-c/ENVIRONMENT.md；不可将中间专项通过当最终候选完成。
- 下一步：完成分页、A12/A30及交叉审查后冻结候选；C运行手机/平板矩阵与各至少15分钟生产业务长测；统一原子提交仍待执行。


### 2026-11-04 / 消除设计验收章节的过时实施描述

- 状态：按C审查提示核对源文件，冲突实际位于专用设计第9节；将“本轮不执行A–F／没有执行业务用例”改为注明设计交付历史与当前证据入口，验收要求本身不变。
- 验证：原文定位与替换、diff空白检查通过；仅文档，不运行应用测试。
- 下一步：A/B继续定向收敛；C手机ADB及独立tablet启动已连通，生产业务矩阵和长测尚未完成。未提交。


### 2026-11-04 / Luna审查扩展到全局知识授权来源与A25提交边界

- 状态：A确认自动ContentIntake扫描/授权等待至锁内提交之间缺候选与表版本复核，已获content_intake/policy所有权继续修；B确认全局知识旧pending候选可能在切换完全权限后被静默批准，且缺人工/policy授权来源，已获结果层/持久化所有权修复。
- 环境进度：C改用未排除的5620/5621端口后ADB连接成功，正建立独立tablet profile及生产业务故障注入；不修改全局Windows网络配置。
- 验证：上述两项为代码审查确认的缺口，尚无修复通过结论；不得按原定向绿测判整体完成。
- 下一步：完成各自回归、迁移兼容和交叉审查后冻结候选，设备验收与最终原子提交仍待执行。


### 2026-11-04 / 统一目标文档的实施状态

- 任务：将README/RM、专用设计、术语、模型接入、可执行方案及ADR0024入口的过时“未实现／只设计”状态统一为“实施与验收中”；设计原始代码对照表标明为2026-11-03基线。
- 状态：仅修正文档当前状态，不改变已接受架构、产品范围或历史变更记录；公开版本仍为v1.2.1+9。
- 验证：逐项匹配旧文本后替换；文档修改不运行应用测试，diff空白检查通过。
- 下一步：三代理继续实现/验证，最终完成性由A01–A36证据及设备长测决定；尚未提交。


### 2026-11-04 / Luna首轮实现与模拟器端口根因

- 状态：A开始手工查重UI/例外凭据接线；B发现coverage泄漏和准备期取消窗口；C定位旧模拟器端口落入Windows排除TCP范围。
- 验证：目前仅缺口/环境诊断证据，新增改动尚待各owner定向结果；父代理刷新ACCEPTANCE逐项责任与证据，旧记录保留。
- 下一步：A/B完成回归与交叉只读审查；C恢复ADB并准备真实生产任务长测。候选未冻结、未提交。


### 2026-11-04 / 启动三名 Luna high 子代理收敛计划

- 任务：按用户要求由父代理领导，三名 gpt-6-luna/high 子代理分别实施手工查重、执行内核修复、Android 环境与完整验收；明确文件所有权，禁止自行提交和相互覆盖。
- 状态：保留当前授权未提交实现；手工模块/API 仍待完成接线验证，剩余生产审计和设备矩阵/长测尚未完成。
- 验证：只读核对 git status 与 hooks（已指向本仓库 .githooks）；本轮尚无新增子代理通过结论。旧主机证据按分项记录复用，不宣称最终合流通过。
- 风险/下一步：修正当前交接中设计阶段过时描述并保留第8节历史；收集分项证据、交叉审查、冻结候选，再执行手机/平板各15分钟故障注入，最终一个原子提交。


### 2026-11-04 / 精确查重越范围回执及预算发布竞态修复

- 进度：精确查重跨表复用后，在返回工具回执前重新检查当前会话tableScope，禁止返回受限表ID/内容回执；不制造第二条副本。预算请求预留改为候选快照保存成功后才发布内存计数，绑定原活动turn，失败无内存增量。
- 验证：exact-scope-red.log与reservation-publish-red.log均复现；修复后权限/模型接收组合29/29（exact-scope-green.log）、runtime/scheduler23/23（reservation-publish-green.log）通过；分析见scope-reservation-analyze.log。
- 风险/下一步：审计发现手工内容编辑器仍直接调用TableLibrary.createEntry/updateEntry，尚未接手工精确校验/语义提示/保留两条凭据；该项属于原计划，必须补齐。设备传输仍未恢复，手机/平板及15分钟故障注入未验收。未提交。


### 2026-11-04 / 停滞纠偏、空答复补救和压缩检查点（进行中）

- 进度：连续三步相同调用/相同结果（排除请求预算与回执身份噪声）加入一次纠偏，仍重复则明确暂停；空答复最多补救一次。
- 压缩后的安全前缀摘要先保存至原助手transcript再使用，后续压缩继承原目标、补充要求、对象版本与回执；摘要失败不切换请求。
- 验证：空答复回归初始1次请求失败，修复后通过；stagnation-empty.log34/34，reliability-context.log37/37，context-checkpoint.log1/1；reliability-analyze.log无诊断。
- 环境：旧隔离实例已保留日志并关闭；新实例emulator15756/qemu14128以5600/5601启动，内核日志出现sys.boot_completed=1，但端口不监听、ADB5041/5037均无设备。此为设备验收待解决条件，不能据此标记计划阻塞（仍可推进生产审计）。
- 下一步：补A01–A36完整证据与剩余输入/权限/预算并发审查，排除模拟器本机传输故障后执行手机/平板矩阵与15分钟任务；未提交。


### 2026-11-04 / 原generation恢复、完整工具意图及自动续批（验收继续）

- 进度：完整模型工具轮在执行前保存到原助手消息；每项回执结算后保存完整配对transcript。恢复复用原assistant/generation与工具位置，先结算待执行意图，再请求模型；已结算步骤不再由模型重新规划。意图保存期间取消不再派发新写入。
- 修复：暂停任务不再由worker完成回调无限重新调度；批次上限改为保存检查点后自动续批，不清零累计预算，检索批预算同步重置。
- 验证：跨批回归先红后绿；重建runtime验证启动零网络、手动继续原消息/回执、唯一正文与累计3次请求通过。5个定向文件55/55及最后3文件43/43通过（transcript integration/final 日志）；分析日志亦通过。
- 下一步：停滞/空答复/压缩持久化等A01–A36缺证据仍需审计，手机/平板15分钟故障注入未完成；模拟器2828/16152存活但没有5580/5581监听，尚未ADB就绪，未验收。全部工作尚未提交。


### 2026-11-04 / 查重回执持久化及中断恢复（任务步骤恢复待继续）

- 当前进度：ContentIntake的创建/补充使用表库持久化操作意图、前后像与回执；文件已提交但回执未结算时可恢复原回执；外部第三种修改保留材料并暂停。
- 同操作新建ContentIntake可返回原created结果，不再退化为reused；请求不匹配拒绝重放。v1任务检查点首次覆盖前保存原始backup，损坏状态禁止覆盖。
- 验证：原回执回归先红后绿；intake/capture/table-action/write-journal33/33、table-repository与恢复26/26、检查点备份与调度15/15通过。接收相关5目标分析无诊断。日志intake-recovery-*、intake-repository-regression.log、migration-backup.log。
- 风险/下一步：任务generation恢复尚未接到原步骤，自动续批/压缩等仍需审计；需完成手机/平板矩阵及15分钟故障注入。模拟器进程2828及其qemu16152存活但ADB尚无设备，正在诊断，不能视为设备验收完成。未提交/推送/发布。


### 2026-11-04 / 按任务预算与v2检查点（恢复账本仍待完成）

- 当前进度：独立任务分别计账，同任务steering共享budgetRunId；检查点v2持久化runBudgets与当前预算引用。
- 兼容：v1未完任务映射到legacy共享累计账本，避免迁移清零或扩大额度；校验v2缺失引用。暂停重入时检查点不再重复记录同一turn。
- 验证：独立任务回归修复前失败（第二任务计2）；修复后store/runtime/scheduler24/24通过，4目标分析无诊断，见task-budget-red.log、task-budget-green.log、task-budget-analyze.log。
- 风险/下一步：v2仅完成预算结构，完整步骤/意图/回执恢复及迁移备份仍未完成；ADB隔离端口5041当前无设备，需按环境记录启动AVD后完成手机/平板与15分钟故障注入。未提交。


### 2026-11-04 / 并发额度追加与SEC083确定性流（进行中）

- 追加/继续共用单个在途授权操作，并与请求预留串行；重复点击不会重复授权。
- SEC083首轮流保持打开直到取消，增加首段已到达、取消订阅及一秒停止断言；后续请求独立响应。设备尚未复验。
- 验证：runtime/scheduler定向20/20通过（budget-concurrency.log）；上一轮分析无诊断；本轮分析记录budget-stop-analyze.log。
- 下一步：独立任务预算与v2检查点、恢复账本、停止竞态及手机/平板矩阵和15分钟故障注入；完整计划仍未完成，未提交。


### 2026-11-04 / 追加预算持久化失败修复（计划继续实施中）

- 当前进度：追加额度和恢复队列改为候选快照保存成功后发布内存；失败不扩大授权，不清理待核对状态。
- 验证：新增两个故障注入回归修复前均失败；修复后runtime/scheduler共19/19通过。见budget-save-red.log、budget-save-green.log及budget-save-analyze.log。
- 风险与下一步：追加并发、任务独立计账、v2恢复账本、A01–A36设备验收仍未完成；尚未提交，不能视为计划完成。


### 2026-11-04 / 统一主辅请求预算入口（部分实施）

- 主模型通过与辅助模型相同的串行持久化预留入口计数；移除请求次数 max 合并。
- 更新调度器组合测试：两次额度下主请求先占一次，只允许一个辅助请求。
- 验证：两个定向文件 17/17 通过；首次旧断言失败（16通过/1失败），更新为共享额度契约后通过。
- 未完成：任务独立预算、追加原子性、v2检查点和回执持久化、停止屏障及手机/平板15分钟验收；未提交、未推送、未发布。


### 2026-11-04 / 专用 Agent 并行实施与定向收敛（进行中）

| 字段 | 内容 |
|---|---|
| 任务 | 根据持续目标实施 A–F，父代理统一集成六个子代理改动 |
| 状态 | 权限、检索、查重、工具循环、任务恢复及 Android 后台已有实现；工作区尚未收敛提交 |
| 验证 | 真实命令与分项结果保存在 test-results/secretary-agent-implementation/；最新收纳目标/表页 7/7、普通对话连续100轮通过；未执行全量测试 |
| 风险/下一步 | 完成生产语义查重与持久化审查，修复模拟器 VM isolate 中断，补齐手机/平板及15分钟故障注入；最终统一更新证据并创建原子提交 |

### 2026-11-03 / 完成专用秘书 Agent 完全权限与写前查重设计

| 字段 | 内容 |
|---|---|
| 任务 | 深入研究 DSH，完善专为本项目服务的可恢复 Agent 设计；用户明确本轮只落盘设计 |
| 变更文件 | 专用设计、DSH 研究、ADR 0024、术语、权威入口/相关契约提示及本交接 |
| 状态 | 已确认全权限含任意表与预置表删除、全局知识免逐项确认；查重优先自动复用/补充，仅冲突询问。已列 A–F 实施包与 A01–A36 验收；业务代码未改 |
| 验证 | 10 项静态检查通过：13 份文档、119 个本地链接、36 个连续验收编号、22 个固定来源链接格式、既有交接历史保留及 diff 空白；见 test-results/secretary-agent-design-20261103/VALIDATION.md。未运行应用测试、构建、真实模型或设备验证 |
| 风险与下一步 | 研究区分壳/实际钉住引擎/当前上游，未校验 Release APK。设计不能宣称故障已修复；按 A–F 实施，升级同时调整默认表初始化、捕获路由、权限和全局知识授权 |

### 2026-11-03 / 完成 v1.2.1 预览发布与资产安全核验

| 字段 | 内容 |
|---|---|
| 任务 | 完成最新版推送、预览发行及 API Key 泄露检查 |
| 变更文件 | README、本交接及 test-results/v1.2.1-release-20261103 验收证据 |
| 状态 | v1.2.1 已发布，APK/Windows setup/portable/SHA256SUMS 四项完整；标签 cda8bc7；Release 41585883431 与 main CI 41585877060 均 success |
| 验证 | 36 项定向回归通过；既有 Android 75/75 与真实模型冒烟复用。下载资产哈希全部匹配 GitHub digest 与清单；APK 1.2.1+9、v2 与长期证书匹配，Windows EXE 1.2.1+9。全部 Git 引用和 408 个资产文件/条目的模式扫描未发现秘密；详见本轮 VALIDATION.md |
| 风险与下一步 | 安装器外层扫描、便携包内部扫描与 CI 安装检查均通过，未独立解包安装器；模式扫描有覆盖边界。真机工具修复覆盖安装/恢复 Base URL、Windows 启动仍待完成；未执行全量测试，云盘和通知未接入 |

### 2026-11-03 / 修复秘密扫描成功退出码

| 字段 | 内容 |
|---|---|
| 任务 | 修复 Release 41585739440 的源码秘密门禁误判失败 |
| 变更文件 | scripts/scan-public-release.ps1、本交接和发布验证记录 |
| 状态 | 扫描无匹配时清零 LASTEXITCODE；此前 git grep 的正常返回 1 被 pwsh CI wrapper 继承。v1.2.1 尚未形成 Release/资产，将标签更新至修复提交重试 |
| 验证 | 同 CI 的 pwsh 调用修复前输出通过但返回 1；修复后验证见发布记录。主机业务测试不重跑，未执行全量测试 |
| 风险与下一步 | 跟踪重新触发的标签构建和 main CI，核对发布资产；旧失败运行保留作为证据 |

### 2026-11-03 / 发布 v1.2.1 修复预览版

| 字段 | 内容 |
|---|---|
| 任务 | 用户授权将已修复并完成模拟器测试的最新版推送 GitHub，发行预览版并检查 API Key |
| 变更文件 | app/pubspec.yaml、两个 CI 工作流、v1.2.1 发行说明、README、本交接及发布验证记录 |
| 状态 | 版本升至 1.2.1+9；准备原子提交并推送 main/v1.2.1，由标签流水线构建 Android/Windows 与校验清单 |
| 验证 | 全部本地 Git 引用秘密扫描通过；已有模拟器 75/75、真实 DeepSeek 冒烟及修复定向测试复用。新构建/发布结果见 test-results/v1.2.1-release-20261103/VALIDATION.md；未执行全量测试 |
| 风险与下一步 | 跟踪 Release 与 main CI，核对四项资产、版本/长期签名和哈希；真实手机工具修复安装、Windows 启动仍待验收，真实同步与通知未接入 |

### 2026-11-02 / 完成 Android 模拟器全量回归与真实模型冒烟

| 字段 | 内容 |
|---|---|
| 任务 | 在电脑 Android 15 手机和平板模拟器验证工具名修复，并使用真实 DeepSeek Key 复验秘书 |
| 变更文件 | README、交接和本轮模拟器验证记录；无生产代码变化 |
| 状态 | 手机 50/50、平板 25/25 确定性场景通过；真实连接测试、普通回复、`table_list` 工具往返及首页往返状态保留通过；Windows 25 场景按确认范围未运行 |
| 验证 | Flutter 3.47.6；`flutter drive` 目标 `integration_test/secretary_100_android_test.dart`；日志 `drive/phone.log`、`drive/tablet.log` 均包含 `All tests passed!`；release APK v2 验签、证书与 SHA-256 复核通过；应用日志无 HTTP 400、FATAL 或 Flutter 未处理异常。详见 `test-results/secretary-ai-emulator-20261102/VALIDATION.md` |
| 风险与下一步 | 本机 `flutter test -d` 会停在 VM Service 附加，使用官方 `flutter drive` 完成；真实手机的无线调试仍离线，后续需安装并恢复 Base URL。测试 Key 仅临时输入应用安全存储，应用数据与两个临时 AVD 已清理 |

### 2026-11-02 / 修复真实 DeepSeek 聊天工具名导致的 HTTP 400

| 字段 | 内容 |
|---|---|
| 任务 | 排查秘书页面无法使用：设置页文本连接成功，但真实聊天持续返回 HTTP 400 |
| 变更文件 | `ChatService` 表工具出网名及历史 transcript 归一化、聊天工具/Android 表 AI/真实场景测试、表交互契约、模型接入、执行计划、README、交接和本轮验证记录 |
| 状态 | 根因是 OpenAI 兼容接口不接受含点号的 function name。12 个表工具改用下划线名发送，本地继续映射回点号操作名，不迁移持久化操作；13 项定向测试、目标分析器和同长期证书 release 构建通过 |
| 验证 | `flutter test --no-pub test/chat_service_tools_test.dart test/table_ai_runtime_test.dart test/table_action_processor_test.dart` 13/13；目标 Dart analyze 无诊断；release APK v2 验签与证书 `51b5e2f3…` 通过，SHA-256 `8B9F21665DEEEE09065E9D46FB94E88434AEB4E9B0E42249837B1E86B2A8B26D`。真机覆盖安装与真实复验未执行，见 `test-results/secretary-ai-tool-names-20261102/VALIDATION.md` |
| 风险与下一步 | 无线调试会话构建期间变为 `offline`；手机 Base URL 仍指向临时回环代理。恢复 ADB 后先覆盖安装并还原官方 Base URL，再完成真实聊天和一次表操作复验；临时代理、日志和截图不提交 |

### 2026-11-02 / 按用户要求清理已迁移旧源并保留备份

| 字段 | 内容 |
|---|---|
| 任务 | 迁移成功后清理活动旧数据，减少反复预检 |
| 变更文件 | ADR 0023/索引、迁移服务/gate、旧源横幅/确认文案/旧链接跳转、相关测试、数据契约/执行计划、README 与交接 |
| 状态 | 新增整批备份与源 hash 核验、prepared→complete 可续跑清理清单，删除非全局旧源及旧删除记录；新内容/后续修改/全局知识保留。完成凭据独立于旧源，保持旧同步关闭；清理后旧会话链接按稳定 ID 打开新表/条目 |
| 验证 | 清理 gate 及旧链接回归均先失败；相关迁移 14 项与 runtime 5 项通过，已完成范围 analyzer/格式通过；最终同签名清理包构建/验签/保留数据安装通过，真机旧源横幅消失、4 张表/66 条内容不变、两次清理后冷启动通过，详见 test-results/h90y-legacy-cleanup-20261102/VALIDATION.md |
| 风险与下一步 | 用户本轮指令取代旧规范“永久保留活动旧源”；备份/journal/清理清单继续保留，清理开始后回旧版须显式还原备份。真机已清理且重启/数量核对通过；发布包禁止 run-as，未独立导出私有备份/清单，清理凭据与备份 hash 校验由应用执行。后续正式版本需包含修复与清理规则 |

### 2026-11-02 / 修复迁移后正常编辑引起的再次启动阻断

| 字段 | 内容 |
|---|---|
| 任务 | 用户再次反馈无法打开，真机截图确认完成目标与旧预检不一致 |
| 变更文件 | 迁移服务/回归、数据契约、README、交接与本轮验证记录 |
| 状态 | completedReceipt 错把当前内容要求为迁移快照；正常编辑导致重启进入只读错误页。改为读取已完成的一次性复制凭据，不覆盖用户后续内容；未完成迁移与 rollback 仍按 hash 保护 |
| 验证 | 真实 repository 编辑后回归修复前复现相同错误；修复后迁移服务/门控/I/O 10/10；补充 apply/rollback 防覆盖断言后该回归 1/1；dart analyze 无诊断，格式通过。同证书 release 构建/验签/保留数据覆盖安装通过，现有已修改数据上连续两次 force-stop 冷启动进入首页，未重迁移/回滚。见 test-results/h90y-migration-restart-20261102/VALIDATION.md |
| 风险与下一步 | 上一条的真机重启通过仅覆盖迁移后立即重启，不覆盖修改后重启，由本条补充纠正；已在当前已修改资料上验证恢复及两次冷启动，无需重复迁移；发布包禁止 run-as，未独立读取私有源文件与逐项对比用户修改。后续正式发布须包含本次修复 |

### 2026-11-02 / H90y 重连安装与删除记录迁移阻断修复

| 字段 | 内容 |
|---|---|
| 任务 | 在真机完成保留数据覆盖安装，继续解决升级无法进入应用 |
| 变更文件 | 迁移服务/回归、数据契约、README、验证记录与交接 |
| 状态 | 首版同证书修复包安装成功，69 条旧资料预检变为 1 张表及 66 条内容；过去日期阻断全部消失。剩余两条已删除记录误阻断，现改为保留旧源、备份并校验，但不恢复、不生成新内容、不阻断。未解决冲突仍阻断 |
| 验证 | 删除记录断言修复前失败，修复后迁移服务/门控/I/O 10/10 通过，相关 analyzer 无诊断；第二版签名包构建/验签/保留数据安装成功；应用内迁移完成，4 张表（3 默认+1 自定义）及 66 条内容（26 日程+40 待办），强制停止重启及日历入口通过。见 test-results/h90y-upgrade-20261102/VALIDATION.md |
| 风险与下一步 | 真机只读旧资料仍显示 69 条，未恢复两条删除记录。发布包不允许 run-as，未独立导出私有数据库/备份清单或逐文件核验源 hash；数据保护依赖应用备份/hash 校验及定向回归。未发布/推送此修复；本条取代上一条设备离线的当前状态 |

### 2026-11-02 / 修复旧日历安排随时间推移阻断升级

| 字段 | 内容 |
|---|---|
| 任务 | 无线连接 H90y，排查 v1.2.0 升级后无法进入主应用 |
| 变更文件 | 迁移服务、定向回归、当前迁移契约/执行计划、README 与交接 |
| 状态 | 真机停在旧资料只读预检（69 条可读取旧资料）；过去有开始时间的旧安排被错误阻断。改为保留原时间的日程，不推断已发生；不增加处理界面、不改旧源文件 |
| 验证 | 新增回归修复前失败；修复后迁移服务/门控/I/O 定向 10/10 通过，相关 analyzer 无诊断；同签名修复包构建及 apksigner 校验通过；安装时设备离线，真机验证待重连，详见 test-results/h90y-upgrade-20261102/VALIDATION.md |
| 风险与下一步 | 发布版不允许 run-as；尚未读取私有源文件、未执行真实迁移。修复 APK 已就绪但设备离线，需重连后保留数据覆盖安装，确认预检是否仍有其他阻断项；迁移保持应用内确认 |

### 2026-11-01 / 核验 v1.2.0 发布资产与验收边界

| 字段 | 内容 |
|---|---|
| 任务 | 核验 v1.2.0 发布结果，复核发布资产/签名/版本，并在可隔离范围内执行剩余验收 |
| 变更文件 | `README.md`、`RM_HANDOFF.md`、`docs/releases/v1.2.0.md`、`test-results/v1.2.0-release-prep/VALIDATION.md`；新增 `test-results/v1.2.0-release-acceptance-20261101/`（`VALIDATION.md` 与证据文件） |
| 状态 | Release `41218586972` success（head `7b42167`）；GitHub Release v1.2.0 已作为预发布版本发布（2026-10-31T16:31:22Z），4/4 资产齐全；main CI `41219403100` success（head `34b8543`）。资产本地 SHA-256 与 GitHub API digest、`SHA256SUMS.txt` 全部一致；APK 核验 `versionName=1.2.0`、`versionCode=8`、minSdk 24、targetSdk 36、证书 SHA-256 `51b5e2f3…`（v2 方案）；Windows 便携包解压 23/23 条目一致，EXE `1.2.0+8`、安装包 `1.2.0`。Android 秘书 AVD 用例与 Windows 启动**未验收**（环境/隔离限制）。执行中曾遇 sandbox 下授权目录写入被拒；用户随后授权完整运行权限后恢复执行，未修改 ACL、系统设置或网络配置 |
| 验证 | 见 `test-results/v1.2.0-release-acceptance-20261101/VALIDATION.md`；关键命令：`Get-FileHash`、`aapt2 dump badging`、`apksigner verify --print-certs`、ZIP 条目对比、`(Get-Item).VersionInfo`、`adb devices`、有界 `emulator.exe`/system-image 搜索 |
| 风险与下一步 | 本机无可用 Android 模拟器/系统镜像；存在真实数据目录 `C:\Users\18377\AppData\Roaming\com.yuanfang.aitext`，Windows 启动无法证明隔离故未执行。二者保持“未验收”，待具备隔离环境后补充 |

### 2026-11-01 / 修正 Linux 迁移测试的磁盘容量夹具

| 字段 | 内容 |
|---|---|
| 任务 | 让迁移 I/O 测试在 Linux CI 使用确定性磁盘空间输入，避免调用仅支持 Android/Windows 的平台探测器 |
| 变更文件 | `app/test/table_migration_io_test.dart`、发布验证记录 |
| 状态 | GitHub main CI `41218574288` 中除迁移 I/O 用例外的 617 项通过；两项失败均因 Linux 磁盘探测按设计返回 null。测试已改为注入 1 GiB 可用空间，本地相关用例 2/2 通过。此修复不会改变应用代码；Release `41218586972` 基于 `7b42167` 已通过全量测试，正在构建 |
| 验证 | Flutter 3.47.6 `flutter test test/table_migration_io_test.dart` 2/2 通过；该文件 `dart format --output=none --set-exit-if-changed` 通过。GitHub main CI 尚待重跑 |
| 风险与下一步 | 提交并推送测试夹具，确认 main CI；等待 Release 工作流完成后核验发布页资产、长期签名与哈希。AVD 秘书交互和真实资料迁移仍未验收 |

### 2026-11-01 / 修复 v1.2.0 发布测试门禁

| 字段 | 内容 |
|---|---|
| 任务 | 修正与表/笔记模型及秘书页常驻导航不一致的旧验收用例，恢复 v1.2.0 发布门禁 |
| 变更文件 | Android/设备矩阵生成器与快照、秘书/真实流程回归、迁移只读页面 DTO 边界、README、验证记录 |
| 状态 | 首轮 CI 格式失败已修复；第二轮 Release 与 main CI 的全量测试失败已定位。旧用例曾在 `results.todos` 查询已迁入默认表的 AI 内容、期望离开页面取消仍应继续生成，以及使用已移除筛选项/导航写断言；均已按当前实现和已确认产品行为修正。GitHub 当前仍无 Release |
| 验证 | Flutter 3.47.6：Android UI 100、设备验收 100、秘书 100、秘书 smoke 与现实流程 smoke 合计 328 项通过；`dart format --output=none --set-exit-if-changed lib test integration_test tool` 通过；`flutter analyze` 无诊断；`scripts/scan-public-release.ps1 -AllRefs` 通过。此前失败工作流：Release `41215486744`、main CI `41215475349`。详见 `test-results/v1.2.0-release-prep/VALIDATION.md` |
| 风险与下一步 | 提交并推送本修复，确认没有已发布 Release 后更新 v1.2.0 标签并重跑完整工作流；通过后验证签名、资产哈希及 Windows 包。Android 秘书页 AVD 交互和真实资料迁移仍未验收 |

### 2026-10-31 / 修复 v1.2.0 发布格式门禁

| 字段 | 内容 |
|---|---|
| 任务 | 修复首轮 GitHub Release 工作流在 Dart 全量格式检查中发现的格式问题 |
| 变更文件 | `app/lib/ui/pages/global_knowledge_page.dart`、RM_HANDOFF 和发布准备验证记录 |
| 状态 | 已按 Dart formatter 修复唯一未格式化文件；本地全量格式检查通过。首轮 Actions 因该项失败并未运行后续分析/测试/构建；GitHub 尚无已发布 Release，资产未生成 |
| 验证 | Flutter 3.47.6 `dart format --output=none --set-exit-if-changed lib test integration_test tool` 通过；首轮工作流 `41215153819` 格式门禁失败。详见 `test-results/v1.2.0-release-prep/VALIDATION.md` |
| 风险与下一步 | 提交并推送修复，确认仍无 Release 后更新标签目标并重跑工作流；不覆盖已发布的 Release |

### 2026-10-31 / 准备 v1.2.0 预览版 GitHub 发布

| 字段 | 内容 |
|---|---|
| 任务 | 将本地领先远端的 25 个表/笔记改版、AI 表内操作、迁移及秘书页嵌入提交纳入 v1.2.0 预览发布准备 |
| 变更文件 | `app/pubspec.yaml`、`docs/releases/v1.2.0.md`、README、RM_HANDOFF 和发布准备验证记录 |
| 状态 | 版本改为 1.2.0+8；发行说明记录数据备份要求、跨设备同步/通知未接入、真实资料迁移未验证及秘书页 Android AVD 交互缺口。发布准备提交与标签已推送；首轮格式门禁失败待修复后重跑 |
| 验证 | 发布范围核对 25/25 提交；`scripts/scan-public-release.ps1 -AllRefs` 通过；远端 main 已包含发布准备提交，首轮 Actions 在全量格式检查停止；无 GitHub Release/资产。详见 `test-results/v1.2.0-release-prep/VALIDATION.md` |
| 风险与下一步 | 按发行说明备份旧版应用数据与 Markdown 主库；推送格式修复并重跑工作流。Android 秘书交互缺口继续明确保留 |

### 2026-10-31 / 秘书页常驻与主导航集成

| 字段 | 内容 |
|---|---|
| 任务 | 将 AI 对话嵌入 AppShell 常驻页，保留全局导航和主页面往返状态 |
| 变更文件 | AppShell、秘书页面及抽屉/请求切换逻辑、秘书 UI 与 Android 集成导航用例、CONTEXT、前端/对话/模型约定、ADR 0022、README 与本交接 |
| 状态 | 代码修改完成；主机定向验证通过；AVD 已启动但本轮 Android APK 构建未完成，因此 AVD 交互未验证。变更尚未提交 |
| 验证 | `flutter test --no-pub test/secretary_conversation_ui_test.dart` 4/4 通过；目标 Dart analyzer 无诊断。Android 集成测试尝试因 Gradle cache/Java TLS 环境失败或长时间无输出而中断。详见 `test-results/secretary-embedded-20261031/VALIDATION.md` |
| 风险与下一步 | AVD 测试缺失，先修复或复用可工作的 Gradle 9.3.1 离线缓存/JDK 信任配置，再重跑集成用例；确认后提交本轮原子变更 |

### 2026-10-30 / P8–P9完成表入口收敛与候选验证

| 字段 | 内容 |
|---|---|
| 任务 | 替换旧事项/待处理入口，完成表内捕获与搜索、定向主机/AVD验收和隔离候选构建 |
| 变更文件 | 表/捕获/同步/全局知识入口，测试场景与Android集成用例，项目 README、执行计划及验证报告 |
| 状态 | P8首轮完成；P9候选构建与应用内合成资料迁移验证通过。旧源未变；真实旧资料未迁移；Windows候选未启动 |
| 验证 | 最新主机相关测试51/51、旧会话恢复/AI工具8/8、迁移服务14/14、迁移后runtime/global knowledge/sync17/17、22个直接改动分析目标无诊断；Android表页1/1、AI建日程/改期1/1、迁移后主导航/全局知识修改重启3/3；候选APK空AVD安装、4源迁移、应用确认和重启哈希核验通过。矩阵见 `test-results/table-notebook-p8-p9-20261030/VALIDATION.md` |
| 后续 | 真实资料迁移只在实际用户备份通过校验并由应用迁移门确认后执行；真实同步、通知和Windows启动验收仍未完成 |

### 2026-10-30 / P5d 完成表页多宽度布局检查

| 字段 | 内容 |
|---|---|
| 任务 | 检查表列表、详情、字段管理和内容编辑器在手机/平板/宽屏下的布局与操作 |
| 变更文件 | `tables_page_test.dart`及P5d验证记录 |
| 状态 | 320×780、800×900、1280×900三档完成列表→详情→字段→内容编辑；实际截图美术走查未做 |
| 验证 | `tables_page_test.dart`、`table_fields_page_test.dart`、`table_repository_test.dart`共26/26通过，7个分析目标无诊断。详情见 `test-results/table-notebook-p5d-responsive-20261030/VALIDATION.md` |
| 后续 | P8旧入口/待处理替换，P9候选包恢复/升级验收 |

### 2026-10-30 / P7 首轮接通 AI 表检索、内容操作与对话结构审批

| 字段 | 内容 |
|---|---|
| 任务 | AI 查找围绕表内数据；表内内容按权限直接执行，表结构变化必须在当前对话点击确认 |
| 变更文件 | LocalRetrieval表/内容查询，ChatService表工具与旧成果工具封锁，TableActionProcessor，ConversationWorkspace与ChatMessage持久化，表动作对话卡片，模拟模型/AVD用例 |
| 状态 | 支持表列表/搜索/读取、按表/类型/时间/字段检索、内容读写/移动/删除、表正文修改、通知事件与原日程联动。表/字段创建修改删除产生 revision 绑定确认卡；默认表不可删，旧结果工具不可绕过表权限；全局知识确认保持原路径 |
| 验证 | P7定向主机测试25/25、20个分析目标无诊断；AI表检索、模拟模型自动写入、内联结构审批、旧工具封锁及全局知识审批通过。Android15 AVD模拟模型写入/确认/重启读回1/1。详情见 `test-results/table-notebook-p7-20261030/VALIDATION.md` |
| 后续 | P5表页响应式检查；P8旧待处理入口替换；P9候选包恢复/升级演练。真实用户数据未迁移 |

### 2026-10-30 / P6 首轮接通首页与日历表投影

| 字段 | 内容 |
|---|---|
| 任务 | 日历按表显示带业务时间的内容；首页继续展示现有区块并可添加、排序常用表 |
| 变更文件 | Calendar projection/occurrence identity、设备设置v4、CalendarPage、HomePage、内容编辑器初始日期及主机/AVD用例 |
| 状态 | 日历仅投影表内待办/日程/有发生时间事件，普通笔记时间不进入；过滤与首页模块顺序按设备保存。首页今日安排、待办和普通笔记从表读取，表模块显示五行并可展开/排序/移除显示 |
| 验证 | 主机28/28、14个分析目标无诊断；Android15 AVD首页添加表、表筛选/创建日程、删除预览/恢复1/1；日历320/800/1280宽度检查通过。详情见 `test-results/table-notebook-p6-20261030/VALIDATION.md` |
| 后续 | P7 AI表内操作与对话结构确认已首轮实现；继续完成P5响应式检查及P8/P9。真实资料未迁移 |

### 2026-10-30 / P5c 完善字段选项与整表回收站预览

| 字段 | 内容 |
|---|---|
| 任务 | 补齐单选/多选选项维护及整表恢复预览，避免删除仍被内容使用的选项 |
| 变更文件 | TableFieldsPage选项编辑、TableRepository回收快照预览、TableLibrary接口、表列表恢复预览与期限、主机/AVD用例 |
| 状态 | 选项新增/改名保留稳定 ID；被内容引用的选项不能直接删。回收站展示原表名、最多五条内容预览、恢复剩余时间，并可整表恢复 |
| 验证 | 主机定向测试25/25通过，9个定向分析目标无诊断；Android 15 AVD整表创建/持久化/删除/预览/恢复1/1通过。详情见 `test-results/table-notebook-p5c-20261030/VALIDATION.md` |
| 后续 | P5继续完成表页窄/宽屏验收；随后实施P7 AI表内操作与对话结构确认。真实资料未迁移 |

### 2026-10-30 / P5b 接入六类自定义字段和值安全移动

| 字段 | 内容 |
|---|---|
| 任务 | 实现按表字段定义、逐条字段值输入，以及跨表移动时不丢字段值；字段删除支持撤销 |
| 变更文件 | TableFieldsPage/entry editor、TableRepository字段恢复批次与moveEntry兼容校验、SQLite schema v10/v9→v10升级、P5主机用例 |
| 状态 | 文本/数字/日期/单选/多选/勾选可定义并编辑；字段改名保留ID，删除已填字段时原定义和值保留30天。跨表移动保留ID；目标字段不兼容时明确阻断。未接AI字段结构审批 |
| 验证 | 当前直接相关 repository/SQLite/页面主机用例50/50通过，analyzer无诊断；Android15 AVD作业表/笔记/自定义文本字段创建后 force restart，再次读取正文与字段值通过 |
| 后续 | 继续 P5 的字段选项维护、快速新建日期联动和窄/宽屏验收；随后执行 P6日历/首页投影。真实用户数据未迁移 |

### 2026-10-30 / P5a 接入表与笔记基础手工界面

| 字段 | 内容 |
|---|---|
| 任务 | 用表列表取代事项导航，提供笔记式表正文与混合内容的基础手工增改删 |
| 变更文件 | 新增 TablesPage/TableDetailPage/基础内容编辑器，替换 AppShell 事项入口；TableLibrary 刷新全部表内容；新增主机和 AVD 持久化用例 |
| 状态 | 支持三默认表、作业/考试等自定义表、表正文、笔记/待办/日程/事件、待办完成、表重命名/删除/恢复。首页仍不变。字段 UI、跨表移动及日历/首页联动待后续工作包 |
| 验证 | 主机 `tables_page_test` 1/1、Android15 AVD 手工建表/写正文/记笔记/force restart后读回 1/1 通过；相关 analyzer 无诊断 |
| 后续 | P5b完成字段值编辑和安全移动；P6投影表到首页/日历。真实用户数据未迁移 |

### 2026-10-30 / P4c 接入旧资料只读启动门

| 字段 | 内容 |
|---|---|
| 任务 | 在 AppRuntime 启动读取迁移预检；发现旧资料时阻止旧模块初始化，并提供只读旧内容查看和显式确认的副本迁移入口 |
| 变更文件 | TableMigrationGate、AppRuntime/AppScope/AppShell、只读预检页、runtime 主机与 AVD 集成测试 |
| 状态 | 旧资料页面不能编辑；捕获、事项库、会话恢复和同步模块不启动。确认后可生成新格式副本，旧源保留；迁移完成后仍只读，等待P5新表入口 |
| 验证 | AppRuntime/迁移门主机定向测试通过；Android15 AVD默认表、磁盘探测、只读门及确认迁移副本四项集成测试通过；相关 analyzer 无诊断 |
| 后续 | P5接通新表页面并在迁移完成后允许进入，演练后评估真实旧资料升级；当前未迁移真实资料 |

### 2026-10-30 / P4b 增加数据库快照、磁盘容量探测与迁移安全门

| 字段 | 内容 |
|---|---|
| 任务 | 为迁移 journal 引入独立 SQLite/会话/设置快照清单，接入 Android/Windows 剩余空间查询，并要求缺失备份/容量/写暂停回调时阻断 apply |
| 变更文件 | `MigrationCoordinator`/`SqliteMigrationCoordinator`、`TableMigrationService`、Android MainActivity、平台空间探测、迁移与平台测试、执行计划和交接文档 |
| 状态 | vault和数据库快照分别hash校验，迁移journal关联其路径；旧源保留。应用级写暂停实现尚未接入，故迁移 apply 仍被阻断；未使用真实用户资料 |
| 验证 | 迁移服务5项、SQLite协调器5项、Windows可用空间探测1项、Android15 AVD通道集成1项均通过；APK构建成功，定向 analyzer 无诊断 |
| 后续 | 实现AppRuntime/UI的写暂停与迁移确认门、只读旧格式入口、隔离目录重启/空间不足演练；然后按计划继续P5 |

### 2026-10-30 / 完成 P4a 迁移预检与可重放暂存工具首轮

| 字段 | 内容 |
|---|---|
| 任务 | 为旧 Markdown 生成迁移预检、确定性映射、vault Markdown 备份清单、暂存校验、重放和按 hash 回滚 |
| 变更文件 | 新增 `TableMigrationService` 与合成 fixture 测试，修正 SQLite启动迁移测试的 schema v9 夹具，更新数据契约/执行计划/规划入口 |
| 状态 | 旧源文件保留；未来且有开始时间的旧日历项映射为日程。过去/无日期日历项、草稿、删除记录、冲突和孤立关联阻断自动迁移。仅内存 fixture 测试，未接正式入口或修改真实资料 |
| 验证 | migration service 与 SQLite migration coordinator 定向测试 10/10 通过，相关 analyzer 无诊断，diff whitespace检查通过 |
| 后续 | P4b补齐跨存储一致备份、空间探测、启动迁移门/只读旧格式入口与隔离目录中断恢复演练；在全部完成前不迁移真实资料 |

### 2026-10-30 / 完成 P3a–P3c 本地恢复与日程联动数据层首轮

| 字段 | 内容 |
|---|---|
| 任务 | 完成恢复账本、单条/整表回收与恢复、到期清理，以及通知事件和原日程同批变更 |
| 变更文件 | 表恢复模型/index/repository/library、SQLite v8→v9迁移、故障与事务测试、数据契约、执行计划和项目交接 |
| 状态 | 内容 10 分钟撤销、整表 30 天恢复、默认表防删、跨表 affects 清理/恢复、改期事件与原日程幂等同批更新/撤销已接入本地数据层；页面、AI 工具、旧事项迁移和真实同步尚未接入 |
| 验证 | repository/index/SQLite 21 项定向用例通过，相关 analyzer 无诊断；测试涵盖单日程/整表删除、关联恢复、到期处理、事务中断重放、日程改期和 v8→v9 迁移。最新 Debug APK 构建/安装成功，Android15 AVD冷启动、force-stop重启及三默认表Markdown SHA-256一致 |
| 后续 | 继续 P4隔离迁移演练；P5接回收站和表页面。Flutter integration_test VM Service问题仍待排查 |

### 2026-10-30 / 完成 P3b 单条撤销和整表回收恢复首轮

| 字段 | 内容 |
|---|---|
| 任务 | 在 SQLite恢复账本上实现内容/整表删除、30天到期处理、恢复和跨表事件引用保护 |
| 变更文件 | TableRepository/TableLibrary、恢复迁移门/模型、P3本地故障测试及产品数据契约 |
| 状态 | 单条10分钟撤销、整表30天恢复、删除/恢复prepared恢复、到期硬化和跨表affects清理复原已实现；UI和同步契约尚未接通 |
| 验证 | 17项 repository/SQLite测试通过；直接相关 analyzer无诊断；未改真实资料 |
| 后续 | P3c实现日程联动及同步兼容；P5界面接回收站入口 |

### 2026-10-30 / 增加 P3a 持久化恢复批次账本

| 字段 | 内容 |
|---|---|
| 任务 | 为短期单条撤销与30天整表恢复建立 SQLite 持久化删除批次状态 |
| 变更文件 | TableRecoveryBatch模型、IndexDatabase内存/SQLite接口、schema v8和迁移门、ledger测试 |
| 状态 | P3a账本schema首轮完成；实际快照、删除、恢复、到期清理和事件联动尚未实现 |
| 验证 | 相关7个 Dart 文件 analyze 无诊断；SQLite v6→v8升级和批次状态重开测试通过 |
| 后续 | 在P3b保存/校验前像并实现恢复/过期清理；P3未完成 |

### 2026-10-30 / 接入表与内容 SQLite索引及默认表 runtime初始化

| 字段 | 内容 |
|---|---|
| 任务 | 增加索引 schema v7、表/内容索引API、memory/SQLite适配器、TableRepository/TableLibrary和AppRuntime接线 |
| 变更文件 | index/repository/runtime/modules, SQLite与memory tests, Android默认表bootstrap集成用例 |
| 状态 | 默认表、内容存储/重建、有界搜索/字段筛选、版本控制已实现；内容删除/回收站、迁移、页面与AI入口未完成 |
| 验证 | Flutter analyze 20项无诊断；定向SQLite/repository/runtime/result测试28/28；Debug APK成功。AVD安装后手工启动/重启，默认表Markdown和SQLite行一致。Flutter integration runner因VM Service连接问题失败，详见P2结果 |
| 后续 | P3实现单内容撤销/30天整表回收及事件联动；不迁移现有真实资料 |

### 2026-10-29 / 完成 P0 契约及 P1 表模型和 Markdown codec 首轮

| 字段 | 内容 |
|---|---|
| 任务 | 完成笔记式表页面/AI工具契约；实现独立表与内容类型模型和 Markdown 编解码 |
| 变更文件 | 表/交互契约、ADR 索引、模型接入/同步提示、README/RM_HANDOFF、table model/codec 和定向测试 |
| 状态 | P0 文档契约完毕；P1 codec 首轮实现。尚未切换运行 codec，未修改 repository/SQLite、UI 或真实资料 |
| 验证 | 指定 Dart 文件格式化无变化；analyzer 无诊断；codec 测试 9/9通过。Android 15 AVD启动但尚未运行改版 UI 流程 |
| 后续 | 继续 P2 repository/SQLite 和索引；随后迁移演练、手工页面、首页/日历、AI工具及对话确认 |

### 2026-10-29 / 细化表与笔记改版的逐步执行计划

| 字段 | 内容 |
|---|---|
| 任务 | 按用户要求把规划细化到每一步执行动作、文件落点、验证与完成标准 |
| 变更文件 | 表与笔记执行计划、产品规划入口、README、RM_HANDOFF |
| 状态 | P0–P9 共 80 步全部待执行；覆盖契约、模型、存储、联动/恢复、迁移、手工页面、投影、AI审批、替代入口和候选升级；未改业务代码 |
| 验证 | 4 个 Markdown 文件、25 个本地链接、01–80 连续唯一编号、13 类需求映射及历史保留核对通过；未执行应用测试、构建、模型调用、设备或真实数据迁移 |
| 后续 | 从 P0 收敛建议与契约，按工作包局部验收并原子提交；发布、真实云盘接入不属于此计划的自动执行范围 |

### 2026-10-29 / 开始执行 P0 数据契约

| 字段 | 内容 |
|---|---|
| 任务 | 明确表/内容 Markdown 对象、类型、字段值、迁移映射、日历投影及恢复的实现契约草案 |
| 变更文件 | 表与内容数据契约、ADR 0021、同步协议提示、实施计划、README、RM_HANDOFF |
| 状态 | 完成 P0 的数据所有权和 schema 草案；P1 及后续包未执行。未修改应用代码、真实格式或用户资料 |
| 验证 | 文档核对待完成；Flutter 命令未在 PATH/常用安装位置发现，计划路径 `E:\DevTools\Flutter` 不存在；ADB 文件存在但不能由主机启动。未运行应用测试或模拟器场景 |
| 后续 | 完成 P0 状态草图/决策清单和文档核对，解决 Android 工具链；随后执行 P1 模型与编解码 |

### 2026-10-29 / 确认通知事件联动原日程与回收站保留 30 天

| 字段 | 内容 |
|---|---|
| 任务 | 记录用户对事件调整和自定义表删除恢复的答复 |
| 变更文件 | README、RM_HANDOFF、CONTEXT、表与笔记改版规划、ADR 0020 |
| 状态 | 确认保留调整通知事件并更新原日程；自定义表连内容删除后可在 30 天内整表恢复，到期自动清理。仅规划，未改业务代码 |
| 验证 | 5 个 Markdown 文件、22 个本地链接、空白及全部既有交接历史保留检查通过；未运行应用测试、构建、模型调用、设备验证或数据迁移 |
| 后续 | 设计关联更新、恢复材料、字段变更和原待处理替代入口；区分回收站恢复与现有同步墓碑 |

### 2026-10-29 / 确认待办分类、普通笔记兜底与首版字段类型

| 字段 | 内容 |
|---|---|
| 任务 | 将用户最新三项确认写入规划，移除已经解决的待定问题 |
| 变更文件 | README、RM_HANDOFF、CONTEXT、表与笔记改版规划、ADR 0020 |
| 状态 | 已确认带截止时间待办保持类型；普通笔记无其他归属时进入事件表且保持笔记类型；字段按表定义、逐条填写，首版六种类型。仍为规划阶段，未改业务代码 |
| 验证 | 5 个 Markdown 文件、22 个本地链接、空白及既有交接历史保留检查通过；未运行应用测试、构建、模型调用、设备验证或数据迁移 |
| 后续 | 继续确认事件联动与删除恢复，细化字段变更和原待处理内容的新入口 |

### 2026-10-29 / 确认表与笔记大改版的首轮产品规则

| 字段 | 内容 |
|---|---|
| 任务 | 整理用户的大改版要求及本轮答复，记录已确认目标并标出待定问题 |
| 变更文件 | README、RM_HANDOFF、CONTEXT、表与笔记改版规划、ADR 0020 与相关权威文档目标提示 |
| 状态 | 规划中；确认笔记式表、三个不可删默认表、日程/事件语义、日历只显示、首页表展示、AI 内容/结构权限、删表可恢复、旧事项迁移、普通知识进表和首版自定义字段；未改业务代码 |
| 验证 | 15 个 Markdown 文件静态核对通过，95 个本地链接有效，既有交接历史完整保留；验证脚本早期把代码示例误作链接的误报已修正。未运行应用测试、构建、模型请求、设备验证或数据迁移 |
| 后续 | 细化分类、笔记归属、字段、关联更新、恢复与待处理替代入口；全局知识仍独立且人工确认 |

### 2026-10-25 / 清理公开仓库历史与运行记录

| 字段 | 内容 |
|---|---|
| 任务 | 从 GitHub 可达的分支和版本标签历史移除已清理的生成资料及专用说明，并删除 GitHub Actions 旧运行记录 |
| 变更文件 | README、RM_HANDOFF、AGENTS、`.gitignore`、产品文档和版本说明 |
| 状态 | 公开分支与 tags 已重写；Release 页面与分发资产保留，旧 Actions 运行记录已移除；工作流已重新启用，当前运行记录为零 |
| 后续 | 旧克隆和其他托管副本需要重新克隆；本机生成内容保持 ignored |




