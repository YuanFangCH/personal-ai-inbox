# RM 交接总文档

> 本文件是本项目唯一完整的 Agent 交接入口。顶部保存当前状态，底部只追加变更记录。

## 1. 文档状态

| 字段 | 当前值 |
|---|---|
| 项目名称 | 懒狗秘书（新显示名已确认，运行版本仍使用个人 AI 收件箱） |
| 最后更新时间 | 2026-10-20 |
| 时区 | Asia/Hong_Kong |
| 最后修改 Agent | Codex |
| 当前阶段 | `v1.1.2` 已预发布；AI 对话、秘书角色、更名与全局知识库产品选择已确认，ADR 0017/0018、计划和同步目标边界已记录，尚未开始业务实现 |
| 总体状态 | `app/` 生产启动由 `AppRuntime` 装配端配置、成果库、捕获、会话和同步模块；页面直接订阅所属模块，`AppController` 已从生产源码删除。知识查询基于 SQLite v3 规范化索引按 50 项分页；Markdown 仍为成果权威副本。工具链固定 Flutter 3.47.6 / Dart 3.13.5。本轮为主机测试与三端模拟器/桌面验收，未连接真实云盘或真实模型 Key。`v1.1.2` GitHub 预发布版仍使用 Debug 证书，Windows 包未代码签名；OneDrive、百度网盘、通知和真实跨端同步尚未完成。 |

## 2. 一句话交接

2026-10-20 追加规划已确认：软件显示名“懒狗秘书”，AI 默认秘书型助理；全局知识使用已确认基础事实，随成果三端同步，AI 按需检索且受当前会话读取权限控制，新增/修改/删除均须人工确认。见 [ADR 0018](docs/adr/0018-confirmed-global-knowledge-for-secretary.md)、[补充计划](docs/secretary-and-global-knowledge-plan.md) 与同步协议第 17 节。原三个待答问题已收敛，普通成果仍按原权限直接操作；本轮仅规划，未开始业务实现。

2026-10-20 当前规划：两轮产品选择已确认，见 [ADR 0017](docs/adr/0017-conversation-permissions-and-reversible-result-actions.md) 和[改造计划](docs/ai-conversation-redesign-plan.md)。收件箱直接改为 AI 对话，每次进入显示新对话，侧边管理会话，待处理独立成页；三组权限为读取、新增、修改与删除，初始默认全开，各会话独立保存。AI 按用户要求直接改删成果并支持撤销，其他会话只读；语音转写和朗读、文件、深度思考纳入计划；联网仅用当前模型接口内置能力，不支持时禁用。不再将先前草案的六项问题视为待答；业务代码未改。


2026-10-13 补充：已完成[架构审查](docs/architecture/architecture-audit-2026-10-13.md)。架构方向合理，当前仍部分满足可维护性和基础可配置性，尚不满足高可靠性；本轮只形成审查与建议，没有修复运行代码，也未替代既有 ADR 或正式实施顺序。


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





- 2026-10-18：`v1.1.2` 预发布已发布：Release 工作流 `39108705557` 在 Windows 2022 上完成标签校验、格式、分析、376 项主机测试、Android/Windows release 构建、APK 元数据与 Debug 证书校验、Inno Setup 编译、安装/卸载冒烟、便携包校验和上传；Release 为非草稿预发布，含 APK、Windows 安装包、便携 ZIP 与 `SHA256SUMS.txt`。
- 2026-10-18：准备 `v1.1.2` 预发布：`app/pubspec.yaml` 升至 `1.1.2+4`，新增 [发行说明](docs/releases/v1.1.2.md)，更新 README 下载入口；本地 Android/Windows release 构建通过，APK `versionName=1.1.2`、`versionCode=4`、minSdk 24、targetSdk 36、含 INTERNET 权限。
- 2026-10-18：`main` 上 7 个架构整改提交已快进推送到 `origin/main`（`ced0755..1927647`），GitHub Flutter CI 运行 `1927647` 成功；未使用 `--no-verify` 或强推。
- 2026-10-18：矩阵修复了 `StatusPill` 在手机 1.15x 字体下的 7.1px 横向溢出，并新增 `status_pill_test.dart` 回归；`AppRuntime.bootstrap` 新增可选 `SyncProvider` 注入，使同步注入契约有测试覆盖。
- 架构整改阶段 F 已实现 schema v2 完整设置快照、旧偏好迁移、能力覆盖和请求期限校验；API Key 通过安全存储槽轮换，导入/导出排除端标识和凭据，恢复默认保留本地身份/凭据；设置页支持高级选项、差异预览与固定文本连接诊断。Markdown 增加 schema_version 与未知 frontmatter 往返保留，未来 schema/非法已知字段拒绝写入；Web 通过条件迁移工厂隔离 SQLite FFI。
- 阶段 F 的 Web、Windows、Android release 构建及 Windows integration smoke 均通过；当前 `adb devices` 为空，Android AVD 冒烟未执行。未重跑 339 项全量套件；最近全量结果仍是阶段 E 的 339/339。
- 阶段 F 已新增[整改验收矩阵](docs/architecture/remediation-acceptance.md)和[升级/恢复说明](docs/architecture/upgrade-and-recovery.md)，逐项记录 F1–F12 证据与边界；真实云盘、通知、签名、真实用户数据升级、物理断电仍未验证。
- 已完成 2026-10-13 架构审查，按当前代码区分已复现问题、代码审阅风险和未完成能力；报告记录 12 项发现、文档冲突与建议验收。
- 架构整改阶段 A 已新增逐阶段执行方案与 ADR 0015/0016，明确可恢复文件提交、幂等动作、数据库/设置迁移、同步身份校验和版本绑定裁决；修正文档中的成果类型、SQLite 恢复范围、Key 复用、向量检索与静态站口径。
- CI、Release 和 PowerShell 验证入口统一固定 Flutter 3.47.6 / Dart 3.13.5；新增机器版本断言脚本；场景生成器 lint 已修复并保持日期字符串内容不变。
- 架构整改阶段 C 已增加 `.local-transactions` 暂存、恢复副本、提交日志、hash/revision 校验及启动恢复；成果写入由 OS 文件锁跨实例串行化。SQLite 动作账本保存幂等键/载荷 hash/提交状态，会话库保存请求状态和完整响应/工具参数；重启可重放完整响应，未完成网络请求转人工重试；processing 捕获转待整理。
- 架构整改阶段 D 已将同步写入改为 create-only/eTag 条件操作；远端 ID、类型、路径、canonical 状态和内容 hash 在写入前逐对象校验。冲突副本按远端 hash 去重并持久化本地 hash/eTag，首轮相同内容建立基线；两类裁决都校验用户所见版本，成果快照在同步后刷新。
- 索引库现为 `user_version=3`，包含绑定参数的标题/正文/标签子串查询列；会话库为 `user_version=1`。启动时以 `VACUUM INTO` 备份两库和非秘密配置并校验 hash，完成验证前失败则恢复快照。Web 仍使用预览级内存 adapter。
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
- 2026-10-18 推送与 CI：`git push origin main` 输出 `ced0755..1927647 main -> main`，`git ls-remote` 与本地 HEAD 一致；GitHub Flutter CI 对 `1927647` 的结论为 success（上一提交 `ced0755` 的 Analyze 曾失败，本轮已通过）。推送前 `scripts/scan-public-release.ps1 -CurrentTreeOnly`、`git diff --check origin/main..HEAD` 通过。
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

当前优先：产品选择已收敛；用户明确开始实现后，按原计划 A–G 与[补充计划](docs/secretary-and-global-knowledge-plan.md) 的角色/更名/全局知识审批推进，先落实用途字段、版本迁移、统一审批检查和检索权限。无需重问已确认产品选择；技术选型需核实三端语音、文件解析和当前模型能力，若需要新增收费语音服务再呈现具体选择。以下为既有后续工作。

1. 发布前按发布门禁运行完整测试套件，并在三端执行 `scripts/verify-realistic-e2e.ps1`；矩阵已可重复运行，但每次约需 16 分钟纯用例时间。
2. 若转入生产用户数据，先执行升级与备份恢复演练；真实云盘、通知、签名和物理断电专项需另行验收。
3. 接入真实 OneDrive Provider 后，把 sync 分类从脚本通道切换为真实通道回归，并补齐令牌失效、限流与离线重试场景。
4. 后续代码任务按 `AGENTS.md` 的增量测试范围执行；测试结论记录执行范围与未验证项，临时测试仅在用户要求时清理。

