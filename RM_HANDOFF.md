# RM 交接总文档

> 本文件是本项目唯一完整的 Agent 交接入口。顶部保存当前状态，底部只追加变更记录。

## 1. 文档状态

| 字段 | 当前值 |
|---|---|
| 项目名称 | 个人 AI 收件箱与提醒系统 |
| 最后更新时间 | 2026-10-10 |
| 时区 | Asia/Hong_Kong |
| 最后修改 Agent | Codex / GPT-5 |
| 当前阶段 | `v1.1.1+3` 已发布为 GitHub 预发布版，Release 工作流、发布资产与 SHA-256 校验均通过 |
| 总体状态 | `app/` 已形成可运行的 Flutter 客户端，本地核心拆分为端配置、成果库、捕获、会话和同步模块，`AppController` 降为迁移期兼容 facade；日历视图、快速新建和对话页已拆分。开发工具链已从 C 盘迁移到 `E:\DevTools`，迁移后 Dart 格式、`flutter analyze`、294 项主机回归、Web/Windows/Android release 构建、Windows 原生冒烟和双 AVD 验收均重新通过。`v1.1.1` 已是当前 GitHub 预发布版，发布 Android APK、Windows x64 安装包、便携 ZIP 和校验文件；公开树已移除设备指纹、个人设备披露、测试报告与生活化测试主题，APK 仍使用 Debug 证书，Windows 包仍未代码签名。产品边界继续保留：OneDrive、百度网盘、本地通知和真实跨端同步尚未完成。 |

## 2. 一句话交接

开发环境迁移后的完整测试已通过，三端可构建、双 AVD 验收通过，`v1.1.1` 预发布资产已完成上传与校验；公开树已清理设备指纹、个人披露和生活化测试主题。下一步迁移页面到模块快照、删除兼容 facade，再继续正式签名、通知和真实同步。

## 3. 当前目标与范围

### 目标

- 建立手机、平板、Windows 三端独立 App 的完整本地闭环。
- 以 Markdown 为权威存储，SQLite 只做索引、同步游标和幂等账本。
- 通过 OneDrive 交换定稿成果，通过百度网盘每日单向归档。
- 云端模型只生成结构化候选，不直接修改用户成果。

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
- OneDrive OAuth、百度网盘归档、Windows 原生运行验证和真实云端模型回归尚未完成。
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
- 模型不得绕过端内规则；ADR 0010 允许在完整流结束、结构校验通过、置信度不低于 `0.85` 且非敏感时自动新建成品，修改与删除永不自动执行。
- 图片在配置模型后默认允许出网；设置页提供默认开启的总开关，客户端自动缩放、重编码并去除 EXIF，但不自动遮蔽图片内容。

## 6. 当前进度与验证

### 已完成

- 已形成 `CONTEXT.md`、可执行方案、同步协议、模型接入和 14 条 ADR。
- 已完成知识捕获、日历提醒、AI/OCR 自动化调研。
- 已定义 RM 交接文档的固定结构和只追加变更记录。
- 已定义 Agent 强制阅读、任务收尾和 Git 提交流程。
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

- Git hooks 可被 `--no-verify` 绕过，项目规则明确禁止该操作。
- `core.hooksPath` 是本地仓库配置，不随仓库内容自动传播；克隆后必须运行安装脚本。
- 公开仓库已提供 Flutter CI，但 Git hooks 和本地发布扫描仍可能被 `--no-verify` 绕过；推送时必须保留 hook 和人工审计。
- `archive/pre-open-source` 仅用于本机追溯，包含迁移前敏感测试信息，绝不可推送到 GitHub 或复制给公开协作方。
- `v1.0.0` Android APK 使用 Debug 证书，Windows 安装包和 EXE 未进行代码签名；用户可能看到未知来源或 SmartScreen 提示，正式稳定版前必须完成独立签名。
- GitHub Release 仍由标签触发；重跑工作流时必须保持标签版本、`pubspec.yaml` 和 `docs/releases/<tag>.md` 一致。
- Release 运行依赖 Flutter Action 的版本缓存；稳定通道升级后首次运行可能需要重新下载完整 SDK，本次 `3.47.7` 首次下载曾因连接中断失败，重跑后通过。
- 自动记录目前只授权高置信新建；模型更新、删除、重复规则和敏感内容不会自动执行。真实 Key 的联网流式与自动建成果仍未跑回归。
- 会话与图片只在本端保存；删除会话会删除本地消息和附件，但不会删除已创建的成果。
- 当前同步按钮运行的是端内沙箱 Provider，用于验证三 hash 与冲突逻辑，不等于 OneDrive 已联调。
- `AppController` 仍作为迁移期兼容 facade 存在；后续不得向其中新增业务规则，页面迁移完成后必须删除。
- 维护性升级第一阶段的模块边界已由架构测试保护，但页面仍主要读取 facade，后续需要逐页切换到模块快照。
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

1. 后续公开开发直接在干净 `main` 上增量提交，禁止推送 `archive/pre-open-source`；新版本必须同步提升 `pubspec.yaml` 版本并新增 `docs/releases/v<version>.md`。
2. 配置 Android 独立签名和 Windows 代码签名，为后续稳定版准备正式证书。
3. 在两台设备上验证电池优化、自启动、后台冻结和本地通知恢复。
4. 登记 Microsoft public client，完成 OneDrive App Folder、delta、eTag 和 PKCE 联调。
6. 继续维护性升级第二阶段：页面改读模块快照、抽模型/同步纯策略、增加 schema migration 和增量刷新，最终删除 `AppController`。

## 8. 变更记录

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

