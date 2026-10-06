# RM 交接总文档

> 本文件是本项目唯一完整的 Agent 交接入口。顶部保存当前状态，底部只追加变更记录。

## 1. 文档状态

| 字段 | 当前值 |
|---|---|
| 项目名称 | 个人 AI 收件箱与提醒系统 |
| 最后更新时间 | 2026-10-07 |
| 时区 | Asia/Hong_Kong |
| 最后修改 Agent | Codex / GPT-5 |
| 当前阶段 | GitHub 预发布版 `v1.1.0` 已发布，Android、Windows 安装包和便携包资产可用 |

## 2. 一句话交接

项目已发布 GitHub 预发布版 `v1.1.0`，完成日历工作区、多视图、待办投影和快速新建。下一步是正式签名、厂商后台策略、通知和图片输入验证。

## 3. 当前目标与范围

### 目标

- 建立手机、平板、Windows 三端独立 App 的完整本地闭环。
- 以 Markdown 为权威存储，SQLite 只做索引、同步游标和幂等账本。
- 通过 OneDrive 交换定稿成果，通过百度网盘每日单向归档。
- 云端模型只生成结构化候选，不直接修改用户成果。

### 当前范围

- 当前客户端位于 [app](./app)。
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
- 模型不得绕过端内规则；ADR 0010 允许在完整流结束、结构校验通过、置信度不低于 `0.85` 且非敏感时自动新建成品，修改与删除永不自动执行。
- 图片在配置模型后默认允许出网；设置页提供默认开启的总开关，客户端自动缩放、重编码并去除 EXIF，但不自动遮蔽图片内容。

## 6. 当前进度与验证

### 已完成

- 已形成 `CONTEXT.md`、可执行方案、同步协议、模型接入和 13 条 ADR。
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
- 已建立荣耀手机与 Galaxy Tab 双设备验收体系，固定 100 条用例，每台 50 条，覆盖导航、字体、滚动、横向控件、筛选、详情、捕获、主题和主要按钮。
- 已增加设备身份门禁：荣耀配置要求 `manufacturer=HONOR` 且视口小于 600dp；Galaxy Tab 配置要求 `manufacturer=samsung`、型号 `SM-T73*` 且视口至少 600dp。
- 已将设备侧测试改为保留真实分辨率、密度和像素比，只在测试中控制字体缩放；模拟器不会被厂商门禁误报为目标真机。
- 已将系统入口探针纳入设备验收脚本：校验 `ACTION_SEND` / `ACTION_PROCESS_TEXT` 分发包解析，显式投递短标记，自动操作系统 chooser 选择本应用，强制停止后重启复查，并为投递后与恢复后状态保存截图。
- 已增加双 AVD 虚拟设备验收脚本，自动创建或复用 `aitext_honor_phone` 与 `aitext_galaxy_tab`，在固定端口顺序执行主机、UI 和系统入口探针，结束后自动关闭。
- 已在 Samsung Galaxy Tab S7 FE（`SM-T736B` / Android 14）真机完成 50 条 UI、三类系统入口和强停恢复验收。
- 已新增 20 个大型综合场景，每场景包含 1 个事项、2 个事件、1 个待办和 2 条知识，共 120 个自动记录载荷。
- 已适配 MagicOS `HwResolverActivity`：先点“更多”，选择本应用，再确认“仅此一次”。
- 已完成 DeepSeek 式多会话与上下文管理，新增 ADR 0010。
- 已实现 `ConversationStore`、`ChatRepository`、附件存储和 Android 图片分享载荷。
- 已实现流式模型客户端、停止生成、断流保留、失败重试和会话级上下文裁剪。
- 已实现高置信自动记录、低置信/敏感/歧义待整理回退和 10 分钟撤销。
- 已实现会话按首次非空文字或图片创建，冷启动不建会话，启动时清理无消息空会话；系统分享内容仍会创建并打开会话。
- 已将独立确认页并入收件箱，捕获确认和同步冲突共用同一入口，首页待确认数量同步计入冲突。

### 验证

- `scripts/test-git-policy.ps1` 已通过 7 项隔离测试：合法原子提交、非法标题、未跟踪文件、未暂存修改、缺少 RM 交接更新、空交接章节和脏工作区推送拦截。
- hooks 安装脚本已连续执行两次，`core.hooksPath` 和 `commit.template` 保持一致。
- 首个提交已通过 `pre-commit` 与 `commit-msg`，暂存区 `git diff --check` 无错误。
- 首个提交后工作区为空，`RM_HANDOFF.md` 已被跟踪，提交标题符合 Conventional Commits。
- `flutter analyze` 通过，无 warning、error 或 lint issue。
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
- 新真机入口在 Android 15 x86_64 模拟器上按荣耀实际视口 `1080x2400 / 420dpi` 通过 50/50，用例覆盖 `honor-phone` 配置。
- 同一真机入口临时按 `2560x1600 / 240dpi` 模拟平板视口，通过 Galaxy Tab 配置 50/50，执行后已恢复模拟器原始显示参数。
- 负向门禁验证通过：把 `manufacturer=google` 的模拟器作为 HONOR 设备提交时，脚本在任何设备测试前以厂商不匹配拒绝。
- 在 Android 15 模拟器 release APK 上完成系统入口探针 6/6：荣耀和平板配置各通过 `ACTION_SEND`、`ACTION_PROCESS_TEXT` 和系统 chooser 选择，标记在校验落盘后执行强制停止并重启仍可见。
- 系统探针已保存 12 张截图到 `app/build/device-acceptance/<profile>/<system_share|process_text|system_chooser>/`；`build/` 保持不进入 Git。
- 主验收脚本在无设备序列号时仍可执行主机 100 条；提供序列号后自动追加 release 系统探针，`-SkipSystemProbes` 可显式关闭。
- `scripts/verify-virtual-device.ps1` 完整执行通过：主机 100 条、`aitext_honor_phone` UI 50 条、`aitext_galaxy_tab` UI 50 条，两台 AVD 各 3 类系统入口与强停恢复全部通过。
- 虚拟脚本已验证 AVD 自动创建/复用、固定端口 5560/5562、顺序启动、完成后自动关闭；本次运行结束后两个专用 AVD 均已停止。
- `scripts/verify-app.ps1` 与 `scripts/verify-integration.ps1` 均已跑通。
- 浏览器 release 在 390x844 实测日历页，修复后的日格无溢出，控制台无错误。
- 使用一支临时测试 Key 验证 DeepSeek 端点：`/models` 返回 `deepseek-flash` 与 `deepseek-v4-pro`；`/chat/completions` 对“周五下午两点和客户开会”返回规范 JSON 事件。
- App 端到端模型测试生成 `2026-10-09 14:00` 事件，标题“与客户开会”，日期与时间在日历中可见；测试 Key 已从 App 安全存储清除。
- `flutter analyze` 无问题；完整 `flutter test -r compact` 231 项全部通过。
- 新增 AI 对话专项测试覆盖 SQLite 持久化、SSE 分片、工具调用解析、高置信自动创建、低置信待整理、撤销、跨会话隔离和冷启动留在首页。
- Android debug APK、release APK（约 63.4 MB，SHA-256 `C4CFC1B5079FD0B7D7483138ADD266A3702AD98399D9F0503647A07473C6C99D`）与 Web release 构建通过。
- 新增会话生命周期测试覆盖冷启动不建会话、临时页退出不留记录、首次发送只创建一个会话、分享内容建会话和启动清理空会话。
- 新增收件箱合并测试覆盖捕获确认、调整、忽略和同步冲突裁决。
- Galaxy Tab S7 FE 真机识别通过：Samsung `SM-T736B`、Android 14/API 34、1600x2560/340dpi、逻辑宽度约 753dp；未执行清除数据、刷机或重启。
- 真机 release 验证发现 DNS 被阻断，根因为主 manifest 缺少 `android.permission.INTERNET`；修复后 `aapt2 dump permissions` 确认权限存在，release APK SHA-256 为 `CAF39E61B1A4583EF0767FA5C1A7A9811F1B94041D74AC9B90A8317FC1265100`。
- Galaxy Tab 真机真实模型端到端通过：输入“明天下午三点和客户开会”，自动创建“与客户开会”事件，开始时间 `2026-10-06 15:00`，标签“会议、客户”；测试 Key 已在验证后从平板安全存储清除。
- HONOR 90 的 `ACTION_SEND`、`ACTION_PROCESS_TEXT`、MagicOS chooser 和强停恢复全部通过。
- 已新增 `tool/export_large_scenario_vault.dart`，可把 20 个大型场景导出为 120 份 Markdown。
- 已把 220 份人工检查数据写入 HONOR 90 正式应用的 vault，包含 120 个大型场景成果和 100 条设备验收用例；首页显示 20 个待办、140 条知识，事项页显示 20 件事。
- 按用户要求，HONOR 90 应用的测试 Key 当前保留在系统安全存储中，暂未清除。
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

## 7. 风险、阻塞与下一步

### 风险与边界

- Git hooks 可被 `--no-verify` 绕过，项目规则明确禁止该操作。
- `core.hooksPath` 是本地仓库配置，不随仓库内容自动传播；克隆后必须运行安装脚本。
- 公开仓库已提供 Flutter CI，但 Git hooks 和本地发布扫描仍可能被 `--no-verify` 绕过；推送时必须保留 hook 和人工审计。
- `archive/pre-open-source` 仅用于本机追溯，包含迁移前敏感测试信息，绝不可推送到 GitHub 或复制给公开协作方。
- `v1.0.0` Android APK 使用 Debug 证书，Windows 安装包和 EXE 未进行代码签名；用户可能看到未知来源或 SmartScreen 提示，正式稳定版前必须完成独立签名。
- GitHub Release 仍由标签触发；重跑工作流时必须保持标签版本、`pubspec.yaml` 和 `docs/releases/<tag>.md` 一致。
- 自动记录目前只授权高置信新建；模型更新、删除、重复规则和敏感内容不会自动执行。真实 Key 的联网流式与自动建成果仍未跑回归。
- 会话与图片只在本端保存；删除会话会删除本地消息和附件，但不会删除已创建的成果。
- 当前同步按钮运行的是端内沙箱 Provider，用于验证三 hash 与冲突逻辑，不等于 OneDrive 已联调。
- 首版仅支持文本/分享文本捕获，截图视觉 OCR 链路尚未接入和回归。
- 真实模型已有一条 AVD 和一条 Galaxy Tab 真机端到端样本；尚未形成持续 API Key、30-50 条回归集或费用控制策略。
- 20 个大型场景使用确定性模拟 SSE 和工具调用，验证应用侧多结果处理与持久化，不代表线上模型对 20 段原文的抽取准确率。
- Android release APK 使用 debug 签名，不能作为正式分发包。
- Windows release 与 integration test 已完成；物理设备、托盘、热键、Toast 和通知仍未在真实 Windows 桌面长期运行验证。
- Galaxy Tab S7 FE 与 HONOR 90 均已完成真机 50 条、系统入口、强停恢复、20 个大型场景和真实模型验证。
- 两台设备上的测试应用与成果暂时保留便于检查；Galaxy Tab 的测试 Key 已清除，HONOR 90 按用户要求仍保留测试 Key；未执行系统数据清理或卸载。
- MagicOS/One UI 后台策略、通知、相机和第三方 App 图片分享必须单独采集真机证据。
- 当前应用尚未实现本地提醒通知，不能把 UI 矩阵通过写成通知验收通过。
- ADB `shell` 不是媒体 URI 所有者，无法为外部图片分享命令授予 MediaStore 读权限；第三方 App 图片分享仍需人工真机验收。
- 相机拍照入口尚未在模拟器执行完整拍照流程。
- 本轮日历工作区已通过主机、Windows 原生冒烟、Android AVD 冒烟和 Android UI 100 条集成矩阵；尚未在 HONOR/Galaxy 物理设备上人工复核新日历布局。

### 下一步

1. 后续公开开发直接在干净 `main` 上增量提交，禁止推送 `archive/pre-open-source`；新版本必须同步提升 `pubspec.yaml` 版本并新增 `docs/releases/v<version>.md`。
2. 配置 Android 独立签名和 Windows 代码签名，为后续稳定版准备正式证书。
3. 在两台设备上验证电池优化、自启动、后台冻结和本地通知恢复。
4. 登记 Microsoft public client，完成 OneDrive App Folder、delta、eTag 和 PKCE 联调。
5. 在具备受控测试 Key 和费用预算时，用线上 `deepseek-flash` 对 20 个大型场景做抽取质量评分，并补 30-50 条中文样本。
6. 在新日历工作区基础上，连接 HONOR/Galaxy 物理设备复跑双设备验收和系统分享强停恢复探针。

