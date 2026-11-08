# DSH 手机 Agent 的权限、工具与运行时研究

> 调研日期：2026-11-03（Asia/Singapore）
>
> 目标：为“懒狗秘书”的专用秘书 Agent 提炼可借鉴的权限、可靠性与检索设计，不实现业务代码。
>
> 标记：`已验证事实`只来自固定提交中的源码或项目文档；`判断/建议`是针对本项目的工程结论。

> **2026-11-08 更新**：当前 `dsh-mobile-apk` 固定提交为 `949ba349887b663749f56e6c50eec818568d5bb2`，运行清单钉住上游 `deepseek-harness 66491b05e3f05ad35bcdd4f6cd7ed26041d9e3db`（0.2.2-rc.1）。该版本 `dsh-agent-loop` 明确“没有内置轮次预算”，工具调用或 steering 会让当前轮次继续；`dsh-repeat-tool-reminder` 在重复 3、5、8 次时只注入提醒，不阻断。持久上下文压缩、单请求超时、协作取消和工具结果配对仍保留。下文 2026-11-03 的 0.2.1 事实保留为历史证据，不能替代当前钉住版本。

## 1. 证据边界与版本结论

`已验证事实`

- 手机壳仓库当前 `main` 为 `c2053739985801dcecfa621eb40c08d3ba6c79cc`；当前上游 `master` 为 `8bd073392eef6f54e921a093b95076248eb08cbb`。
- 但手机壳在固定提交中的运行清单把实际引擎钉在 `dsh-v0.2.1-rc.3 / 1f81c047fc48fa190a683e469daa699857e9afe8`，而不是当前 `master`。[engine-overlay.json](https://github.com/kelai141/dsh-mobile-apk/blob/c2053739985801dcecfa621eb40c08d3ba6c79cc/scripts/snapshot-config/engine-overlay.json)、[RUNTIME-PATCHES.md](https://github.com/kelai141/dsh-mobile-apk/blob/c2053739985801dcecfa621eb40c08d3ba6c79cc/docs/AGENTS/RUNTIME-PATCHES.md)
- `RUNTIME-PATCHES.md` 也明确说明上游 checkout 只读，壳通过补丁、插件和壳侧适配扩展能力；不能把这些适配结果当成上游原生行为。
- 本次把实际钉住版本的源码作为“手机壳实际使用能力”的主要证据；当前 `master` 只用于确认后续接口方向。逐项抽样发现 `jobs`、会话恢复和搜索核心在 `1f81c047` 与 `8bd07339` 间相同；权限预设、审批、提问和 read 的提示/生命周期实现存在差异，不能无条件混用。
- 没有 clone 大型仓库、执行下载脚本、读取本地密钥或运行远端代码。仓库当前 SHA 只通过 `git ls-remote` 和固定提交原文核验。

`判断/建议`

- 设计文档必须同时写“当前上游 API”与“手机壳实际钉住的 API”，否则容易把新版本能力误认为已经装进参考 APK。
- 本项目应吸收机制，不复制壳工程中的 Android、ADB、Shizuku 或 root 权限实现。

## 2. 八项高价值事实与迁移建议

### 事实 1：权限预设捆绑“执行范围”和“审批策略”，不是角色扮演

`已验证事实`

- 实际基础组合配置了 `read-only + ask`、`workspace-write + ask`、`danger-full-access + never` 三档；未设置环境覆盖时，新会话默认 `workspace-write`。[基础组合配置](https://github.com/deepseek-ai/deepseek-harness/blob/1f81c047fc48fa190a683e469daa699857e9afe8/packages/bundle/base/cordis.patch.yml)、[权限预设源码](https://github.com/deepseek-ai/deepseek-harness/blob/1f81c047fc48fa190a683e469daa699857e9afe8/packages/interaction/permission-presets/src/index.ts)
- 默认预设用于新会话；已有会话保存自己的权限事实。预设切换通过各权威 setter 落日志，模型可见结果仍由底层 sandbox 与 approval 状态决定。
- `never` 的真实含义是“不向用户提问，并把需要审批的请求直接拒绝”，不是 `allow-always`；`danger-full-access` 让原本不触发审批的操作直接执行，仍不授权操作系统或应用领域中的任意动作。

`判断/建议`

- 为本项目定义应用域预设，例如 `只读`、`日常秘书`、`完全表管理`。预设应明确列出可用工具、是否可改正文、是否可删表/字段，并保存到每个会话。
- 修改全局默认只影响新会话；当前会话的“完全表管理”必须显式切换并立即显示在权限芯片中。
- 不照搬：上游 `danger-full-access` 是文件系统和命令执行概念，不是“可管理本应用任意表”的授权。

### 事实 2：工具可见性与系统权限必须分层，并支持持久化解锁与撤销

`已验证事实`

- 手机壳把 29 个以上设备工具按组隐藏，初始只暴露 4 个入口；facade 解锁某组后，该组工具才进入模型工具表。[能力门源码](https://github.com/kelai141/dsh-mobile-apk/blob/c2053739985801dcecfa621eb40c08d3ba6c79cc/plugins/dsh-android-bridge/src/capability-gate.ts)、[工具预算清单](https://github.com/kelai141/dsh-mobile-apk/blob/c2053739985801dcecfa621eb40c08d3ba6c79cc/scripts/tool-surface-budget.json)
- 解锁状态以原子文件持久化，坏文件或未知版本按“全锁”处理；同时提供 `off` 撤销路径。“用户曾经解锁”和“底层通道此刻可用”是两个独立事实。
- 该实现遇到意外的工具限制安装异常时选择记录后 fail-open，保留工具可见性；这是出于工具消失排查体验做出的取舍。

`判断/建议`

- 本项目采用相同分层：系统权限、会话权限、工具组可见性、目标表/字段范围分别判断；任一层单独通过都不能执行写操作。
- 用按需披露减少模型工具面和上下文占用：初始暴露 `table_list`、`table_search`、`content_read` 与能力说明，解锁后才出现批量写入、结构和删除工具。
- 不照搬 fail-open。表与字段操作可能不可逆或污染数据，工具限制安装失败时必须拒绝该类工具，并给出可诊断错误。

### 事实 3：授权必须在真正执行的服务面复查

`已验证事实`

- 手机壳的设备控制工具除工具壳前置检查外，还在内部 `controlExec` 服务面重新检查会话档位、调用来源、危险路径和屏幕范围；其注释明确把工具层检查称为 UX 快速路径，把服务面检查称为安全地板。[执行面源码](https://github.com/kelai141/dsh-mobile-apk/blob/c2053739985801dcecfa621eb40c08d3ba6c79cc/plugins/dsh-android-bridge/src/index.ts)
- 回归测试观察“请求是否真的投递到控制队列”，而不是只比较错误文案；因此可抓到“判据存在但没有挂到执行路径”的缺陷。[gate-exec-path.test.mjs](https://github.com/kelai141/dsh-mobile-apk/blob/c2053739985801dcecfa621eb40c08d3ba6c79cc/plugins/dsh-android-bridge/test/gate-exec-path.test.mjs)

`判断/建议`

- 每次 `content_create/update/delete/move`、`schedule_change`、表创建/改名/删表/字段变更，都要在 repository 事务内重新检查会话权限、目标 revision、默认表约束和删除范围。
- 工具层的“已授权”按钮只负责交互提示；不能被模型参数、缓存状态或另一插件绕过。
- 测试应断言仓储写函数是否被调用、事务是否提交，而不只断言模型收到“失败”字符串。

### 事实 4：审批是一次性、失败关闭、可审计；提问可以有限等待而不是永久卡住

`已验证事实`

- 上游审批结果是闭集：只有 `allowed-once` 授权；`rejected`、`cancelled`、`unavailable` 全部拒绝继续。无应答者、应答者异常或非法返回值都按关闭处理，`never` 策略在分发前直接拒绝。[审批源码](https://github.com/deepseek-ai/deepseek-harness/blob/1f81c047fc48fa190a683e469daa699857e9afe8/packages/interaction/user-approval/src/index.ts)
- 每次请求记录 `approval/asked` 与 `approval/decided` 审计对；取消信号会撤回答题，迟到回答被丢弃。[审批文档](https://github.com/deepseek-ai/deepseek-harness/blob/8bd073392eef6f54e921a093b95076248eb08cbb/docs/subsystems/approval.zh.md)
- `ask_user_question` 的 timed 模式到期后返回 `pending`，问题仍可回答，模型可继续独立工作；`pending` 明确不等于用户同意，也不能当作跳过答案。[timed.ts](https://github.com/deepseek-ai/deepseek-harness/blob/1f81c047fc48fa190a683e469daa699857e9afe8/packages/interaction/tool-ask-user/src/timed.ts)
- 手机壳把提问与审批映射到通知回复，并将用户决定先落盘再投递；失败会重试、显示可见失败并提供重试，不会无限停在“等待”。[NotifyDecisionQueue.kt](https://github.com/kelai141/dsh-mobile-apk/blob/c2053739985801dcecfa621eb40c08d3ba6c79cc/app/src/main/java/com/dsharnessmobile/shell/NotifyDecisionQueue.kt)、[NotifyActionReceiver.kt](https://github.com/kelai141/dsh-mobile-apk/blob/c2053739985801dcecfa621eb40c08d3ba6c79cc/app/src/main/java/com/dsharnessmobile/shell/NotifyActionReceiver.kt)

`判断/建议`

- 标准模式的表结构、删表和全局知识使用绑定 operation ID、目标 revision、会话 ID 和参数摘要的一次性确认；等待期间权限或数据变化会使确认失效。完全权限直接执行这些已授权动作，不重复制造同权限审批。
- 普通信息缺口使用 timed question：到期显示“仍在等待回答”，允许用户稍后作答；不能静默占住整个运行。
- 用户关闭应用、断网或进程重启时，审批结论必须有明确状态；未落盘的决定不能当作批准。

### 事实 5：长任务应成为可重连的 Job，而不是一个长 HTTP 调用

`已验证事实`

- 上游 Job 有稳定 ID 和 `running/stopping/completed/killed/failed` 状态，提供增量输出、进度、读取、等待和取消；所有者会话限定访问。`turn/end` 不代表有主 Job 已停止。[Job 源码](https://github.com/deepseek-ai/deepseek-harness/blob/1f81c047fc48fa190a683e469daa699857e9afe8/packages/jobs/jobs/src/index.ts)、[Job 文档](https://github.com/deepseek-ai/deepseek-harness/blob/8bd073392eef6f54e921a093b95076248eb08cbb/docs/subsystems/jobs.zh.md)
- 输出使用有界环形缓冲和绝对字节偏移；读者可断线后从 offset 继续，丢失部分必须报告 `lossy`，不能伪装成完整输出。
- 手机壳的前台服务和看门狗属于 Android 壳能力：服务先进入前台再初始化，按健康探针和活动信号决定是否受控重启，并持久化“用户已手动关停”。[EngineService.kt](https://github.com/kelai141/dsh-mobile-apk/blob/c2053739985801dcecfa621eb40c08d3ba6c79cc/app/src/main/java/com/dsharnessmobile/shell/EngineService.kt)、[EngineProbe.kt](https://github.com/kelai141/dsh-mobile-apk/blob/c2053739985801dcecfa621eb40c08d3ba6c79cc/app/src/main/java/com/dsharnessmobile/shell/EngineProbe.kt)

`判断/建议`

- 超过普通交互时限的整理、导入、批量迁移或长检索建立本地 Job：`job_id`、阶段、心跳、滚动进度、部分结果、取消和最终回执都持久化。
- UI 允许离开秘书页后返回并恢复输出；模型只读取受影响片段，不反复重发全部输出。
- 看门狗依据协议心跳、流 chunk 和工具事件判断停滞，不依据“模型正在思考”的 UI 文案；重启前保留当前阶段和未知副作用标记。
- 不照搬具体 Android root、ADB 或 Shizuku 授权；它们是设备控制权限，不是本应用的表权限。

### 事实 6：会话必须可恢复；真实副作用未知时禁止盲目重试

`已验证事实`

- 上游会话以追加式事件日志作为恢复依据；崩溃后修复可证明未完成的尾部，不把半成品当作成功。这里引用的 repair 实现证明恢复语义，不单独据此推断底层每次写入的 fsync 策略。
- 如果工具调用已记录开始但结果未持久化，恢复会生成 `TOOL_OUTCOME_UNKNOWN`，要求先核对或询问；只有只读或幂等操作才可直接重试。若开始都未记录则生成 `TOOL_NOT_STARTED`。[会话修复源码](https://github.com/deepseek-ai/deepseek-harness/blob/1f81c047fc48fa190a683e469daa699857e9afe8/packages/core/session/src/repair.ts)
- 手机壳还区分传输成功与业务成功：HTTP 响应包装层 `ok` 不足以证明命令完成，必须继续检查壳侧 `data.ok`，否则非零退出或截断输出会被误报成功。[真实回执检查](https://github.com/kelai141/dsh-mobile-apk/blob/c2053739985801dcecfa621eb40c08d3ba6c79cc/plugins/dsh-android-bridge/src/index.ts)

`判断/建议`

- `content_create` 等工具返回持久化操作结果：`applied/rejected/needs_clarification/stale/conflict/failed/unknown`，并带 operation ID、目标 ID、旧/新 revision 和实际部分结果。
- 模型文本、SSE 正常结束或 HTTP 200 都不能代替仓储提交回执。App 重启发现开放写入时显示“结果未知”，先读取目标状态，再决定重试或补偿。
- 相同幂等键重复请求返回原回执；删除、改表和跨对象联动使用可恢复日志、前像与 CAS。

### 事实 7：搜索与读取分离，所有结果都有边界、截断和超时事实

`已验证事实`

- 上游 `glob/grep` 与 `read` 是不同工具包。搜索只返回路径、匹配预览和上限信息；需要上下文时再按 `read(offset, limit)` 读取窗口。[搜索源码](https://github.com/deepseek-ai/deepseek-harness/blob/1f81c047fc48fa190a683e469daa699857e9afe8/packages/fs/tool-fs-search/src/search-core.ts)、[读取源码](https://github.com/deepseek-ai/deepseek-harness/blob/1f81c047fc48fa190a683e469daa699857e9afe8/packages/fs/tool-fs/src/read.ts)
- 搜索默认有 30 秒协作式超时、原始输出上限、单行预览上限和结果数量上限；超时取消使用稳定 `SEARCH_ABORTED`，溢出不会被静默解析成“不完整即完整”。超过内联上限的完整结果可另存 spill。
- 上游 timeout policy 只能请求遵守 `exec.signal` 的工具停止；忽略取消的工具仍可能拖住调用方。因此“声明了超时”不等于“保证不会卡死”。

`判断/建议`

- 把现有 `table_search` 与 `content_read` 明确分工：搜索返回稳定 ID、表 ID、类型、revision、短摘要、命中原因、`truncated/cursor/total_estimate`；读取只接受 ID 或用户明确范围，并返回实际读取区间。
- 搜索先按表、类型、时间、字段和关键词缩窄；片段足够立即停止，只有不足时才批量读取详情。每轮共享总预算，失败重试不重置。
- 不照搬：参考项目的搜索是文件路径/正则语义，并未证明存在业务表的语义查重或表结构理解。本项目需要另建 table-aware 查询与重复候选能力。
- 本项目确认目标新增自动查重：跨全部表计算不含 `table_id` 的内容指纹（规范化标题、正文、类型、业务时间和关键字段值）；同一对象复用 ID，兼容的新事实自动补充，同标题但业务时间/身份不同则分别保存。相似度和标题本身不能作为合并证据；只有身份、时间、地点、数值或归属存在无法解决的冲突时才询问。即使模型没有读取权限，仓储也应在不泄露正文的前提下执行内部查重。

### 事实 8：预算管理靠计量、剪枝与压缩恢复，不是无限加大超时

`已验证事实`

- 上游在请求前按模型上下文容量检查压力，先剪裁超大工具结果，再摘要最旧的安全范围并保留近期尾部；确认上下文溢出后会压缩并至多重试一次。[压缩文档](https://github.com/deepseek-ai/deepseek-harness/blob/8bd073392eef6f54e921a093b95076248eb08cbb/docs/subsystems/compaction.zh.md)、[基础压缩说明](https://github.com/deepseek-ai/deepseek-harness/blob/1f81c047fc48fa190a683e469daa699857e9afe8/packages/compaction/compaction-basic/README.zh.md)
- 压缩使用持久标记对和可取消事务；摘要失败不伪造成功，已完成的剪枝或上一个检查点继续有效。

`判断/建议`

- 为秘书 Agent 分开设置首字节、流空闲、工具队列、审批等待和总运行时限；审批等待与真实的网络/工具停滞使用不同状态。
- 每次模型切换重新按目标上下文窗口计算预算；压缩检查点保留用户意图、已执行工具回执、未完成 Job、表对象 ID/revision 和待确认候选，不能只生成一段泛化摘要。
- 达到硬预算时返回“已覆盖范围、遗漏范围、下一步”，并允许 Job 分批继续；不能无限换词搜索或反复重试。

## 3. 面向“懒狗秘书”的收敛设计

`判断/建议`

以下是根据父任务已确认目标整理的迁移映射，不是参考项目的既有能力；目标契约见 [ADR 0024](../adr/0024-secretary-agent-permissions-and-deduplication.md) 与[专用设计](../secretary-agent-design.md)。权限选择采用四项清楚的应用域预设：

| 预设 | 读取/搜索 | 表内内容 | 表结构/收纳目标 | 全局知识 |
|---|---|---|---|---|
| 只读 | 允许 | 禁止 | 禁止 | 只读/禁止写 |
| 标准秘书 | 允许 | 允许 | 每项确认 | 每项确认 |
| 完全权限 | 允许 | 直接增改删/移动 | 直接建删表、改名、字段和收纳调整，含三个预置默认表 | 直接增改删 |
| 自定义 | 按动作 | 按动作 | 按动作 | 按动作 |

“完全权限”表示有权调用全部表域工具，工具仍可按需披露，不表示绕过数据不变量；它不包含任意 OS/文件/网络操作、API Key 或修改自身授权。完全权限可删除三个预置默认表，删除后重启不得重建；因此初始化、收纳目标映射和回收恢复必须独立设计。旧版升级和新安装默认仍是“标准秘书”，不自动扩大授权。

写入流程应收敛为：`search candidates -> exact duplicate check -> near-duplicate/evidence check -> permission/revision check -> CAS transaction -> durable receipt -> projection update`。标准模式在需要时插入 one-shot confirmation；完全权限使用同一执行内核但不重复弹出同权限审批。重复检查必须在最终提交事务内再次执行；用户长时间未答或恢复后不能沿用过期搜索结果。

运行状态建议明确区分 `queued`、`streaming`、`tool_running`、`waiting_user`、`waiting_approval`、`compacting`、`cancelling`、`interrupted`、`failed`、`completed`。UI 和模型看到同一状态；只要处于等待态，就不要显示为“卡住”，但超过阶段期限必须给出可操作原因。

## 4. 明确不照搬

`判断/建议`

- 不把 `danger-full-access`、Android root、ADB、Shizuku、无障碍或“允许所有文件访问”当作表管理权限。
- 不复制移动端持续前台服务作为唯一执行保证；项目应依靠可恢复 Job 和持久回执，Android 后台能力只能是平台适配层。
- 不复制通知重试的具体秒数、压缩阈值或工具结果上限；这些值需要在本项目设备、模型和真实表规模上测量。
- 不宣称参考项目具备业务语义查重。本次所查的权限、运行时、搜索与压缩源码/文档只证明文件名和正则搜索、预算、spill 与超时，没有证明表内容语义去重。

## 5. 未确认项

- 已确认手机壳清单声明实际引擎为 `1f81c047…`，但没有下载并解包发布 APK 逐字节证明某个具体 Release 资产也使用同一快照；实际 APK 的可复现来源仍应由发布 provenance 证明。
- 当前 `master` `8bd07339…` 与手机壳固定 `1f81c047…` 存在版本差；设计应优先采用钉住版本既有能力，再单独评估当前 master 的新功能。
- 参考项目没有为本项目表模型提供查重键、相似度阈值、冲突合并策略或真实规模数据；查重规则已在专用设计中确定，召回质量和真实规模性能仍须实施阶段用固定语料及本地基准验证。
- 通知、后台保活和重启行为依 Android 版本、厂商策略和用户授权变化，不能从参考实现直接推得本项目的 SLA。
