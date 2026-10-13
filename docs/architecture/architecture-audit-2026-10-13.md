# 项目架构审查：可维护性、可靠性与可配置性

> 日期：2026-10-13（Asia/Singapore）
> 审查基线：`main` / `ced0755`，应用版本 `1.1.1+3`
> 性质：基于当前仓库的评估与建议，不新增或取代 ADR，不批准实现范围与顺序变更。

## 结论

架构方向合理，已具备继续演进的基础，但当前实现尚不能认定为同时满足“高可维护性、高可靠性、高可配置性”。

| 维度 | 当前判断 | 主要依据 |
|---|---|---|
| 可维护性 | 部分满足，仍处于模块迁移中 | 已拆分五个模块，有快照、适配边界和契约测试；UI 仍集中依赖 `AppController`，同步绕过成果库快照，领域模型混入 Flutter |
| 可靠性 | 尚不满足高可靠性 | 存在文件替换中断窗口、图片策略未执行、SSE 完成判定缺失、工具结构校验不足、同步身份校验缺失和冲突裁决不收敛 |
| 可配置性 | 基础配置满足，策略配置不足 | 可设置模型 URL、名称、Key、主题和图片开关；能力声明、配置校验、版本迁移、超时与重试策略仍不完整 |

当前适合定位为本地优先的预发布应用。294 项既有主机测试通过，不能替代存储中断、真实云盘、后台通知或线上模型验收。

## 项目现状与已有优势

- Android 手机、平板和 Windows 共用 Flutter 代码；没有集中式后端，离线查看和成果编辑有独立本地路径。
- Markdown 是成果权威副本；SQLite 索引支持重建，已有墓碑、三项 hash 判定和冲突副本。
- `DevicePreferences`、`ResultLibrary`、`CaptureWorkflow`、`ConversationWorkspace`、`SyncWorkspace` 已各有职责和测试，成果快照冻结了列表。
- 模型采用 OpenAI 兼容请求，Key 使用系统安全存储接口；捕获在分析前保存原文，模型不可用时有本地规则回退。
- 仓库有 ADR、交接、Conventional Commit、Git hooks、格式/分析/测试 CI 和标签发布工作流。
- `AppController.bootstrap` 实际装配的是 `MemorySyncProvider`。OneDrive、百度网盘归档、本地通知和后台调度尚未完成；这些是明确的能力缺口，不等同于已有功能运行失败。

实际依赖更接近 `UI → AppController → modules → services/data → core`。`AppRuntime` 主要负责生命周期；生产依赖装配仍在 `AppController`，`domain/` 当前主要只有失败契约。

## 优先问题

P1 表示涉及用户数据、隐私或核心不变量，应在扩大真实使用或接入真实同步前处理；P2 表示演进、状态一致性或工程门禁问题。严重程度是本次审查判断。

### F1 / P1：图片出网开关没有进入模型请求边界【已复现】

位置：`app/lib/services/chat_service.dart:30`、`:54`；`app/lib/ui/pages/conversation_page.dart:78`。

`allowImageEgress` 只用于禁用相册/拍照按钮。`ChatService` 构造上下文时继续读取历史图片并发送，系统分享路径也没有在请求边界检查该开关。

复现：保存一条含图消息，配置 `allowImageEgress=false`，调用 `streamReply`；Mock HTTP 捕获的请求仍含 `data:image/png;base64,...`。用户关闭开关后继续旧会话即可触发历史图片重发。

建议：在统一模型请求策略中检查当前配置，对所有入口和历史图片执行同一规则；测试关闭开关、分享输入、重试和旧会话。

### F2 / P1：正常 EOF 被当作完整模型响应【已复现】

位置：`app/lib/services/model_client.dart:154`；`app/lib/modules/conversation/conversation_workspace.dart:263`、`:281`。

模型客户端忽略 `[DONE]`，没有把明确完成信号传给会话模块。会话模块在流 `onDone` 后执行工具调用。因此网关提前正常关闭连接、没有异常但也没有完成标记时，仍可能产生自动副作用。

复现：返回完整的一段 `create_result` 参数后直接 EOF，不发送 `[DONE]` 或 `finish_reason`；仍创建 1 个成果，消息状态为 `complete`。

建议：把“正常完成/异常中断/用户取消”作为显式流协议，只有满足适配器的完成条件才执行工具。另需设置首包后空闲超时和总时限：当前 45 秒超时只覆盖 `_client.send`，没有覆盖后续 SSE 消费；错误响应正文读取也没有期限。

### F3 / P1：Markdown 替换存在丢失权威副本的窗口【代码审阅风险，未执行磁盘故障注入】

位置：`app/lib/data/io_vault_store.dart:33`；`app/lib/data/result_repository.dart:300`。

写入流程是写固定 `.tmp`、删除旧 `.md`、重命名临时文件。删除后进程退出或 rename 失败会使原路径消失，启动扫描只接受 `.md`，没有 `.tmp` 恢复机制。相同路径并发写入还会共享临时文件。成果变更目录时也先删除旧路径，再写新路径。

文件写入与索引更新是两个操作；索引失败后 Markdown 可能已提交，而调用方仍看到失败，重试可能再次创建成果。当前可重建索引能缓解索引失配，不能恢复已丢失的旧文件，也不能保证命令幂等。

建议：落实各平台支持的可靠替换或可恢复日志方案、唯一临时路径、按成果串行写入与恢复扫描；明确“文件已提交但索引失败”的返回及恢复语义。验收应覆盖磁盘满、权限错误、替换阶段进程中断和并发写入。

### F4 / P1：自动记录没有严格执行工具 schema【已复现】

位置：`app/lib/modules/conversation/auto_record_processor.dart:82`；工具声明在 `app/lib/services/model_client.dart`。

请求中的 schema 声明 `sensitive` 必填，但执行层使用 `payload['sensitive'] == true`，缺失或错误类型被当作非敏感。字符串转换、日期 `tryParse` 和置信度阈值检查也不能替代结构校验；尚未统一拒绝未知字段、无效日期、超范围置信度、结束早于开始等情况。

复现：`knowledge` 参数提供有效标题/正文、置信度 0.95，却省略 `sensitive`；仍自动创建成果。此问题说明结构门禁不足，不说明系统具有独立敏感内容识别能力。

建议：在副作用前验证必填字段、准确类型、范围、日期和业务不变量；校验失败进入待整理或明确拒绝，不能用宽松默认值获得自动创建资格。

### F5 / P1：远端对象身份未校验，可覆盖另一成果【已复现】

位置：`app/lib/data/sync_engine.dart:170`、`:183`。

下载直接相信内容中的 frontmatter `id`，不确认它与 `remote.id`、路径及类型一致，也不重新核对内容 hash。`remote` 中剩余对象被当作新增下载，但实际写入目标可以是另一已有成果。

复现：本地已有成果 A；Provider 返回元数据 id=B、内容 id=A 的对象。在一轮同步中，A 先上传，B 后下载，A 的正文被该对象覆盖，无冲突副本。

建议：在同步入库前执行身份、路径、类型、状态和字节 hash 校验；拒绝草稿、非法对象和重复身份，不能让远端路径或正文直接选择写入目标。

### F6 / P1：冲突裁决没有建立新的同步基线【已复现】

位置：`app/lib/data/result_repository.dart:290`；`app/lib/data/sync_engine.dart:148`。

“保留本地”只删除冲突副本，没有记录已确认的远端版本和裁决意图；下轮依旧认为两端都偏离旧 hash，再次冲突。“使用远端”会改写本地 origin/revision，也保留旧基线，存在同样的收敛风险。连续未裁决轮次还会不断创建新的冲突文件。

复现：初次同步后同时修改两端，生成冲突；选择保留本地；下一轮再次返回 1 个冲突。

建议：将裁决与当前远端 eTag 绑定，保存裁决后的基线及待上传意图；条件写入失败后重新判定，并按远端版本去重冲突副本。验收要求一次裁决后下一轮收敛，且裁决期间新的远端变更仍保留。

### F7 / P2：同步与成果库快照分离【已复现】

位置：`app/lib/modules/sync/sync_workspace.dart:51`、`:78`；`app/lib/services/app_controller.dart:350`、`:354`。

同步直接写 `ResultRepository`，完成后只刷新报告和冲突文件，没有刷新 `ResultLibrary`。facade 的通知只能通知 UI 重建，无法更新其读取的成果列表。

复现：成果库快照标题为 original；同步接受远端标题 remote；直接读仓库已是 remote，成果库快照仍是 original。成果详情、日历和重复检查都可能继续使用旧值。

建议：为成果写入统一所有者设计明确的导入/裁决能力，并发布增量变化或刷新对应快照；不要把通知当作数据刷新。

### F8 / P2：持久化任务与命令幂等不足【代码审阅风险】

位置：`app/lib/modules/capture/capture_workflow.dart:70`、`:130`；`app/lib/modules/conversation/conversation_workspace.dart:254`、`:298`。

捕获保存为 processing 后若进程退出，启动只加载已有列表，没有恢复 processing 的执行路径。`acceptCapture` 没有检查当前账本状态或唯一动作键，重复调用会重新生成 UUID 成果。工具动作写在助手消息 JSON 中，成果创建与动作审计落盘没有共同的恢复协议。流式消息的异步保存未统一排队，finally 中保存失败也可能跳过生成状态清理。

建议：按捕获/工具调用建立稳定动作键、持久化状态机和可重放账本；启动恢复未完成动作，区分手动重试和自动重试；资源清理不应依赖持久化成功。

### F9 / P2：模块隔离与架构测试覆盖仍不充分【代码审阅】

位置：`app/lib/ui/app_scope.dart:5`；`app/lib/app.dart:19`；`app/test/architecture_test.dart:7`；`app/lib/core/models.dart:1`。

UI 全局订阅 facade，任一模块通知都会进入根 `AnimatedBuilder`。领域模型包含 Flutter 图标/主题，modules 直接依赖 concrete repository/service，未形成完整纯策略边界。架构测试按字符串片段检查 import，不解析规范化依赖图；不能充分约束跨层间接暴露、循环依赖或未列出的 package import，且当前还禁止 UI 直接导入部分模块。

建议：沿 ADR 0014 继续迁移页面到所需模块快照，把模型/同步准入规则抽成纯策略，UI 元数据与成果模型分开；升级依赖测试为规范化路径与明确允许规则。无需改为微服务或引入通用事件总线。

### F10 / P2：模型能力与配置生命周期未落地【代码审阅】

位置：`app/lib/data/settings_service.dart`、`app/lib/modules/settings/device_preferences.dart`、`app/lib/services/model_client.dart`。

URL、模型名和 Key 可替换，但没有 ADR 0009 要求的能力表或用户覆盖。分类固定请求 `json_object`，对话固定发送 tools 和图片 `detail=original`，兼容端点缺少这些能力时会失败。URL 和模型名只 trim，缺少保存前校验与连通性诊断；base URL 拼接路径的约定也未明确。

超时、上下文条数、图片数量/尺寸为代码常量；同步调度、重试上限、批量上限没有产品配置模型。固定 +08:00 是当前协议决定，不能简单改成任意时区配置；如需支持其他时区，应先定义日期语义并更新协议。安全阈值不宜作为无约束的任意配置。

建议：用版本化配置区分用户选项、运行策略和安全不变量；能力最小化默认、连接测试、配置导入导出时排除凭据，并对配置更新失败的部分落盘状态做恢复。

### F11 / P2：schema 迁移、坏文件诊断和大库增量能力不足【部分复现】

位置：`app/lib/data/sqlite_index_database.dart:16`、`app/lib/data/sqlite_conversation_store.dart:22`；`app/lib/data/result_repository.dart:204`；`app/lib/modules/results/result_library.dart:81`。

数据库仅 `CREATE TABLE IF NOT EXISTS`，未建立版本化 migration。Markdown 没有清晰的 schema 升级/兼容拒绝机制。启动全量重建、每次成果写入全量读文件并派生列表；尚无大库规模基准。

坏文件探针确认：无效 YAML 文件仍留在 vault，但重建返回成功并将它从索引排除，没有返回按文件的错误摘要。最初“坏 YAML 阻断整个重建”的假设被探针否定，不作为发现。

建议：数据库和文件格式分别建立迁移与恢复测试；坏文件保留并可定位，索引重建报告成功/失败数量；成果查询按索引与增量快照演进，检索按既定范围考虑 FTS。

### F12 / P2：当前静态门禁不通过，SDK 未精确锁定【实测与代码审阅】

`flutter analyze` 返回非零，现有 `app/tool/generate_large_scenarios.dart:160` 有 `unnecessary_brace_in_string_interps`。本轮没有修复该 lint，以保留审查基线。

常规 CI 使用 stable channel，没有指定精确 Flutter 版本；lockfile 能锁依赖，不能锁 SDK。现有矩阵主要证明确定性逻辑和 UI；未覆盖本次复现的隐私开关、流协议中断、同步裁决收敛与身份错配。

建议：修复 lint，锁定经过验证的 SDK，纳入故障与恢复测试；既有矩阵保留，但发布门禁应分别陈述主机、平台、存储恢复、真实同步和模型验收结果。

## 文档一致性

已按 AGENTS.md 先登记到 `RM_HANDOFF.md` 风险章节：

- 可执行方案第 7.1 节 `kind` 与同步协议/实现 `type` 冲突。
- 方案 embedding/向量索引候选残留与同步协议禁止向量索引冲突。
- MkDocs 发布描述与方案第 14 节不发布静态站冲突。
- 方案把全部 SQLite 表描述为可从 Markdown 重建，实际成果文件不能恢复捕获原文、会话和运行账本。
- Key 按端独立配置与“三端共用”描述应澄清；当前实现允许按端独立存储，不应推断强制复用。

交接顶部仍有“Windows 原生运行验证尚未完成”及“首版仅支持文本”旧描述，与已完成验证/图片对话进度不完全一致。应区分历史记录、当前状态、图片对话和独立 OCR 工作流，历史交接记录只追加纠正，不改写。

## 建议的改进顺序与验收

以下为评估建议，未替代交接中的正式实施顺序：

1. 先收口 F1–F6：请求边界策略、完整响应判定、严格工具校验、可靠写入/恢复、同步身份和冲突收敛。每项通过针对故障的回归，再扩大真实数据使用。
2. 完成 ADR 0014 后续迁移：统一成果写入与快照更新，页面按模块订阅，抽纯策略，建立 schema migration 和命令幂等。
3. 落地能力声明和版本化配置，明确可调策略与固定安全/协议不变量，固定工具链。
4. 补齐真实 OneDrive、发布归档、本地通知、后台恢复和备份恢复演练；用真实设备、断网、强停、令牌失效与并发修改分别验收。

## 本次真实验证与边界

| 检查 | 结果 |
|---|---|
| 起始 Git 状态及 hooks | `main...origin/main`，工作区干净；`core.hooksPath` 指向本仓库 `.githooks` |
| 必读文档、ADR 0001–0014、模块/存储/请求/CI 审阅 | 已完成 |
| `flutter analyze` | 失败：1 条现有 info lint，详见 F12 |
| `flutter test --no-pub --reporter expanded` | 294/294 通过 |
| 临时故障探针 | 修正一个被否定的坏 YAML 假设后，7/7 符合观察结果；6 个行为问题复现，1 个坏文件静默排除行为确认 |
| `git diff --check`、提交 hooks、提交后状态 | 收尾执行，结果同步到 RM 交接 |
| release 构建、原生/AVD、真实云模型、云盘联调、磁盘故障注入、性能基准 | 本轮未执行 |

命令通过 `E:/DevTools/flutter/bin/flutter.bat` 执行。临时探针及日志在忽略目录 `app/build/architecture_audit_probe_test.dart`、`architecture-audit-probes.log`、`architecture-audit-regression.log`，不作为正式回归提交；报告已记录复现输入和观察结果。探针断言的是当前问题行为，其通过不表示产品满足可靠性要求。

本轮仅提交审查文档和交接，不修改运行代码、既有测试或已接受的架构决定。
