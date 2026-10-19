# RM 交接总文档

> 本文件是本项目唯一完整的 Agent 交接入口。顶部保存当前状态，底部只追加变更记录。

## 1. 文档状态

| 字段 | 当前值 |
|---|---|
| 项目名称 | 懒狗秘书（新显示名已确认，运行版本仍使用个人 AI 收件箱） |
| 最后更新时间 | 2026-10-20 |
| 时区 | Asia/Hong_Kong |
| 最后修改 Agent | Codex |
| 当前阶段 | `v1.1.2` 已预发布；懒狗秘书改造 S1 权限快照/迁移与 S2 普通成果版本保护/撤销账本已实现并局部验证；读取工具、全局知识审批、对话界面/扩展与 100 例矩阵仍在进行 |
| 总体状态 | `app/` 生产启动由 `AppRuntime` 装配端配置、成果库、捕获、会话和同步模块；页面直接订阅所属模块，`AppController` 已从生产源码删除。知识查询基于 SQLite v3 规范化索引按 50 项分页；Markdown 仍为成果权威副本。工具链固定 Flutter 3.47.6 / Dart 3.13.5。本轮为主机测试与三端模拟器/桌面验收，未连接真实云盘或真实模型 Key。`v1.1.2` GitHub 预发布版仍使用 Debug 证书，Windows 包未代码签名；OneDrive、百度网盘、通知和真实跨端同步尚未完成。 |

## 2. 一句话交接

2026-10-20 执行状态：S1 已将三组默认权限加入设置 schema v3，将会话快照加入 `conversations.sqlite3` v2，并提高 SQLite 启动迁移协调器的支持版本。首次全开、设置导入/恢复默认、独立会话快照及 v1 会话迁移已由 27 项定向测试验证，定向 Dart analysis 零问题；记录见 [S1 测试结果](test-results/secretary-s1-permission-snapshots/verification.md)。模型工具尚未按权限执行，仍需后续 S5 接线；S1 通过不代表改造全部完成。

2026-10-20 执行状态：S2 已在成果库加入 expected revision/hash 改删、稳定动作键、SQLite `reversible_actions` v4、10 分钟建议撤销与事务恢复；跨端迁移协调器支持索引 v4。28 项定向测试和静态分析通过，见 [S2 测试结果](test-results/secretary-s2-result-actions/verification.md)。这是普通成果接口，当前 AI 尚未调用；权限执行、全局知识确认例外与检索预算仍待 S3–S5。

2026-10-20 实施/验收细化：[实施任务](docs/secretary-implementation-plan.md) 已定义 S0–S12 的依赖、接口/状态、迁移、文件范围及完成门禁；[SEC-001–100 清单](docs/testing/secretary-100-case-plan.md) 已逐例安排。用户明确三端合计 100 例（50/25/25），在业务修改完成及局部验证通过后执行，非每端 100，也不授权全项目全量测试。复用现有 runner/AVD 基础，新增专用数据与设备入口；本轮仅文档，未启动模拟器、未实施或执行新矩阵。

2026-10-20 检索约束补充：用户要求非必要不检索以节省开销、提高速度。已补[检索策略](docs/ai-retrieval-policy.md)：上下文足够零检索、不新增云端判断调用、按需最小来源/片段、足够即停、统一预算、去重及版本/权限感知缓存。初始限额为可调整建议，未做性能测量或业务实现；不能把少检索解释为省略写前版本与审批检查。

2026-10-20 追加规划已确认：软件显示名“懒狗秘书”，AI 默认秘书型助理；全局知识使用已确认基础事实，随成果三端同步，AI 按需检索且受当前会话读取权限控制，新增/修改/删除均须人工确认。见 [ADR 0018](docs/adr/0018-confirmed-global-knowledge-for-secretary.md)、[补充计划](docs/secretary-and-global-knowledge-plan.md) 与同步协议第 17 节。原三个待答问题已收敛，普通成果仍按原权限直接操作；本轮仅规划，未开始业务实现。

2026-10-20 当前规划：两轮产品选择已确认，见 [ADR 0017](docs/adr/0017-conversation-permissions-and-reversible-result-actions.md) 和[改造计划](docs/ai-conversation-redesign-plan.md)。收件箱直接改为 AI 对话，每次进入显示新对话，侧边管理会话，待处理独立成页；三组权限为读取、新增、修改与删除，初始默认全开，各会话独立保存。AI 按用户要求直接改删成果并支持撤销，其他会话只读；语音转写和朗读、文件、深度思考纳入计划；联网仅用当前模型接口内置能力，不支持时禁用。不再将先前草案的六项问题视为待答；业务代码未改。

架构整改阶段 A–F 已完成并按阶段提交。阶段 E 的全量主机回归为 339/339；阶段 F 仅运行受影响测试（64 项通过），静态分析、格式检查、Web/Windows/Android release 构建及 Windows 冒烟通过。当前无连接 Android 设备，因此 AVD 冒烟未执行；未重跑全量测试。真实云盘、通知、代码签名、真实用户目录升级和物理断电仍为未验收能力。

2026-10-13 补充：已完成[架构审查](docs/architecture/architecture-audit-2026-10-13.md)。架构方向合理，当前仍部分满足可维护性和基础可配置性，尚不满足高可靠性；本轮只形成审查与建议，没有修复运行代码，也未替代既有 ADR 或正式实施顺序。

2026-10-18 补充：2026-10-18 将 `main` 上 7 个整改提交推送到 `origin/main`（`ced0755..1927647`，快进，无强推），GitHub Flutter CI 运行成功。同日新增[真实端到端测试矩阵](docs/architecture/realistic-e2e-matrix.md)：100 条多步骤跨模块场景，在 Pixel 6 AVD（50 条）、2560×1600 平板 AVD（25 条）和 Windows 桌面（25 条）上全部通过；主机全量回归 376/376。矩阵发现并修复了 `StatusPill` 在手机 1.15x 字体下的 7.1px 横向溢出。同日发布 `v1.1.2` 预发布：Release 工作流全部通过，四个资产齐备，下载后校验 SHA-256 与 `SHA256SUMS.txt` 一致。

## 3. 当前目标与范围

### 目标

- 建立手机、平板、Windows 三端独立 App 的完整本地闭环。
- 以 Markdown 为权威存储，SQLite 只做索引、同步游标和幂等账本。
- 通过 OneDrive 交换定稿成果，通过百度网盘每日单向归档。
- 云端模型只提出结构化候选或工具请求；本地核心按会话权限执行成果操作，模型不能绕过成果库。新增的读取/改删目标契约见 ADR 0017，尚待实现。

### 当前范围

- 当前客户端位于 [app](./app)。
- 本机 Windows 开发工具链已迁移到 `E:\DevTools`：Flutter、Android SDK、Gradle、AVD 和 Anaconda 均通过原 C 盘 Junction 兼容旧命令，设备验收脚本同时支持直接发现 E 盘路径。
- 本地核心采用模块化结构：`DevicePreferences`、`ResultLibrary`、`CaptureWorkflow`、`ConversationWorkspace`、`SyncWorkspace`；组合根和 UI 依赖关系由架构测试约束。
- 首版已覆盖本地捕获、Markdown 主库、SQLite 索引、收件箱、日历、待办、事项、知识、设置和同步演练；确认队列已并入收件箱。
- 日历工作区已覆盖日程、我的一天和待办三段切换；日程支持年、月、周、日、日程列表，默认进入详细月视图，月视图可切换概要模式。
- 事件与带截止时间的待办共同参与日历日期格、时间轴和日程列表投影；基础重复规则会展开到视图，已完成和未完成待办可区分显示。
- 事件和待办使用快速新建，默认带入当前选中日期与当前时间；事项和知识仍保留完整编辑页。
- 收件箱已覆盖多会话列表、首次内容创建会话、旧会话继续、重命名和删除；删除会话不删除已创建成果。
- 冷启动和普通重进直接进入首页；“新对话”只打开临时输入页，未发送退出不留空会话，启动时清理历史空会话。
- AI 对话支持文本、剪贴板粘贴、相册、拍照、图片预览和 Android 文本/图片分享入口。
- 对话使用 OpenAI 兼容 SSE 流式回复，可停止、重试，并保留中断半成品。
- 每轮只使用当前会话最近 20 条消息；历史图片最多来自最近 4 条含图消息、总量不超过 8 张。
- 模型通过 `create_result` 自动新建高置信、非敏感、无日期歧义且未重复的成果；风险和低置信项进入待整理区。
- 自动创建结果保留 10 分钟撤销；会话、消息、工具审计和本地图片均不参与 Markdown 同步。
- Android 已注册系统分享入口；Web 与 Android debug/release 构建可重复产出。
- 根目录已提供中文开源 README、MIT `LICENSE`、`SECURITY.md`、`CONTRIBUTING.md`、EditorConfig 和 Flutter CI。
- 公开发布使用干净单根提交；迁移前本地历史保留在 `archive/pre-open-source`，不推送。
- GitHub Release 采用 `v<major>.<minor>.<patch>` 标签；首发 `v1.0.0` 为预发布，同时提供 Android APK、Windows x64 安装包和便携 ZIP。
- Windows 安装器使用 Inno Setup，按用户安装并提供开始菜单、可选桌面快捷方式、卸载和安装后启动。
- OneDrive OAuth、百度网盘归档和真实云端模型回归尚未完成；Windows 原生运行验证已在既往完成。
- 个人服务器、端到端加密、多人协作和实时同步不在当前实现范围。

## 4. 权威文件

| 文件 | 用途 |
|---|---|
| [RM_HANDOFF.md](./RM_HANDOFF.md) | Agent 交接、当前状态、决定、验证和下一步的最高入口 |
| [AGENTS.md](./AGENTS.md) | Agent 阅读顺序、修改流程、交接要求和 Git 强制提交规则 |
| [CONTEXT.md](./CONTEXT.md) | 项目术语表，约束正式名称 |
| [可执行方案](./docs/personal-ai-inbox-executable-plan.md) | 产品目标、架构、范围与实施路线 |
| [同步协议](./docs/sync-protocol.md) | 成果文件、冲突、删除和同步流程 |
| [模型接入](./docs/model-integration.md) | 模型端点和接入边界 |
| [ADR 索引](./docs/adr/README.md) | 已接受且难以回退的架构决定 |

## 5. 已锁定决定

- 三端对等，各自拥有本地核心，不存在集中式后端。
- 一个成果一个 Markdown 文件，文件名使用稳定 `id`。
- 冲突保留副本并进入确认队列，删除使用 30 天墓碑。
- OneDrive 承担双向同步，百度网盘只做单向归档，个人服务器暂不实现。
- 变更判定使用三项 hash，不依赖设备时钟。
- 事项是一等实体，待办和事件通过 `matter` 声明归属。
- 关联单边存储，反向引用由本地索引派生。
- 三端统一使用 Flutter。
- 默认模型为 `deepseek-flash`，模型接入层保持开放。
- 每项正式任务必须更新本文件，形成一个 Conventional Commit，且提交后工作区必须干净。
- 源码以 MIT 协议公开发布；公开历史不得包含 API Key、OAuth 令牌、签名文件、本地 vault、原始附件、未脱敏设备标识或旧历史中的敏感提交。
- GitHub Release 资产和标签规则由 ADR 0012 管理；首发包允许 Android Debug 签名和未签名的 Windows 安装包，但必须明确标记为预发布。
- 模型不得绕过端内规则；隐式自动新增保留 ADR 0010 校验。ADR 0017 已确认三组会话权限、按用户要求直接修改/删除成果并可撤销，不允许 AI 改删会话或历史消息；新边界尚待业务实现。
- AI 页每次从应用导航进入显示新对话，历史会话从侧边显式选择；待处理独立成页。语音限定转文字输入和回复朗读；联网只用当前模型接口内置能力，不支持则禁用，不另接搜索服务或自动切模型/协议。
- 软件显示名“懒狗秘书”，AI 默认秘书型助理；ADR 0018 要求全局知识增改删均人工确认，按需检索受读取权限控制，已确认成果与删除墓碑参与三端同步，候选不出端。不能用高置信、默认全开、用途标识变更或普通成果工具绕过审批，均尚未实现。
- 图片在配置模型后默认允许出网；设置页提供默认开启的总开关，客户端自动缩放、重编码并去除 EXIF，但不自动遮蔽图片内容。

## 6. 当前进度与验证

### 已完成

- 2026-10-20：S1 会话权限快照与迁移已实现：新设置默认全开/可导入导出，旧设置和会话迁移为全开；现有会话权限独立保存，新会话复制当前默认。受影响定向测试 27/27 通过、指定文件 analysis 零问题。报告见 [验证记录](test-results/secretary-s1-permission-snapshots/verification.md)。

- 2026-10-20：S2 普通成果 CAS 更新/删除与持久化撤销账本已实现，索引迁移升至 v4；28 项 repository/index/migration/capture 定向测试及指定文件 analysis 均通过。报告见 [验证记录](test-results/secretary-s2-result-actions/verification.md)。AI 工具尚未连接。

- 2026-10-20：S2 普通成果 CAS 更新/删除与持久化撤销账本已实现，索引迁移升至 v4；28 项 repository/index/migration/capture 定向测试及指定文件 analysis 均通过。报告见 [验证记录](test-results/secretary-s2-result-actions/verification.md)。AI 工具尚未连接。

- 2026-10-20：完成 S0–S12 实施任务与三端新功能 100 例计划，覆盖界面/角色/更名、权限、检索预算、成果/撤销、全局审批、日期/同步、模型、文件和语音；明确 50/25/25 分配、每例状态断言、真实设备/受控服务边界、结果目录与定向重跑。规划检查见[记录](test-results/secretary-detailed-plan/verification.md)，未执行业务测试。

- 2026-10-20：补充[非必要不检索策略](docs/ai-retrieval-policy.md)，明确零检索场景、必要触发、来源/片段约束、初始限额、缓存失效、失败停止和定向验收，并同步原计划与模型接入。仅文档，检查见[记录](test-results/retrieval-constraints-plan/verification.md)。

- 2026-10-20：根据用户答复收敛全局知识的三端同步、权限化按需检索与增改删全确认要求；更新 ADR 0018、计划及同步协议第 17 节，维持四类成果与本地候选边界。仅文档变更，检查见[记录](test-results/global-knowledge-confirmed/verification.md)。

- 2026-10-20：追加[角色与全局知识库计划](docs/secretary-and-global-knowledge-plan.md)、ADR 0018 与术语/模型边界，定位当前角色提示及各端显示名文件；提出全局共享、读取和删除确认三项澄清。仅文档变更，验证见[记录](test-results/secretary-global-knowledge-plan/verification.md)。

- 2026-10-20：按用户两轮答复收敛 AI 对话改造计划，新增 ADR 0017 并同步术语、旧 ADR 取代注记、模型接入、可执行方案和 README。核对 DeepSeek 官方思考、工具调用及联网接口文档，明确当前 `/chat/completions` 缺少内置联网依据，计划禁用按钮；不接独立 Search / Fetch。本轮仅文档，验证见 [记录](test-results/ai-conversation-redesign-confirmed/verification.md)。

- 2026-10-20：完成 AI 对话界面与操作权限改造的首轮需求整理，形成[草案](docs/ai-conversation-redesign-plan.md)。仅文档变更，未执行运行测试；检查范围与结论见 [记录](test-results/ai-conversation-redesign-plan/verification.md)。

- 2026-10-18：`v1.1.2` 预发布已发布：Release 工作流 `39108705557` 在 Windows 2022 上完成标签校验、格式、分析、376 项主机测试、Android/Windows release 构建、APK 元数据与 Debug 证书校验、Inno Setup 编译、安装/卸载冒烟、便携包校验和上传；Release 为非草稿预发布，含 APK、Windows 安装包、便携 ZIP 与 `SHA256SUMS.txt`。
- 2026-10-18：准备 `v1.1.2` 预发布：`app/pubspec.yaml` 升至 `1.1.2+4`，新增 [发行说明](docs/releases/v1.1.2.md)，更新 README 下载入口；本地 Android/Windows release 构建通过，APK `versionName=1.1.2`、`versionCode=4`、minSdk 24、targetSdk 36、含 INTERNET 权限。
- 2026-10-18：`main` 上 7 个架构整改提交已快进推送到 `origin/main`（`ced0755..1927647`），GitHub Flutter CI 运行 `1927647` 成功；未使用 `--no-verify` 或强推。
- 2026-10-18：新增 100 条[真实端到端测试矩阵](docs/architecture/realistic-e2e-matrix.md)，覆盖 12 个分类、12 种步骤与 15 种断言；手机 AVD 50/50、平板 AVD 25/25、Windows 25/25 全部通过，主机全量 376/376。
- 2026-10-18：矩阵修复了 `StatusPill` 在手机 1.15x 字体下的 7.1px 横向溢出，并新增 `status_pill_test.dart` 回归；`AppRuntime.bootstrap` 新增可选 `SyncProvider` 注入，使同步注入契约有测试覆盖。
- 架构整改阶段 F 已实现 schema v2 完整设置快照、旧偏好迁移、能力覆盖和请求期限校验；API Key 通过安全存储槽轮换，导入/导出排除端标识和凭据，恢复默认保留本地身份/凭据；设置页支持高级选项、差异预览与固定文本连接诊断。Markdown 增加 schema_version 与未知 frontmatter 往返保留，未来 schema/非法已知字段拒绝写入；Web 通过条件迁移工厂隔离 SQLite FFI。
- 阶段 F 定向测试 64/64 通过：设置/模型/请求流/Markdown/成果库等 10 个测试文件 59 项；AppRuntime 与 SQLite migration 两个测试文件 5 项。`flutter analyze` 零问题，修改的 27 个 Dart 文件格式检查零差异。
- 阶段 F 的 Web、Windows、Android release 构建及 Windows integration smoke 均通过；当前 `adb devices` 为空，Android AVD 冒烟未执行。未重跑 339 项全量套件；最近全量结果仍是阶段 E 的 339/339。
- 阶段 F 已新增[整改验收矩阵](docs/architecture/remediation-acceptance.md)和[升级/恢复说明](docs/architecture/upgrade-and-recovery.md)，逐项记录 F1–F12 证据与边界；真实云盘、通知、签名、真实用户数据升级、物理断电仍未验证。
- 已完成 2026-10-13 架构审查，按当前代码区分已复现问题、代码审阅风险和未完成能力；报告记录 12 项发现、文档冲突与建议验收。
- 架构整改阶段 A 已新增逐阶段执行方案与 ADR 0015/0016，明确可恢复文件提交、幂等动作、数据库/设置迁移、同步身份校验和版本绑定裁决；修正文档中的成果类型、SQLite 恢复范围、Key 复用、向量检索与静态站口径。
- CI、Release 和 PowerShell 验证入口统一固定 Flutter 3.47.6 / Dart 3.13.5；新增机器版本断言脚本；场景生成器 lint 已修复并保持日期字符串内容不变。
- 架构整改阶段 C 已增加 `.local-transactions` 暂存、恢复副本、提交日志、hash/revision 校验及启动恢复；成果写入由 OS 文件锁跨实例串行化。SQLite 动作账本保存幂等键/载荷 hash/提交状态，会话库保存请求状态和完整响应/工具参数；重启可重放完整响应，未完成网络请求转人工重试；processing 捕获转待整理。
- 架构整改阶段 D 已将同步写入改为 create-only/eTag 条件操作；远端 ID、类型、路径、canonical 状态和内容 hash 在写入前逐对象校验。冲突副本按远端 hash 去重并持久化本地 hash/eTag，首轮相同内容建立基线；两类裁决都校验用户所见版本，成果快照在同步后刷新。
- 索引库现为 `user_version=4`，包含绑定参数的标题/正文/标签子串查询列及本地撤销动作账本；会话库为 `user_version=2`，包含每会话权限快照。启动时以 `VACUUM INTO` 备份两库和非秘密配置并校验 hash，完成验证前失败则恢复快照。Web 仍使用预览级内存 adapter。
- 架构整改阶段 E 将生产组合根移入 `AppRuntime.bootstrap`，UI 通过 `AppScope` 获取五个模块并按当前页面监听；根应用只监听主题设置。领域实体和设置快照为纯 Dart，成果单项写入增量更新快照，知识页每页最多读取 50 个 Markdown 文件。测试版旧宿主移至 `app/test/support/`。
- SQLite 重建会报告逐文件错误，重复成果 ID 的文件不会被选为索引版本；设置页显式重建/扫描显示成功、失败数量和错误路径。关闭流程停止模型生成、等待消息/成果/设置写入后关闭本地 adapters。
- 已形成 `CONTEXT.md`、可执行方案、同步协议、模型接入和 14 条 ADR。
- 已完成知识捕获、日历提醒、AI/OCR 自动化调研。
- 已定义 RM 交接文档的固定结构和只追加变更记录。
- 已定义 Agent 强制阅读、任务收尾和 Git 提交流程。
- 2026-10-20：在 `AGENTS.md` 新增编码与测试约定，明确实现简化原则、增量验证默认策略、避免重复验证、测试目录和测试记录/清理规则。
- 已准备 `pre-commit`、`commit-msg`、`pre-push` 三层本地门禁。
- 已准备 hooks 幂等安装脚本和隔离测试脚本。
- 已创建 Flutter 客户端 `app/`，包含响应式桌面/移动布局和离线优先工作流。
- 已实现一个成果一个 Markdown 文件、固定 `id`、frontmatter、`+08:00` 时间戳和本地 SQLite 索引重建。
- 已实现文本捕获、相对日期规则、待办勾选、事项聚合、知识搜索、确认队列、冲突副本和 30 天墓碑。
- 已实现 `SyncProvider`、三项 hash 判定、远端丢失重传、冲突文件与同步总览。
- 已实现 OpenAI 兼容模型客户端、系统安全存储配置及模型不可用时的本地降级。
- 已实现 Android `ACTION_SEND` / `ACTION_PROCESS_TEXT` 分享接收桥。
- 已生成固定 200 条回归矩阵，手机 67 条、平板 67 条、桌面 66 条；四档大小各 50 条，五类需求各 40 条。
- 已增加三档前端/后端回归：解析、Markdown、SQLite、索引重建、同步上传/去重、页面切换、滚动和长文详情。
- 已安装 Visual Studio Build Tools 2022 与 Windows SDK，`flutter doctor` 的 Windows 工具链已通过。
- 已通过管理员 UAC 安装 Visual Studio ATL 组件，并成功构建 Windows release。
- 已增加 Windows 与 Android integration test：真实平台导航、滚动、长文和捕获流程。
- 已生成 100 条 Android UI 独立用例，覆盖 8 个页面、手机/平板、浅色/深色、1.0-1.5x 字体、纵向滚动、横向滑动、筛选、详情、主题切换、捕获和收件箱合并确认区。
- 已修复 Android 高字体日历溢出、编辑页横向溢出、平板键盘导航栏溢出、状态栏 SafeArea 和捕获提交流程。
- 已将设备侧测试改为保留真实分辨率、密度和像素比，只在测试中控制字体缩放；模拟器不会被厂商门禁误报为目标真机。
- 已将系统入口探针纳入设备验收脚本：校验 `ACTION_SEND` / `ACTION_PROCESS_TEXT` 分发包解析，显式投递短标记，自动操作系统 chooser 选择本应用，强制停止后重启复查，并为投递后与恢复后状态保存截图。
- 已修复 release APK 缺少 `android.permission.INTERNET` 的问题，并新增 manifest 回归测试，避免正式包无法调用云端模型。
- 已新增 20 个大型综合场景，每场景包含 1 个事项、2 个事件、1 个待办和 2 条知识，共 120 个自动记录载荷。
- 已适配 MagicOS `HwResolverActivity`：先点“更多”，选择本应用，再确认“仅此一次”。
- 已完成 DeepSeek 式多会话与上下文管理，新增 ADR 0010。
- 已实现 `ConversationStore`、`ChatRepository`、附件存储和 Android 图片分享载荷。
- 已实现流式模型客户端、停止生成、断流保留、失败重试和会话级上下文裁剪。
- 已实现高置信自动记录、低置信/敏感/歧义待整理回退和 10 分钟撤销。
- 已实现会话按首次非空文字或图片创建，冷启动不建会话，启动时清理无消息空会话；系统分享内容仍会创建并打开会话。
- 已将独立确认页并入收件箱，捕获确认和同步冲突共用同一入口，首页待确认数量同步计入冲突。
- 已新增 `DevicePreferences`、`ResultLibrary`、`CaptureWorkflow`、`ConversationWorkspace`、`SyncWorkspace` 和 `AppRuntime`，并为每个模块建立独立 contract 测试。
- 已将原 `AppController` 从约 1110 行降到约 427 行；Markdown/SQLite 写入、捕获确认、会话流和同步状态均委托模块。
- 已将日历视图、快速新建和对话页拆为小于约 350 行的组件文件，并新增 `architecture_test.dart` 拦截 UI 到存储、模块到 UI 的反向依赖。
- 已修复 Android 390x844 手机视口下关闭快速新建面板时的底部 52px 溢出。
- 已适配 C 盘空间迁移：`E:\DevTools` 承载 Flutter、Android SDK、Gradle、AVD 和 Anaconda，原先五个 C 盘路径保留 Junction；设备验收脚本增加 E 盘工具链回退，应用本机 `local.properties` 已改指 E 盘 Flutter/Android SDK。

### 验证

- 2026-10-18 v1.1.2 发布：Release 工作流 `39108705557` 全部步骤 success，耗时约 20 分钟（标签 `v1.1.2` 于 07:39 UTC 推送，07:59 完成）；GitHub Release 确认 `prerelease=true`、`draft=false`，四个资产存在：APK 64.40 MB、Windows 安装包 11.80 MB、便携 ZIP 14.10 MB、`SHA256SUMS.txt`。重新下载三个二进制资产后计算 SHA-256，与校验文件完全一致（APK `97ce79a8…bb4c0e`、安装包 `f629c0d3…eabe16`、便携包 `df5c3b81…8dfb`）。未连接真实云盘或真实模型 Key。
- 2026-10-18 v1.1.2 发布准备：`dart format --output=none --set-exit-if-changed lib test integration_test tool` 163 文件零变化；`dart analyze` 零问题；`flutter test --no-pub` 376/376 通过；`scripts/scan-public-release.ps1 -CurrentTreeOnly` 通过。`flutter build apk --release` 成功（64.4 MB，SHA-256 `F3E623C8A99406599215CB7B234372591D0558B7B47CF4A8DD7FBCC4C5423E3D`），`flutter build windows --release` 成功（EXE SHA-256 `E34881DF0B854836D16988007C58387F4E6C8B6D4D741873F9E6B8C52FDA0812`）；`aapt2` 确认 `versionCode=4`、`versionName=1.1.2`、minSdk 24、targetSdk 36、INTERNET 权限。本地构建与 CI 构建哈希不同，以 Release 资产与 `SHA256SUMS.txt` 为准。
- 2026-10-18 推送与 CI：`git push origin main` 输出 `ced0755..1927647 main -> main`，`git ls-remote` 与本地 HEAD 一致；GitHub Flutter CI 对 `1927647` 的结论为 success（上一提交 `ced0755` 的 Analyze 曾失败，本轮已通过）。推送前 `scripts/scan-public-release.ps1 -CurrentTreeOnly`、`git diff --check origin/main..HEAD` 通过。
- 2026-10-18 真实端到端矩阵：主机预跑（除持久化分类）94/94 通过、46 秒；Android 手机 AVD（Pixel 6，`aitext_honor_phone`，端口 5560）50/50 通过、8 分 10 秒；Android 平板 AVD（`aitext_galaxy_tab`，端口 5562，2560×1600）25/25 通过、4 分 27 秒；Windows 桌面（1440×900 逻辑视口）25/25 通过、3 分 11 秒。日志位于 `app/build/realistic-e2e/<时间戳>/`。
- 2026-10-18 主机回归：`dart format --output=none --set-exit-if-changed lib test integration_test tool` 163 文件零变化；`dart analyze` 零问题；`flutter test --no-pub` 376/376 通过。未执行 release 构建、真实模型 Key 或真实云盘联调。
- 2026-10-13：`flutter test --no-pub --reporter expanded` 294/294 通过；`flutter analyze` 失败，现有 `app/tool/generate_large_scenarios.dart:160` 有 1 条 `unnecessary_brace_in_string_interps` info lint，本轮未修复。临时故障探针修正被否定的坏 YAML 阻断假设后 7/7 符合观察：6 个行为问题复现、1 个坏文件静默排除行为确认。`git diff --check` 通过。未执行 release 构建、原生/AVD 验收、真实模型/云盘联调、磁盘故障注入或性能基准。
- 2026-10-13 架构整改阶段 A：Dart 格式检查 137 文件零变化；`flutter analyze` 无问题；`flutter test --no-pub --reporter expanded` 294/294 通过；7 个 PowerShell 验证脚本解析通过，本机 Flutter 3.47.6 / Dart 3.13.5 版本断言通过；`git diff --check` 通过。未执行 release 构建、原生/AVD、真实模型/云盘、磁盘故障注入或性能基准。
- 架构整改阶段 B：`dart format --output=none --set-exit-if-changed lib test integration_test tool` 140 文件零变化；`flutter analyze` 无问题；完整 `flutter test --no-pub --reporter expanded` 312/312 通过，覆盖请求策略、图片出网、终态/超时/取消、工具参数和重试。未执行 release 构建、原生/AVD 或真实模型联调。
- 架构整改阶段 C：Dart 格式检查 143 文件零变化，静态分析通过，全量主机回归 327/327 通过；新增真实临时文件/OS 锁、事务日志恢复、幂等账本、SQLite 两库备份和旧数据 migration 回滚测试。未执行 release、原生/AVD、真实用户数据升级或物理断电验收。
- 2026-10-09 在 `E:\DevTools` 迁移后重新执行：`flutter pub get` 成功；`dart format` 137 个 Dart 文件 0 变化；`flutter analyze` 无问题；完整主机回归 294/294 通过。
- 迁移后 `flutter build web --release`、`flutter build windows --release` 和 `flutter build apk --release` 全部通过；Windows integration smoke 通过；Android release APK 为 63.8 MB。
- 迁移后 APK SHA-256 为 `0BC340C2E979D1487B2EE9D978870636B4C2D2A0F28F34870C14F7526F3EB491`；Windows release EXE SHA-256 为 `C555EB7B8D58E2E4B05A0ACCCE6387FF12B4ACAB98F9FA038C91670B2BF4F54B`。
- 迁移后 `scripts/test-git-policy.ps1` 通过 9 项隔离测试，`scripts/scan-public-release.ps1 -CurrentTreeOnly` 通过；双 AVD 均已停止，`adb devices` 为空。
- `scripts/test-git-policy.ps1` 已通过 7 项隔离测试：合法原子提交、非法标题、未跟踪文件、未暂存修改、缺少 RM 交接更新、空交接章节和脏工作区推送拦截。
- 开发环境迁移后按用户要求未启动 Flutter、Android、AVD、构建或测试；已确认五个 C 盘 Junction 均指向 `E:\DevTools`，Flutter、ADB、模拟器和 Conda 可执行文件均存在，并完成 PowerShell 脚本语法解析检查。
- hooks 安装脚本已连续执行两次，`core.hooksPath` 和 `commit.template` 保持一致。
- 首个提交已通过 `pre-commit` 与 `commit-msg`，暂存区 `git diff --check` 无错误。
- 首个提交后工作区为空，`RM_HANDOFF.md` 已被跟踪，提交标题符合 Conventional Commits。
- `flutter analyze` 通过，无 warning、error 或 lint issue。
- 模块化升级后 `dart format` 检查 137 个 Dart 文件无变化，`flutter analyze` 无问题。
- 模块化升级后完整 `flutter test --reporter compact` 通过 294 项，覆盖架构依赖、模块 contract、现有 200/100 条矩阵和会话/捕获/同步流程。
- `flutter build web --release`、`flutter build windows --release` 和 `flutter build apk --release` 均通过；Android release APK 为 63.8 MB。
- Windows `integration_test/windows_smoke_test.dart -d windows` 通过。
- Android `integration_test/android_smoke_test.dart -d emulator-5554` 的 phone/tablet 两档通过。
- Android `integration_test/android_ui_100_test.dart -d emulator-5554` 修复后通过 100/100。
- `flutter test --reporter expanded` 通过 124 项测试，其中包含 200 条跨端矩阵和 100 条 Android UI 矩阵：解析、三档后端持久化与同步、三档前端、Android 字体/主题/导航/滚动/滑动/详情/捕获。
- `flutter build web --release` 成功。
- `flutter build apk --debug` 与 `flutter build apk --release` 成功；release APK 为 59.7 MB。
- release APK SHA-256：`773AA5749CDBFE26BE882C97A499D4854CB349B7CE13039E563B867E76DF1BA1`；Windows release EXE SHA-256：`005291CBBD5A3915A61CBFAEA9772581FA451EBAE581A6DBDD1464D549B91B53`。
- `aapt2 dump badging` 确认应用名为“个人 AI 收件箱”；manifest 已包含 `ACTION_SEND` 与 `ACTION_PROCESS_TEXT` 的 `text/plain` 过滤器。
- `apksigner verify` 通过 v2 签名校验；当前为 Flutter 模板 debug 证书，正式分发前必须换独立签名。
- 内置浏览器实测 1440x900、390x844、320x568：捕获、日历、同步自检、更多菜单可操作；修复 320px 下更多面板的 25px 溢出。
- `flutter doctor -v` 中 Android 与 Windows Visual Studio 工具链均通过。
- `flutter build windows --release` 成功生成 `personal_ai_inbox.exe`。
- `flutter test integration_test/windows_smoke_test.dart -d windows` 通过完整导航、长文滚动和捕获流程。
- `flutter test integration_test/android_smoke_test.dart -d emulator-5554` 在 Android 15 x86_64 模拟器上通过 phone/tablet 两档。
- `flutter test test/android_ui_100_cases_test.dart` 通过 100 条独立 Android UI 用例加 1 条矩阵完整性检查。
- `flutter test integration_test/android_ui_100_test.dart -d emulator-5554` 在 Android 15 模拟器上通过 100/100。
- `flutter analyze` 无问题；完整 `flutter test --reporter expanded` 通过 225 项。
- `scripts/verify-device-acceptance.ps1 -SkipPhysical` 通过 101 项，包含 100 条新设备验收用例和 1 条矩阵完整性检查。
- 系统探针已保存 12 张截图到 `app/build/device-acceptance/<profile>/<system_share|process_text|system_chooser>/`；`build/` 保持不进入 Git。
- 主验收脚本在无设备序列号时仍可执行主机 100 条；提供序列号后自动追加 release 系统探针，`-SkipSystemProbes` 可显式关闭。
- 虚拟脚本已验证 AVD 自动创建/复用、固定端口 5560/5562、顺序启动、完成后自动关闭；本次运行结束后两个专用 AVD 均已停止。
- `scripts/verify-app.ps1` 与 `scripts/verify-integration.ps1` 均已跑通。
- 浏览器 release 在 390x844 实测日历页，修复后的日格无溢出，控制台无错误。
- `flutter analyze` 无问题；完整 `flutter test -r compact` 231 项全部通过。
- 新增 AI 对话专项测试覆盖 SQLite 持久化、SSE 分片、工具调用解析、高置信自动创建、低置信待整理、撤销、跨会话隔离和冷启动留在首页。
- Android debug APK、release APK（约 63.4 MB，SHA-256 `C4CFC1B5079FD0B7D7483138ADD266A3702AD98399D9F0503647A07473C6C99D`）与 Web release 构建通过。
- 新增会话生命周期测试覆盖冷启动不建会话、临时页退出不留记录、首次发送只创建一个会话、分享内容建会话和启动清理空会话。
- 新增收件箱合并测试覆盖捕获确认、调整、忽略和同步冲突裁决。
- 真机 release 验证发现 DNS 被阻断，根因为主 manifest 缺少 `android.permission.INTERNET`；修复后 `aapt2 dump permissions` 确认权限存在，release APK SHA-256 为 `CAF39E61B1A4583EF0767FA5C1A7A9811F1B94041D74AC9B90A8317FC1265100`。
- 20 个大型场景主机矩阵通过 21/21；每个场景的两轮对话、6 个多工具调用、事件/待办时间、知识正文和 Markdown 重建均通过。
- 完整主机测试套件扩展到 253 项并全部通过。
- 已新增 `tool/export_large_scenario_vault.dart`，可把 20 个大型场景导出为 120 份 Markdown。
- 已新增中文根 README、MIT 许可证、安全策略、贡献指南、EditorConfig、Flutter CI 和公开发布扫描脚本。
- Flutter CI 固定使用 `ubuntu-24.04` 和 `actions/checkout@v5`，避免 runner 迁移与旧 Node runtime 提示。
- 已扩展 Git `pre-commit`：拦截环境文件、签名材料、本地 vault、构建产物、高置信密钥模式及未脱敏设备标识；隔离策略测试扩展到 9 项。
- 已新增 ADR 0011，确定 MIT 开源发布和干净公开历史策略；旧历史保留在本地 `archive/pre-open-source`。
- 已新增 `.github/workflows/release.yml`，`v*` 标签会校验版本和发行说明，执行分析、测试、Android/Windows 构建、APK 检查、安装器编译、安装/卸载冒烟验证和 Release 上传。
- 已新增 `app/windows/installer/personal_ai_inbox.iss`，固定 AppId、按用户安装到 LocalAppData，并包含中文安装界面、许可证、快捷方式和卸载。
- 已新增 `docs/releases/v1.0.0.md`、README 下载入口和 ADR 0012。
- GitHub Actions 首次运行暴露出 Markdown 往返测试依赖执行主机时区；已改为比较绝对时刻，保留 `+08:00` 序列化断言，使 CI 在 UTC 与 `Asia/Hong_Kong` 下一致。
- `dart format --output=none --set-exit-if-changed lib test integration_test tool` 通过，97 个文件格式一致。
- `flutter analyze` 通过，无 warning、error 或 lint issue。
- `flutter test --reporter expanded` 通过 253 项。
- `flutter build web --release`、`flutter build windows --release` 和 `flutter build apk --release` 均成功；Android release APK 约 63.4 MB。
- `scripts/test-git-policy.ps1` 通过 9 项隔离测试，新增高置信密钥和敏感凭据路径拦截。
- `scripts/scan-public-release.ps1 -CurrentTreeOnly` 在暂存公开树通过；工作树精确搜索确认不再包含已识别的设备序列号。
- GitHub Actions 在 Linux/UTC 环境完成格式、分析和 253 项测试并全部通过；首次时区断言失败已通过绝对时刻比较修正。
- 公开树使用全新单根提交，提交前工作区为空；GitHub 远程为 `https://github.com/YuanFangCH/personal-ai-inbox`。
- `actionlint v1.7.12` 检查发布工作流通过。
- 使用官方 Inno Setup 7.1.0 x64 和固定 SHA-256 实际编译安装器成功；静默安装、必需文件检查、静默卸载和便携 ZIP 展开检查均通过。
- 本机生成的 APK 为 `versionName=1.0.0`、`versionCode=1`、minSdk 24、targetSdk 36，并包含 `android.permission.INTERNET`；证书为 `CN=Android Debug`。
- `flutter analyze` 无问题，完整 `flutter test --reporter compact` 253 项通过。
- `scripts/scan-public-release.ps1` 通过，发布文档和脚本未包含凭据或未脱敏设备标识。
- 标签发布工作流 `37434034842` 在 Windows 2022 上全部通过，耗时约 15 分 39 秒；常规 Flutter CI 也通过。
- GitHub Release API 确认 `v1.0.0` 为预发布，Android APK、Windows 安装包、便携 ZIP 和 `SHA256SUMS.txt` 均存在；校验文件中的三项哈希与平台记录一致。
- `dart format --output=none --set-exit-if-changed lib test integration_test tool` 通过，104 个文件格式一致。
- `flutter analyze` 通过，无 warning、error 或 lint issue。
- 日历专项新增 10 项测试，覆盖基础重复投影、月末跳过、日期型/带时待办、默认月视图和五档模式、密度持久化、快速新建、1.5x 字体响应式布局。
- `flutter analyze` 无问题；完整 `flutter test --reporter compact` 通过 268 项，包含日历专项、会话生命周期、收件箱合并、100 条 Android UI、100 条设备验收和 200 条跨端矩阵。
- `flutter build web --release`、`flutter build windows --release` 和 `flutter build apk --release` 均成功；Android release APK 为 63.8 MB，SHA-256 `62AA2BB22AE5C800643464C1D6C2899D5CE3325DAC314AE4B52531C40769AAB4`；Windows release EXE SHA-256 `FFD9D0033F3CDBF31B6942A2A87A0DBE6D8C4765A49216651A6B84FE08B8E386`。
- `flutter test integration_test/windows_smoke_test.dart -d windows` 通过；Windows 原生导航、滚动、长文和捕获流程无异常。
- 在真实浏览器尺寸复核手机宽度和 1280x800 桌面布局：五档模式栏、月视图、年视图、周时间轴、日程列表、我的一天、待办和快速新建面板均显示正常，未发现文字重叠或控件溢出。
- `main` Flutter CI `37501730835` 在 Linux/UTC 环境通过格式、静态分析和 268 项测试。
- `v1.1.0` Release 工作流 `37501751529` 在 Windows runner 用时 15 分 5 秒全部通过，完成标签校验、测试、Android/Windows release 构建、APK 元数据与 Debug 证书校验、Inno Setup 编译、安装/卸载冒烟、便携 ZIP 校验和 Release 上传。
- GitHub Release `v1.1.0` 已确认是预发布且非草稿，包含 `personal-ai-inbox-v1.1.0-android.apk`、Windows x64 安装包、便携 ZIP 和 `SHA256SUMS.txt`；重新下载三个资产后计算 SHA-256，三项均与校验文件一致。
- `v1.1.1` 首次 Release 运行 `37952267393` 在 `subosito/flutter-action` 下载 Flutter `3.47.7` 时因缓存未命中且连接中断失败，退出码 56；未进入代码验证或构建步骤。
- `v1.1.1` 重跑 Release 工作流 `37952267393` 在 15 分 52 秒内全部通过，完成标签校验、格式、静态分析、294 项主机回归、Android/Windows release 构建、APK 元数据与 Debug 证书校验、Inno Setup 编译、安装/卸载冒烟、便携 ZIP 校验和 Release 上传。
- GitHub Release `v1.1.1` 已确认是预发布且非草稿，包含 `personal-ai-inbox-v1.1.1-android.apk`、Windows x64 安装包、便携 ZIP 和 `SHA256SUMS.txt`；重新下载三个资产后 SHA-256 分别为 `b2dca07b2353e7ea39222f31dd98605df07d4d6311ceb6cd1a134c112283e818`、`110b14c9ddba05f997465831d8a67d81691b94a4a03a36ca6b5b2c36712e2c26` 和 `1303051f796bd39f6d40f6e0b87ab59f3a96cbbe45fb081aa2909b8cbccce3b6`，均与校验文件一致。

## 7. 风险、阻塞与下一步

### 风险与边界

- S1 只持久化权限并让设置页管理新会话默认，当前模型请求/工具仍未强制权限，不能在此阶段称为安全权限闭环。S2–S12 和三端 100 例仍待继续。

- S2 建立了普通成果 CAS 更新/删除、可撤销前像和恢复账本；AI 尚未调用。全局知识用途标识与审批也尚未接入。模型工具对外前需在本地核心完成权限和审批检查。

- S2 只建立普通成果操作/撤销底座；AI 尚未调用它，全局知识用途标识与审批也尚未接入。工具暴露之前仍需在本地核心完成权限校验和全局知识审批门禁。

- 2026-10-20 用户要求的 100 例是修改后的新功能设备矩阵，不是旧 100 例通过记录或 376 项全量主机回归。新脚本/场景数据尚未创建；必须按 ID 核实实际执行、缺失/skip 与替身模式，不能只看进程退出码。真实云盘、真实语音及模型质量另有依赖，不以受控矩阵通过冒充真实服务交付。

- 2026-10-20 检索成本策略尚待实现；本地可以强制权限、范围、总轮次/结果量和去重，模型对必要性的语义判断需样例与运行观测，不能保证绝对不多查。缓存必须随成果/会话/权限/有效期变化失效，不能以提速为由省略审批和并发校验；未承诺费用或时延改善比例。

- 2026-10-20 全局知识产品选择已确认，ADR 0018 是普通成果直接操作的审批例外；使用 `knowledge` 成果专门范围，字段与迁移尚待实施。只同步已确认版本及确认删除的墓碑，候选不得上传；按需检索受读取开关控制，不自动注入。真实云盘仍未接入，不能将目标同步契约当作三端联调证据。

- 2026-10-20 原草案的权限分组、执行方式、操作对象、权限生效范围、页面进入、待处理入口、语音及联网范围均已由用户明确。ADR 0017 已取代相关旧边界；当前运行代码仍为旧实现，不能把目标契约描述为能力上线。文件格式、统一撤销窗口、语音技术来源与限额是实施建议，尚无真实服务联调证据。

- 2026-10-18 真实端到端矩阵使用脚本化 SSE 模型与内存同步通道，验证应用侧流程与持久化语义，不验证真实网关时延、限流、真实云盘或线上抽取准确率。
- 2026-10-18 持久化分类使用真实文件 vault；主机 `testWidgets` 的 fake async 不驱动真实文件 IO，因此该分类只在两条 Android 腿和 Windows 腿运行，主机用 recovery 分类覆盖冷启动语义。
- 2026-10-18 三端执行串行（避免双 AVD 争用 16 GB 内存），纯用例耗时约 16 分钟，不含 Android 首次构建与 AVD 启动；模拟器通过不等于真机通过，MagicOS/One UI 后台策略、通知、相机和第三方图片分享仍需真机证据。
- 2026-10-13 架构整改已收敛可执行方案、模型接入和同步协议中的五组口径冲突：成果字段统一为 `type`，正式范围不含向量/静态站，SQLite 按成果派生索引与独立捕获/会话/账本区分，Key 独立存储且可由用户手动复用。此项取代同日审查记录中“尚未更改既有决定”的状态说明。
- 2026-10-13 架构整改阶段 A–F 已完成并提交；阶段 F 只运行受影响的 64 项测试，不以阶段 E 的 339/339 冒充本阶段全量验证。
- 阶段 B 已修复并覆盖测试：图片关闭后旧附件不出网；未确认完整流不执行工具；缺失 `sensitive`、越界置信度和未知字段不会自动创建；重试保留用户消息；停止后生成状态释放。
- 阶段 A–E 均已完成阶段门槛；阶段 D 的 SQLite 冲突记录迁移、远端身份/hash 错配隔离、相同内容首轮基线、冲突去重、两类裁决收敛和裁决期间远端变更保留均已通过测试。历史冲突副本若没有可信 eTag/裁决记录会留在待处理队列，需先重新同步核对。
- 阶段 C 已以真实临时文件、合成旧数据库验证事务日志、两库备份/迁移回滚和完整响应恢复；未升级真实用户数据或执行物理断电演练。
- Markdown 写入现在由事务日志、恢复副本及文件锁协调；I/O 故障覆盖合成与真实临时文件，但未执行断电/真实用户目录升级演练。高级模型配置与能力覆盖仍待阶段 F。
- 当前状态纠正：本文件当前范围中的“Windows 原生运行验证尚未完成”已被后续验证取代；图片对话已实现，但不能据此宣称独立视觉 OCR 工作流已完成。“327 项测试通过”不能覆盖真实云盘或通知可靠性。
- Git hooks 可被 `--no-verify` 绕过，项目规则明确禁止该操作。
- `core.hooksPath` 是本地仓库配置，不随仓库内容自动传播；克隆后必须运行安装脚本。
- 公开仓库已提供 Flutter CI，但 Git hooks 和本地发布扫描仍可能被 `--no-verify` 绕过；推送时必须保留 hook 和人工审计。
- `archive/pre-open-source` 仅用于本机追溯，包含迁移前敏感测试信息，绝不可推送到 GitHub 或复制给公开协作方。
- `v1.0.0` Android APK 使用 Debug 证书，Windows 安装包和 EXE 未进行代码签名；用户可能看到未知来源或 SmartScreen 提示，正式稳定版前必须完成独立签名。
- GitHub Release 仍由标签触发；重跑工作流时必须保持标签版本、`pubspec.yaml` 和 `docs/releases/<tag>.md` 一致。
- 2026-10-20 本轮仅修改 Agent 协作文档；按新增约定，文档变更默认无需运行测试，本轮未执行测试。
- Release 运行依赖 Flutter Action 的版本缓存；稳定通道升级后首次运行可能需要重新下载完整 SDK，本次 `3.47.7` 首次下载曾因连接中断失败，重跑后通过。
- 自动记录目前只授权高置信新建；模型更新、删除、重复规则和敏感内容不会自动执行。真实 Key 的联网流式与自动建成果仍未跑回归。
- 会话与图片只在本端保存；删除会话会删除本地消息和附件，但不会删除已创建的成果。
- 当前同步按钮运行的是端内沙箱 Provider，用于验证三 hash 与冲突逻辑，不等于 OneDrive 已联调。
- `AppController` 已从生产源码删除，测试专用 `TestAppHost` 留在 `app/test/support/`；页面不再导入存储、服务 facade 或 `AppController`。生产模块仍有部分 adapter 接口收敛工作，按阶段 F 复核 F1–F12 时记录边界。
- 知识页显式刷新会全量扫描 Markdown 并只写入变化的索引行；未做设备前台恢复后的自动重扫，用户可在设置页手动重建并查看路径诊断。
- 首版仅支持文本/分享文本捕获，截图视觉 OCR 链路尚未接入和回归。
- 20 个大型场景使用确定性模拟 SSE 和工具调用，验证应用侧多结果处理与持久化，不代表线上模型对 20 段原文的抽取准确率。
- Android release APK 使用 debug 签名，不能作为正式分发包。
- MagicOS/One UI 后台策略、通知、相机和第三方 App 图片分享必须单独采集真机证据。
- 当前应用尚未实现本地提醒通知，不能把 UI 矩阵通过写成通知验收通过。
- ADB `shell` 不是媒体 URI 所有者，无法为外部图片分享命令授予 MediaStore 读权限；第三方 App 图片分享仍需人工真机验收。
- 相机拍照入口尚未在模拟器执行完整拍照流程。
- `flutter doctor -v` 仍提示 Flutter/Dart 未进入当前 PATH、部分 Android licenses 未接受、Chrome 缺失和 Maven 网络检查超时；本轮通过绝对路径和已缓存依赖完成全部测试，后续应修正 PATH 与许可证告警，避免新终端或 CI 环境出现不可复现失败。
- 本次公开隐私清理只修改当前公开树；此前公开提交历史仍可能保留旧报告、设备指纹和生活化测试主题，若要求彻底清除历史对象，需要另行执行历史重写和强制推送。

### 下一步

当前优先：继续 S3 全局知识审批/用途标识，再做 S4 按需检索与 S5 工具编排权限门禁；已完成 S1/S2 不再重跑同范围验证。无需重问已确认产品选择；业务修改完成后执行 SEC-001–100 三端矩阵（50/25/25），保存逐例证据并对受影响例定向重跑。新增收费语音服务需呈现具体选择；受控 Provider 不能冒充真实云盘接入。以下为既有后续工作。

1. 发布前按发布门禁运行完整测试套件，并在三端执行 `scripts/verify-realistic-e2e.ps1`；矩阵已可重复运行，但每次约需 16 分钟纯用例时间。
2. 若转入生产用户数据，先执行升级与备份恢复演练；真实云盘、通知、签名和物理断电专项需另行验收。
3. 接入真实 OneDrive Provider 后，把 sync 分类从脚本通道切换为真实通道回归，并补齐令牌失效、限流与离线重试场景。
4. 后续代码任务按 `AGENTS.md` 的增量测试范围执行；测试结论记录执行范围与未验证项，临时测试仅在用户要求时清理。

## 8. 变更记录

### 2026-10-20 / 实现 S2 成果 CAS 操作与撤销账本

| 字段 | 内容 |
|---|---|
| 任务 | 为普通成果更新/删除加入稳定动作 ID 与 revision/hash CAS；保存本地前像和撤销状态，支持创建/改/删撤销、过期/版本变化拒绝、提交中断恢复；索引及启动迁移协调器升为 v4 |
| 变更文件 | `app/lib/core/models.dart`、`data/index_database.dart` 与 memory/SQLite adapters、`data/result_repository.dart`、`modules/results/result_library.dart`、`sqlite_migration_coordinator.dart`、repository/index/capture 测试、README、实施计划与 S2 测试记录 |
| 验证 | `flutter test test/result_repository_test.dart test/sqlite_index_database_test.dart test/sqlite_migration_coordinator_test.dart test/capture_workflow_test.dart --reporter compact`：28/28；相应文件 `dart analyze` 零问题；详细日志见 `test-results/secretary-s2-result-actions/verification.md` |
| 提交标题 | `feat(results): 增加成果CAS操作与可撤销账本` |
| 遗留事项 | AI 工具尚未连接；会话权限执行/全局知识审批仍待 S3/S5；未执行三端矩阵或全项目全量测试 |

### 2026-10-20 / 实现 S2 成果 CAS 操作与撤销账本

| 字段 | 内容 |
|---|---|
| 任务 | 为普通成果更新/删除建立稳定动作键与 revision/hash CAS；记录本地撤销前像、期限与状态，支持创建/改/删撤销、版本变化拒绝与提交中断恢复；SQLite 索引/coordinator 升为 v4 |
| 变更文件 | `app/lib/data/index_database.dart`、memory/SQLite adapters、`result_repository.dart`、`ResultLibrary` 操作接口、启动迁移 coordinator、repository/index/capture 测试、本文件和 `test-results/secretary-s2-result-actions/verification.md` |
| 验证 | `flutter test test/result_repository_test.dart test/sqlite_index_database_test.dart test/sqlite_migration_coordinator_test.dart test/capture_workflow_test.dart --reporter compact`：28/28；受影响文件 `dart analyze` 无问题；具体日志及边界见任务验证记录 |
| 提交标题 | `feat(results): 增加成果CAS操作与可撤销账本` |
| 遗留事项 | 模型工具尚未接线；全局知识确认例外和会话权限的统一调度门禁仍在 S3/S5；未跑新功能矩阵或全量回归 |

### 2026-10-20 / 实现 S1 会话权限默认值与数据迁移

| 字段 | 内容 |
|---|---|
| 任务 | 在设置快照和每个会话持久化读取/新增/修改删除权限；新会话复制当前默认，设置导入导出兼容旧值；迁移旧会话数据库并更新启动迁移版本门槛 |
| 变更文件 | `app/lib/core/models.dart`、`core/chat_models.dart`、settings/conversation stores、`sqlite_migration_coordinator.dart`、preferences/conversation modules、`AppRuntime`、设置页与测试；README、交接和 `test-results/secretary-s1-permission-snapshots/verification.md` |
| 验证 | `flutter test` 六个定向文件 27/27 通过：会话存储、SQLite 迁移协调、设置服务、DevicePreferences、ConversationWorkspace、SettingsPage；受影响文件 `dart analyze` 无问题，格式检查无变化；未跑全项目测试或设备矩阵 |
| 提交标题 | `feat(ai): 持久化会话权限与默认设置` |
| 遗留事项 | 模型工具编排尚未执行这些权限；普通成果改删、全局审批、按需检索、主要界面和三端 100 例在后续 S2–S12 |

### 2026-10-20 / 细化实施任务与三端 100 例验收

| 字段 | 内容 |
|---|---|
| 任务 | 将已确认改造拆为 S0–S12，列明依赖、产物、局部验证和完成标准；编制 SEC-001–100 新功能设备验收清单，用户确认手机/平板/Windows 合计 50/25/25 |
| 变更文件 | `docs/secretary-implementation-plan.md`、`docs/testing/secretary-100-case-plan.md`、原改造/补充/检索计划、`README.md`、`RM_HANDOFF.md`、`test-results/secretary-detailed-plan/verification.md` |
| 验证 | 现有脚本与 runner 只读核对；新清单数量、唯一 ID、分类/平台分布、链接与历史保留检查见任务验证记录；未启动模拟器、未运行测试或构建（计划阶段） |
| 提交标题 | `docs(plan): 细化秘书改造与三端百例验收` |
| 遗留事项 | 业务、新场景数据/runner 扩展和脚本待实施；100 例尚未执行，真实云盘/语音来源等外部依赖仍需落实 |

### 2026-10-20 / 增补非必要不检索与成本预算

| 字段 | 内容 |
|---|---|
| 任务 | 按用户要求收敛 AI 检索触发、最小来源与片段、统一预算、去重/有效结果复用、缓存失效及停止条件，避免为判断是否检索增加云端调用 |
| 变更文件 | `docs/ai-retrieval-policy.md`、原改造计划、秘书/全局知识计划、模型接入、`README.md`、`RM_HANDOFF.md`、任务验证记录 |
| 验证 | 人工核对与既有权限、同步、审批边界的一致性；文档链接、差异及历史保留检查见 `test-results/retrieval-constraints-plan/verification.md`；未运行测试或性能基准（仅文档） |
| 提交标题 | `docs(ai): 约束按需检索与调用预算` |
| 遗留事项 | 策略与预算尚待实现及定向验收；初始数值为建议，未测量时延/费用；未扩大联网范围 |

### 2026-10-20 / 确认全局知识共享读取与审批边界

| 字段 | 内容 |
|---|---|
| 任务 | 落实用户三项答复：全局知识随成果三端共享，按需检索受读取权限控制，新增/修改/删除均人工确认；补充同版本接收、候选与墓碑边界 |
| 变更文件 | `docs/secretary-and-global-knowledge-plan.md`、原改造计划、ADR 0018/0017 与索引、`CONTEXT.md`、模型接入、可执行方案、同步协议、`README.md`、`RM_HANDOFF.md`、任务验证记录 |
| 验证 | 文档与用户答复核对；链接、差异及历史保留检查见 `test-results/global-knowledge-confirmed/verification.md`；仅文档变更，未运行测试、构建或真实云盘请求 |
| 提交标题 | `docs(knowledge): 确认全局知识同步与审批边界` |
| 遗留事项 | 业务尚未实现；用途/确认字段、迁移、检索预算及日期计算为实施细节，真实云盘接入仍未完成 |

### 2026-10-20 / 追加秘书角色更名与确认式全局知识库

| 字段 | 内容 |
|---|---|
| 任务 | 将用户新增的秘书角色、懒狗秘书显示名和全局基础知识人工确认写入要求纳入计划，定位受影响提示词/品牌文件，区分已定需求与待答共享/读取/删除范围 |
| 变更文件 | `docs/secretary-and-global-knowledge-plan.md`、原改造计划、ADR 0018、ADR 0017 注记与索引、`CONTEXT.md`、模型接入、可执行方案、`README.md`、`RM_HANDOFF.md`、任务验证记录 |
| 验证 | 已核对用户最终指令与当前源码位置；文档链接、差异与历史记录检查见 `test-results/secretary-global-knowledge-plan/verification.md`；未执行业务测试或构建（仅文档） |
| 提交标题 | `docs(secretary): 规划角色更名与全局知识确认` |
| 遗留事项 | 全局知识共享、读取权限与删除确认三项待答；未选择 schema 或同步范围，未修改运行代码 |

### 2026-10-20 / 确认 AI 会话权限与扩展交互计划

| 字段 | 内容 |
|---|---|
| 任务 | 落实用户两轮产品答复，锁定三组会话权限、可撤销成果操作、每次进入新对话、独立待处理页、语音与联网范围，补充实施阶段和技术核实边界 |
| 变更文件 | `docs/ai-conversation-redesign-plan.md`、ADR 0017、ADR 索引及 0010/0013 注记、`CONTEXT.md`、可执行方案、模型接入、`README.md`、`RM_HANDOFF.md`、`test-results/ai-conversation-redesign-confirmed/verification.md` |
| 验证 | 用户答复与文档契约人工核对；DeepSeek 官方接口文档只读核实；文档本地链接与 `git diff --check` 检查；未执行运行测试、构建或真实模型请求（仅文档变更），详情见任务验证记录 |
| 提交标题 | `docs(chat): 确认会话权限与扩展交互计划` |
| 遗留事项 | 业务尚未实现；语音来源、文件解析依赖及限额、统一撤销窗口需实施前核实；不另接搜索服务 |

### 2026-10-20 / 整理 AI 对话界面与权限改造草案

| 字段 | 内容 |
|---|---|
| 任务 | 读取项目权威文档、核对用户提供的五张 DeepSeek 手机端截图及现有会话源码，整理界面、权限与工具链路草案，并提出六项需求问题 |
| 变更文件 | `docs/ai-conversation-redesign-plan.md`、`README.md`、`RM_HANDOFF.md`、`test-results/ai-conversation-redesign-plan/verification.md` |
| 验证 | 文档与源码对应关系人工核对；`git diff --check` 通过；未执行测试、构建或真实模型请求（仅规划文档变更）；详情见任务验证记录 |
| 提交标题 | `docs(chat): 记录对话界面与权限改造草案` |
| 遗留事项 | 六项需求待用户答复；未新增或替代已接受 ADR，未开始业务实现 |

### 2026-10-20 / 增补编码与测试约定

| 字段 | 内容 |
|---|---|
| 任务 | 在 Agent 协作规范中加入实现原则、最小必要验证、避免重复验证、测试目录约定及测试记录与清理规则 |
| 变更文件 | `AGENTS.md`、`RM_HANDOFF.md` |
| 验证 | 文档结构与变更内容人工检查通过；未运行测试（仅文档变更，按新约定默认无需测试） |
| 提交标题 | `docs(agents): add coding and testing conventions` |
| 遗留事项 | 无 |

### 2026-10-18 / 记录 v1.1.2 发布结果

| 字段 | 内容 |
|---|---|
| 任务 | 推送 `main` 与 `v1.1.2` 标签，执行 GitHub Release 工作流，发布 Android APK、Windows 安装包、便携 ZIP 和校验文件 |
| 变更文件 | `RM_HANDOFF.md` |
| 验证 | Release 工作流 `39108705557` 全部步骤 success，耗时约 20 分钟；标签 `v1.1.2` 指向发布准备提交 `1b27ef7`；Release 为非草稿预发布且四个资产存在；重新下载三个二进制资产后 SHA-256 与 `SHA256SUMS.txt` 全部一致 |
| 提交标题 | `docs: 记录 v1.1.2 发布结果` |
| 遗留事项 | 仍为 Android Debug 证书和未签名 Windows 包；真实云盘、通知与真机后台策略未验收 |

### 2026-10-18 / 准备发布 v1.1.2 预发布

| 字段 | 内容 |
|---|---|
| 任务 | 将版本提升到 `1.1.2+4`，编写发行说明与下载入口，准备通过 `v1.1.2` 标签触发三端 Release |
| 变更文件 | `app/pubspec.yaml`、`docs/releases/v1.1.2.md`、`README.md`、`RM_HANDOFF.md` |
| 验证 | 格式 163 文件零变化；`dart analyze` 零问题；主机 376/376；公开发布扫描通过；Android release APK 64.4 MB（versionName 1.1.2 / versionCode 4 / minSdk 24 / targetSdk 36 / INTERNET）与 Windows release 构建成功并记录 SHA-256；未执行安装器编译、AVD 冒烟或真实模型联调 |
| 提交标题 | `build(release): 准备 v1.1.2 预发布` |
| 遗留事项 | 需要推送 `main`、创建 `v1.1.2` 标签并核验 GitHub Release 资产 |

### 2026-10-18 / 推送整改提交并新增 100 条真实端到端矩阵

| 字段 | 内容 |
|---|---|
| 任务 | 将 `main` 的 7 个架构整改提交推送到 `origin/main`；新增 100 条多步骤真实场景，在手机 AVD、平板 AVD 和 Windows 桌面执行；修复矩阵发现的布局缺陷并补回归 |
| 变更文件 | `app/lib/ui/widgets/common.dart`、`app/lib/bootstrap/app_runtime.dart`、`app/test/app_runtime_test.dart`、`app/test/status_pill_test.dart`、`app/test/e2e/**`、`app/integration_test/realistic_100_android_test.dart`、`app/integration_test/realistic_100_windows_test.dart`、`app/tool/generate_realistic_scenarios.dart`、`scripts/verify-realistic-e2e.ps1`、`docs/architecture/realistic-e2e-matrix.md`、`RM_HANDOFF.md` |
| 验证 | 推送：`ced0755..1927647` 快进，CI `1927647` success；矩阵：手机 50/50（8m10s）、平板 25/25（4m27s）、Windows 25/25（3m11s），主机预跑 94/94；回归：格式 163 文件零变化、`dart analyze` 零问题、主机 376/376；`git diff --check` 通过。未执行 release 构建、真实 Key 或真实云盘联调 |
| 推送记录 | 2026-10-18：本提交 `d59c932` 已推送（`1927647..d59c932`），GitHub Flutter CI 运行 `39107906024` 在 Ubuntu 上格式、分析、测试三步全部 success；远端 `main` 与本地一致，工作区干净 |
| 提交标题 | `test(e2e): 增加 100 条真实场景三端矩阵` |
| 遗留事项 | 矩阵使用脚本化模型与同步通道；持久化分类仅在设备/桌面腿运行；真机后台策略、通知与真实云盘仍待验收 |

### 2026-10-13 / 执行阶段 F 高级配置与整改验收

| 字段 | 内容 |
|---|---|
| 任务 | 完成版本化设置快照、旧配置迁移、能力覆盖、请求超时/上下文约束、安全 Key 槽轮换、便携设置导入导出、默认值恢复和主动连接诊断；补全 Markdown schema 前向兼容与 Web 条件迁移边界；收敛 F1–F12 验收及升级恢复说明 |
| 变更文件 | `app/lib/core/models.dart`、`data/settings_service.dart`、`device_preferences.dart`、模型请求/连接服务、设置页、Markdown codec、成果库、条件迁移 coordinator、相关定向测试、`README.md`、`docs/model-integration.md`、`docs/architecture/maintainability-upgrade-plan.md`、`docs/architecture/remediation-acceptance.md`、`docs/architecture/upgrade-and-recovery.md`、`RM_HANDOFF.md` |
| 验证 | Flutter 3.47.6 / Dart 3.13.5；定向测试两组分别 59/59、5/5；`flutter analyze` 零问题；修改的 27 个 Dart 文件格式检查零变化；Web、Windows、Android release 构建通过，Windows integration smoke 通过；`git diff --check` 通过。未重跑全量测试；当前 adb 无设备，Android AVD smoke 未运行 |
| 提交标题 | `feat(settings): 增加高级配置并完成架构整改验收` |
| 遗留事项 | 完整主机套件留到发布阶段；真实 Key、真实云盘、通知、真实用户数据升级、物理断电和 Android AVD 本轮未验收；Web 仍为预览级内存存储 |

### 2026-10-13 / 执行阶段 E 模块迁移与增量成果查询

| 字段 | 内容 |
|---|---|
| 任务 | 将生产装配/启动恢复迁入 `AppRuntime`；生产移除 `AppController`，页面通过五个模块按需订阅；将 UI 标签/图标和 Flutter 主题类型移出领域模型；SQLite 索引升级到 v3，提供绑定参数的 50 项知识分页；成果单项操作增量更新快照；重建索引返回逐路径诊断并拒绝重复 ID；异步关闭等待生成和待写入操作 |
| 变更文件 | `app/lib/bootstrap/app_runtime.dart`、`core/models.dart`、成果库与 SQLite adapters、模块/页面及 `AppScope`、`main.dart`、测试专用 `app/test/support/test_app_host.dart`、架构/迁移/读取次数测试、`RM_HANDOFF.md`、阶段计划 |
| 验证 | Flutter 3.47.6 / Dart 3.13.5；`dart format --output=none --set-exit-if-changed app/lib app/test app/integration_test app/tool` 146 文件零变化；`flutter analyze` 零问题；完整主机回归 339/339 通过；10k 条知识查询只读取当页 50 个 Markdown 文件，单项编辑少于 10 次文件读取；架构负例、旧库 migration、AppRuntime 内存启动/关闭和 100 条 Android UI 矩阵通过；`git diff --check` 通过。未执行 release、原生/AVD integration smoke 或升级恢复演练 |
| 提交标题 | `refactor(app): 完成模块迁移与增量成果查询` |
| 遗留事项 | 前台自动重扫未接入，设置页提供显式重建和诊断；三端 release、原生/AVD、真实用户数据升级及阶段 F 尚待执行 |

### 2026-10-13 / 执行阶段 D 同步身份校验与冲突裁决

| 字段 | 内容 |
|---|---|
| 任务 | 增加 create-only/eTag 条件写入；校验远端成果身份和 hash；将远端导入及基线保存放入成果仓库事务；持久化去重冲突记录并绑定裁决所见版本；同步/裁决后刷新成果快照 |
| 变更文件 | `app/lib/data/sync_provider.dart`、`sync_engine.dart`、`result_repository.dart`、`index_database.dart`、SQLite/内存 adapter、`SyncWorkspace`、冲突与迁移回归、阶段计划、`RM_HANDOFF.md` |
| 验证 | Flutter 3.47.6 / Dart 3.13.5；`dart format --output=none --set-exit-if-changed lib test integration_test tool` 143 文件零变化；`flutter analyze` 零问题；完整主机测试 332/332 通过；同步、裁决和 SQLite migration 定向测试通过；`git diff --check` 通过。未执行三端 release、原生/AVD、真实云盘或断电专项验证 |
| 提交标题 | `fix(sync): 校验远端身份并使冲突裁决收敛` |
| 遗留事项 | 旧冲突副本没有可信 eTag 时要求重新同步核对；阶段 E–F 尚待实施，真实云盘/通知保持未验收 |

### 2026-10-13 / 执行阶段 C 可恢复存储与迁移恢复

| 字段 | 内容 |
|---|---|
| 任务 | 引入 SQLite version 与操作账本、模型完整响应生成记录；实现成果事务日志/暂存/恢复副本、revision 校验、跨实例 OS 文件锁；实现双库备份、hash 校验、schema migration 与失败回滚 |
| 变更文件 | `app/lib/data/result_repository.dart`、SQLite/ConversationStore 与迁移 adapter、`app/lib/data/sqlite_migration_coordinator.dart`、`app/lib/services/app_controller.dart`、捕获/对话/成果模块、故障及迁移回归、阶段计划、`RM_HANDOFF.md` |
| 验证 | `dart format --output=none --set-exit-if-changed lib test integration_test tool` 143 文件零变化；`flutter analyze` 通过；完整主机回归 327/327 通过；另有真实临时文件提交失败恢复、索引失败、OS 写锁、生成响应重放、两库升级/回滚验证 |
| 提交标题 | `fix(storage): 增加可恢复写入迁移与动作幂等` |
| 遗留事项 | 未执行三端 release、原生/AVD、真实用户目录升级和物理断电演练；阶段 D–F 尚未实施 |

### 2026-10-13 / 执行阶段 B 模型请求与自动记录整改

| 字段 | 内容 |
|---|---|
| 任务 | 新增纯请求策略及保守模型能力；执行图片出网开关；明确 SSE 终态和响应期限；严格校验自动记录；修复停止及保留用户消息的重试 |
| 变更文件 | `app/lib/services/model_capabilities.dart`、`model_request_policy.dart`、`model_client.dart`、`chat_service.dart`、`capture_service.dart`、`app/lib/modules/conversation/*`、对话 UI、相关测试、阶段计划、`RM_HANDOFF.md` |
| 验证 | Dart 格式 140 文件零变化；`flutter analyze` 无问题；完整主机回归 312/312 通过，覆盖图片策略、模型终态/超时/取消、参数校验、失败重试和页面发送 |
| 提交标题 | `fix(model): 执行图片策略并严格校验自动记录` |
| 遗留事项 | 阶段 C–F 尚未实施；真实模型与云服务联调未执行 |

### 2026-10-13 / 建立架构整改执行基线

| 字段 | 内容 |
|---|---|
| 任务 | 固化 F1–F12 的分阶段行动计划；统一成果与恢复语义；记录可恢复写入/幂等动作及同步裁决 ADR；固定 Flutter 与 Dart 工具链 |
| 变更文件 | `docs/architecture/maintainability-upgrade-plan.md`、`docs/adr/0015-recoverable-local-commits-and-idempotent-actions.md`、`docs/adr/0016-sync-validation-and-version-bound-conflict-decisions.md`、ADR 索引、同步协议、可执行方案、模型接入、CI/Release、版本断言及验证脚本、场景生成器、`RM_HANDOFF.md` |
| 验证 | Dart 格式 137 文件零变化；`flutter analyze` 通过；主机测试 294/294；7 个 PowerShell 脚本语法解析通过；Flutter 3.47.6 / Dart 3.13.5 断言通过；`git diff --check` 通过 |
| 提交标题 | `chore(architecture): 固定整改基线与恢复契约` |
| 遗留事项 | 阶段 B–F 尚未实施；未运行三端 release 构建、原生/AVD、真实云服务、故障注入或性能基准 |

### 2026-10-13 / 审查可维护性、可靠性与可配置性

| 字段 | 内容 |
|---|---|
| 任务 | 检查当前项目与架构，形成基于代码和故障探针的审查结论，区分已复现问题、代码审阅风险及尚未完成能力 |
| 变更文件 | `docs/architecture/architecture-audit-2026-10-13.md`、`RM_HANDOFF.md` |
| 验证 | 主机回归 294/294 通过；静态分析失败（1 条现有 info lint）；临时探针最终 7/7 符合观察，首次坏 YAML 阻断假设被否定后修正；`git diff --check` 通过；未执行构建、原生/AVD、真实模型/云盘、磁盘故障或性能验收 |
| 提交标题 | `docs(architecture): 审查维护性可靠性与可配置性` |
| 遗留事项 | 本轮不修复运行代码；图片策略、流完成/结构校验、可靠文件写入、同步身份/冲突收敛、快照刷新等仍待修复，文档口径冲突待按权威来源收敛 |

### 2026-10-10 / 清理公开设备指纹、个人披露与测试主题

| 字段 | 内容 |
|---|---|
| 任务 | 删除公开测试报告和截图，移除个人设备披露与具体设备型号，改用通用 Android 手机/平板 profile，并将回归 fixture 改为无个人语义的合成占位主题 |
| 变更文件 | `README.md`、`RM_HANDOFF.md`、`docs/device-acceptance-test-system.md`、`docs/personal-ai-inbox-executable-plan.md`、`docs/research/02-calendar-reminders.md`、`docs/research/03-ai-automation-ocr.md`、`app/tool/generate_large_scenarios.dart`、`app/tool/generate_regression_cases.dart`、`app/tool/generate_device_acceptance_cases.dart`、相关 fixture/generated 文件、验收脚本和公开测试证据目录 |
| 验证 | 待提交前执行 fixture 生成、定向测试、公开发布扫描、敏感词检索、`git diff --check`、Git hooks 和推送后远程复核；未执行完整 Flutter 构建 |
| 提交标题 | 待提交 |
| 遗留事项 | 当前提交不会自动抹除 GitHub 旧提交中的历史对象；如需彻底清除旧历史，必须另行确认历史重写与强制推送 |

### 2026-10-09 / 发布 v1.1.1 预发布版

| 字段 | 内容 |
|---|---|
| 任务 | 推送 `main` 与 `v1.1.1` 标签，执行 GitHub Release 工作流，发布 Android APK、Windows 安装包、便携 ZIP 和校验文件 |
| 变更文件 | `RM_HANDOFF.md` |
| 验证 | Release 工作流 `37952267393` 最终成功，耗时 15 分 52 秒；预发布标签 `v1.1.1` 指向发布准备提交；Release 为非草稿预发布且四个资产存在；重新下载三个二进制资产后 SHA-256 与 `SHA256SUMS.txt` 全部一致 |
| 提交标题 | `docs: 记录 v1.1.1 发布结果` |
| 遗留事项 | 仍为 Android Debug 证书和未签名 Windows 包；正式稳定版前需要独立签名与代码签名 |

### 2026-10-09 / 准备发布 v1.1.1 预发布版

| 字段 | 内容 |
|---|---|
| 任务 | 将模块化重构与 Android 布局修复形成的 `v1.1.1+3` 候选转为 GitHub 预发布版，更新发行说明、下载入口和交接状态，推送 `main` 后创建 `v1.1.1` 标签触发发布工作流 |
| 变更文件 | `app/test/chat_flow_test.dart`、`docs/releases/v1.1.1.md`、`README.md`、`RM_HANDOFF.md` |
| 验证 | Dart 格式检查 137 文件 0 变化；`flutter analyze` 无问题；修复 `chat_flow_test` 使用固定过去日期导致的时钟相关失败后，完整主机回归 294/294 通过；`scan-public-release.ps1 -CurrentTreeOnly` 通过；Release 工作流结果在发布完成后追加记录 |
| 提交标题 | `build(release): 准备 v1.1.1 预发布` |
| 遗留事项 | 需要推送 `main`、创建 `v1.1.1` 标签并核验 GitHub Release 资产 |

### 2026-10-09 / 完成 C 盘开发环境迁移后的完整验证

| 字段 | 内容 |
|---|---|
| 任务 | 在 `E:\DevTools` 迁移后重新验证 Flutter 工具链、全部主机回归、三端 release 构建、Windows 原生冒烟、双 AVD UI 与系统入口探针，以及仓库门禁 |
| 变更文件 | `RM_HANDOFF.md` |
| 提交标题 | `test(dev): 完成 C 盘迁移后完整验证` |

### 2026-10-07 / 适配 C 盘开发环境迁移

| 字段 | 内容 |
|---|---|
| 任务 | 适配 Flutter、Android SDK、Gradle、AVD 和 Anaconda 从 C 盘迁移到 `E:\DevTools`；保留 Junction 兼容，并让本仓库脚本和本机构建配置指向迁移后路径 |
| 变更文件 | 本机忽略文件 `app/android/local.properties`；`scripts/verify-device-acceptance.ps1`；`scripts/verify-virtual-device.ps1`；`RM_HANDOFF.md` |
| 验证 | 按用户要求未启动 Flutter、Android、AVD、构建或测试；确认 5 个 C 盘 Junction 指向 `E:\DevTools`，Flutter/ADB/emulator/Conda 可执行文件存在，PowerShell 脚本语法解析和 `git diff --check` 通过 |
| 提交标题 | `chore(dev): 适配 C 盘开发环境迁移` |
| 遗留事项 | 下次在继承新环境变量的终端中复跑至少一次 Flutter 分析和 Android 构建；若仍读取不到工具，重启 Codex Desktop 或终端 |

### 2026-10-07 / 完成维护性升级第一阶段与 v1.1.1 bugfix 候选

| 字段 | 内容 |
|---|---|
| 任务 | 按模块化本地核心方案拆分端配置、成果库、捕获、会话和同步逻辑；将 `AppController` 降为兼容 facade；拆分超长 UI；补架构和模块契约测试；修复 Android 快速新建面板底部溢出；形成 `v1.1.1+3` bugfix 候选 |
| 变更文件 | `app/lib/bootstrap/**`、`app/lib/domain/**`、`app/lib/modules/**`、`app/lib/services/app_controller.dart`、`app/lib/core/models.dart`、`app/lib/data/sync_engine.dart`、`app/lib/ui/pages/conversation_page.dart`、`app/lib/ui/pages/conversation/**`、`app/lib/ui/widgets/calendar_views.dart`、`app/lib/ui/widgets/calendar/**`、`app/lib/ui/widgets/quick_create_sheet.dart`、`app/lib/ui/widgets/quick_create/**`、新增模块/架构测试、ADR 0014、维护性升级方案、`docs/releases/v1.1.1.md`、`app/pubspec.yaml`、根 README、本文件 |
| 验证 | `dart format` 137 个 Dart 文件 0 变化；`flutter analyze` 无问题；完整主机测试 294/294 通过；Web、Windows、Android release 构建通过；Windows 原生冒烟通过；Android phone/tablet 冒烟通过；Android UI 100 条设备矩阵修复后 100/100 通过 |
| 提交标题 | `refactor(app): 模块化本地核心并修复Android布局溢出` |
| 遗留事项 | `AppController` 和页面 facade 尚未删除；模型/同步纯策略、schema migration、增量刷新和 FTS 仍在后续阶段；`v1.1.1` 尚未创建标签或 GitHub Release |

### 2026-10-07 / 发布 v1.1.0 预发布版

| 字段 | 内容 |
|---|---|
| 任务 | 推送 `main` 和 `v1.1.0` 标签，执行 Release 工作流，发布 Android APK、Windows 安装包、便携 ZIP 和校验文件 |
| 变更文件 | `RM_HANDOFF.md` |
| 验证 | `main` Flutter CI 通过；Release 工作流 15 分 5 秒全部成功；GitHub API 确认 `v1.1.0` 为预发布且非草稿；四个资产存在；重新下载三个二进制资产后 SHA-256 与 `SHA256SUMS.txt` 全部一致 |
| 提交标题 | `docs: 记录 v1.1.0 发布结果` |
| 遗留事项 | 仍为 Android Debug 证书和未签名 Windows 包；正式稳定版前需要独立签名与代码签名 |

### 2026-10-07 / 准备发布 v1.1.0

| 字段 | 内容 |
|---|---|
| 任务 | 将应用版本提升到 `1.1.0+2`，补充 `v1.1.0` 发行说明、下载入口与升级说明，准备通过标签触发三端 Release 构建 |
| 变更文件 | `app/pubspec.yaml`、Windows 安装器与资源版本、`docs/releases/v1.1.0.md`、根 README、本文件 |
| 验证 | 发布前格式、静态分析、完整主机回归和公开发布扫描通过；Release 资产与工作流结果在发布完成后追加记录 |
| 提交标题 | `build(release): 准备 v1.1.0 预发布` |
| 遗留事项 | 需要推送 `main`、创建 `v1.1.0` 标签并等待 GitHub Release 工作流完成 |

### 2026-10-07 / 扩展日历工作区并加入快速新建

| 字段 | 内容 |
|---|---|
| 任务 | 把日程、我的一天和待办合并到日历工作区；增加年/月/周/日/日程列表、详细/概要月视图、事件与待办共同投影、基础重复展开和事件/待办快速新建；移除重复的全局待办入口 |
| 变更文件 | `app/lib/core/calendar.dart`、`app/lib/ui/pages/calendar_page.dart`、`app/lib/ui/widgets/calendar_views.dart`、`app/lib/ui/widgets/quick_create_sheet.dart`、`app/lib/ui/widgets/todos_pane.dart`、`app/lib/ui/app_shell.dart`、`app/lib/ui/pages/home_page.dart`、设置与控制器、Android/Windows 集成测试、Android UI 与设备矩阵执行器、日历专项测试、`CONTEXT.md`、可执行方案、`app/README.md`、本文件 |
| 验证 | Dart 格式检查通过；`flutter analyze` 无问题；完整主机回归 268/268 通过；Web、Windows、Android release 构建通过；Windows 原生冒烟通过；Android 15 x86_64 AVD 手机/平板两档冒烟通过；Android UI 集成矩阵 100/100 通过；手机宽度与 1280x800 浏览器实测五档视图、三段切换和快速新建无溢出 |
| 提交标题 | `feat(app): 扩展日历工作区与快速新建` |

### 2026-10-07 / 合并确认收件箱并按首次内容创建会话

| 字段 | 内容 |
|---|---|
| 任务 | 冷启动直接进入首页；新对话改为首次发送文字或图片时才落库；清理历史空会话；删除独立确认页并把捕获确认、同步冲突、草稿和会话合并到收件箱 |
| 变更文件 | `app/lib/services/app_controller.dart`、`app/lib/data/chat_repository.dart`、`app/lib/ui/app_shell.dart`、`app/lib/ui/pages/conversation_page.dart`、`app/lib/ui/pages/inbox_page.dart`、`app/lib/ui/widgets/review_queue.dart`、Android/Windows 集成测试、Android UI 与双设备生成矩阵、会话生命周期与收件箱合并测试、ADR 0013、ADR 索引、ADR 0010 注记、术语表、可执行方案、模型接入、应用 README、设备验收说明、本文件 |
| 验证 | Dart 格式检查通过；`flutter analyze` 无问题；完整 `flutter test --reporter compact` 258 项通过；Web、Windows、Android release 构建通过；Windows 原生冒烟通过；本轮无在线 Android 设备，未执行 Android 模拟器/真机集成 |
| 提交标题 | `feat(app): 合并确认收件箱并按内容创建会话` |
| 遗留事项 | 需要在 Android 设备或 AVD 上复跑 100 条 UI、双设备验收和系统分享强停恢复探针 |

### 2026-10-06 / 发布 GitHub 首个预发布版 v1.0.0

| 字段 | 内容 |
|---|---|
| 任务 | 推送 `v1.0.0` 标签，执行 Release 工作流，发布 Android APK 和 Windows 11 x64 安装包、便携 ZIP、校验文件 |
| 变更文件 | `RM_HANDOFF.md` |
| 验证 | Release Actions 全部通过；Release 为 prerelease；四个资产存在；APK、安装包和便携 ZIP 的平台 SHA-256 摘要与 `SHA256SUMS.txt` 一致；常规 Flutter CI 通过 |
| 提交标题 | `docs: 记录 v1.0.0 首发结果` |
| 遗留事项 | 首发为 Debug 签名 APK 和未签名 Windows 包；后续稳定版需要独立签名和代码签名 |

### 2026-10-06 / 建立 GitHub 首个预发布版打包与自动上传流程

| 字段 | 内容 |
|---|---|
| 任务 | 为 `v1.0.0` 建立 Android APK、Windows 安装包、便携 ZIP 和校验文件的首发流程，并支持后续标签自动发布 |
| 变更文件 | `.github/workflows/release.yml`、`app/windows/installer/personal_ai_inbox.iss`、`docs/releases/v1.0.0.md`、ADR 0012、README、RM_HANDOFF.md |
| 验证 | `actionlint` 通过；Inno Setup 7.1.0 实际编译成功；安装、必需文件和卸载冒烟通过；便携 ZIP 展开检查通过；APK 元数据与 Debug 证书检查通过；`flutter analyze` 和 253 项测试通过；公开发布扫描通过 |
| 提交标题 | `build(release): 建立首个 GitHub 预发布流程` |
| 遗留事项 | 需要推送 `v1.0.0` 标签并确认 GitHub Actions 最终 Release；正式稳定版前仍需 Android 和 Windows 独立签名 |

### 2026-10-06 / 整理 MIT 开源发布与干净公开历史

| 字段 | 内容 |
|---|---|
| 任务 | 整理代码与文档，以 MIT 协议公开当前版本；补充中文 README、安全与贡献文档、CI 和密钥门禁，并剔除仓库中的凭据及设备标识 |
| 变更文件 | 根 README、LICENSE、SECURITY.md、CONTRIBUTING.md、.editorconfig、.github/workflows/flutter.yml、.gitignore、Git hooks、公开发布扫描、app README/pubspec、Dart 格式化结果、ADR 0011、ADR 索引、测试报告脱敏、RM_HANDOFF.md |
| 验证 | Dart 格式检查通过；`flutter analyze` 无问题；本机 `flutter test --reporter expanded` 253/253 通过；GitHub Actions Ubuntu 环境的格式、分析和 253 项测试通过；Web、Windows、Android release 构建通过；Git 策略测试 9/9 通过；公开树过滤扫描通过；设备序列号在当前树中精确检索无结果 |
| 提交标题 | `chore(repo): 整理 MIT 开源发布与干净历史` |
| 遗留事项 | 旧本地历史只保留在 `archive/pre-open-source`；产品侧 OneDrive、百度网盘、本地通知和独立签名仍待后续完成 |

### 2026-10-05 / 补充 100 条验收用例到人工检查数据

| 字段 | 内容 |
|---|---|
| 提交标题 | `test(app): 补充验收用例人工检查数据` |
| 遗留事项 | 人工检查完成后由用户决定是否清除 Key 和这些验收数据 |

### 2026-10-05 / 导出大型场景数据用于人工检查

| 字段 | 内容 |
|---|---|
| 提交标题 | `test(app): 支持大型场景人工检查数据导出` |


| 字段 | 内容 |
|---|---|
| 遗留事项 | MagicOS/One UI 后台策略、通知、相机和第三方 App 图片分享仍待验证 |

### 2026-10-05 / 建立 20 个大型综合场景测试

| 字段 | 内容 |
|---|---|
| 提交标题 | `test(app): 建立20个大型综合场景矩阵` |
| 遗留事项 | 该矩阵使用确定性模拟 SSE，不替代线上模型对 20 个场景的抽取准确率测试 |


| 字段 | 内容 |
|---|---|
| 提交标题 | `fix(android): 修复正式包联网并完成平板真机验收` |

### 2026-10-05 / 收件箱改造为 AI 多会话与自动记录

| 字段 | 内容 |
|---|---|
| 任务 | 学习 DeepSeek 式对话交互，把收件箱改成本地多会话 AI 记录，支持冷启动新会话、上下文隔离、文本/粘贴/图片输入、流式回复和高置信自动新增成果 |
| 变更文件 | `app/lib/core/chat_models.dart`、`app/lib/data/*conversation*`、`app/lib/data/*attachment*`、`app/lib/data/chat_repository.dart`、`app/lib/data/share_payload.dart`、`app/lib/services/chat_service.dart`、`app/lib/services/image_input_service.dart`、`app/lib/services/model_client.dart`、`app/lib/services/app_controller.dart`、`app/lib/ui/pages/inbox_page.dart`、`app/lib/ui/pages/conversation_page.dart`、`app/lib/ui/pages/settings_page.dart`、`app/lib/ui/app_shell.dart`、Android manifest/MainActivity、`app/pubspec.*`、新增专项测试、ADR 0010、模型接入/同步协议/可执行方案/CONTEXT/app README、本文件 |
| 提交标题 | `feat(app): 收件箱改造成 AI 多会话与自动记录` |


| 字段 | 内容 |
|---|---|
| 提交标题 | `test(android): 搭建双设备虚拟验收环境` |

### 2026-10-04 / 自动化设备分享与强停恢复探针

| 字段 | 内容 |
|---|---|
| 任务 | 补齐双设备验收中的系统分享面板、文本处理和进程重启持久化证据，并纳入主验收脚本 |
| 提交标题 | `test(android): 自动化设备系统分享与恢复探针` |


| 字段 | 内容 |
|---|---|

### 2026-10-04 / 建立 Android 100 条 UI 回归

| 字段 | 内容 |
|---|---|
| 任务 | 生成 100 条独立 Android UI 用例，测试手机/平板前端、字体、主题、按钮、滚动、滑动、详情和捕获体验，修复视觉与交互问题 |
| 验证 | `flutter analyze` 无问题；124 项主机测试通过；Android 15 模拟器 100/100 integration test 通过；Web、Windows release、Android release APK 构建通过 |
| 提交标题 | `test(android): 完成100条UI回归与体验修复` |

### 2026-10-04 / 补充 Windows 与 Android 原生集成测试

| 字段 | 内容 |
|---|---|
| 任务 | 完成 Windows 原生构建与运行验证，补齐 Android 手机/平板模拟器集成测试，并固化三端验证脚本 |
| 验证 | Windows release 构建成功；Windows integration test 通过；Android 15 x86_64 模拟器 phone/tablet integration test 通过；完整测试套件仍为 23 项通过 |
| 提交标题 | `test(app): 补充三端原生集成测试` |

### 2026-10-04 / 建立 200 条跨端回归矩阵

| 字段 | 内容 |
|---|---|
| 任务 | 生成 200 条不同设备、时段、事件、场景、需求和文本大小的测试例，测试手机、平板、桌面三档前端与后端并修复问题 |
| 验证 | 23 项 `flutter test` 全部通过；200 条解析矩阵通过；三档后端持久化、索引重建和同步通过；三档前端渲染与长文详情通过；`flutter analyze` 无问题；Web release 与 Android release APK 构建成功 |
| 提交标题 | `test(app): 建立200条跨端回归矩阵` |

### 2026-10-04 / 修复周内日期与中文口语时间

| 字段 | 内容 |
|---|---|
| 变更文件 | `app/lib/core/deterministic_parser.dart`、`app/test/deterministic_parser_test.dart`、`RM_HANDOFF.md` |
| 提交标题 | `fix(app): 补全周内日期与中文口语时间解析` |

### 2026-10-04 / 完成第一版本地收件箱客户端

| 字段 | 内容 |
|---|---|
| 任务 | 从零创建 Flutter 客户端，打通本地捕获、Markdown/SQLite、行动域与知识域、确认、同步判定、响应式界面和 Android 分享入口 |
| 变更文件 | `app/**`、`scripts/verify-app.ps1`、`RM_HANDOFF.md` |
| 验证 | `flutter analyze` 无问题；14 项 `flutter test` 通过；Web release、Android debug/release APK 构建成功；APK manifest 与签名校验通过；浏览器 1440/390/320 三档实测通过 |
| 提交标题 | `feat(app): 完成第一版本地收件箱客户端` |

### 2026-10-04 / 建立 RM 交接与 Git 强制提交

| 字段 | 内容 |
|---|---|
| 任务 | 初始化本地 Git 仓库，建立 RM 交接总文档、Agent 规则、hooks 和提交模板 |
| 变更文件 | `RM_HANDOFF.md`、`AGENTS.md`、`.gitattributes`、`.gitignore`、`.gitmessage`、`.githooks/*`、`scripts/install-git-hooks.ps1`、`scripts/test-git-policy.ps1` |
| 验证 | `scripts/test-git-policy.ps1` 的 7 项隔离测试全部通过；hooks 安装幂等；首个提交及提交后状态、diff 和跟踪检查通过 |
| 提交标题 | `chore: 建立项目交接与强制提交规范` |
| 遗留事项 | 后续根据实际开发任务持续维护本文件；目前未配置远程仓库 |

