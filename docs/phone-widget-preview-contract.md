# Android 手机验收与 v1.6.2 预览发布合同

本合同约束 `1.6.2+16` 的 API 35 手机模拟器验收、公开包覆盖升级与 `phone-v1.6.2` 预览发布。先在 E 盘预检；发现可确认的卷/物理盘 I/O 错误时关闭本轮实例，在 D 盘隔离环境重新预检和验收。SDK、镜像、AVD、快照、临时文件和原始证据都必须落在所选盘。候选验收未全部通过，不推送、不打标签、不发布。

## 文件与 API

| 路径 | 职责 |
|---|---|
| `scripts/lib/android-phone-validation.ps1` | 选定盘路径解析、读写预检、AVD 启停、APK 与已安装版本核验。 |
| `scripts/verify-widget-preview-phone.ps1` | Preflight、Start、Upgrade、Finish、Abort；只输出 JSON、管理本轮 AVD 与证据，不执行 GitHub 写操作。 |
| `scripts/verify-secretary-activity-phone.ps1` | 复用共享验证库并保留既有参数与 E 盘行为。 |
| `HomeWidgetRenderer.kt`、`HomeWidgetOpenActivity.kt` | Widget API 31+ 的标准 StackView 页面、API 24–30 固定行、透明点击转发和页状态校验。 |
| `test-results/phone-release-v1.6.2/VALIDATION.md` | 保存本仓库内的精简实测结论；截图、日志、APK、会话和 JSON 证据留在所选盘输出目录。 |

运行命令：

```powershell
./scripts/verify-widget-preview-phone.ps1 `
  -Stage <Candidate|Published> `
  -Action <Preflight|Start|Upgrade|Finish|Abort> `
  [-ValidationDrive <E|D>] `
  [-SdkRoot <absolute-path>] `
  [-AvdHome <absolute-path>] `
  [-OutputDir <absolute-path>] `
  [-BootTimeoutSeconds 180] `
  [-EvidencePath <absolute-path>]
```

`ValidationDrive` 默认 `E`。盘符为 `X` 时默认 SDK 为 `X:\DevTools\Android\Sdk`，AVD 为 `X:\DevTools\Android\.android\avd`，结果为 `X:\DevTools\Android\aitext-validation\phone-v1.6.2`。路径覆盖项须是选定盘内解析联接与符号链接后的绝对路径；同一会话后续命令须使用相同盘和输出目录。

PowerShell 函数失败时抛错：

```text
Resolve-ValidationPath(path, label, drive: E|D) -> canonical absolute path
Resolve-AbsoluteEPath(path, label) -> canonical E: path
Test-ValidationStorage(sdkRoot, avdHome, outputDir, drive: E|D) -> StorageFacts
Start-PhoneAvd(sdkRoot, avdHome, avdName, outputDir,
               bootTimeoutSeconds, validationDrive=E) -> AvdSession
Stop-PhoneAvd(session, sdkRoot) -> void
Get-PhoneApkFacts(apkPath, sdkRoot) -> ApkFacts
Test-PhoneApk(apkPath, checksumsPath, sdkRoot,
              version, build, certificateSha256) -> ApkFacts
Assert-InstalledVersion(serial, packageName, expectedVersion,
                        expectedBuild, sdkRoot) -> void
```

```text
StorageFacts = {drive, diskNumber, probeBytes, probeSha256,
                eventBaseline, checkedPaths}
AvdSession = {serial, processId, avdName, dataPath, avdHome,
              systemImagePath, apiLevel, drive, diskNumber}
Session = AvdSession + {sessionId, stage, outputDir, installedVersion,
                        installedBuildNumber, artifactSha256, startedAt,
                        upgraded, machineChecks, storage}
Evidence = {sessionId, checks:[{id,status,detail,artifacts:[relativePath]}]}
ValidationResult = {stage,status,aborted,sessionId,drive,version,
                    buildNumber,avdName,deviceSerial,artifactSha256,checks}
ApkFacts = {packageName,sha256,certificateSha256,versionName,versionCode,
            minSdk,targetSdk,debuggable,signatureV2}
```

## 阶段行为

- **Preflight**：核验 SDK、NDK、API 35 镜像和 AVD 配置；在输出目录写入 256 MiB 文件、刷盘、回读并比较 SHA-256，随后只删除该探测文件；记录 Windows 存储事件基线。若 E 盘读写或检查确认 I/O 错误，脚本复制 SDK 到 D 盘并在 D 盘独立预检。业务断言失败不触发换盘。
- **Candidate/Start**：要求对应盘预检通过；运行首页、表详情、小组件投影/配置、存储、桥接和秘书工具定向测试；构建并核验 Debug `1.6.2+16` APK，启动 `aitext_v162_candidate_phone`，安装并核验版本，返回 `Session`。成功只表示环境和安装就绪。
- **Published/Start**：核验公开 Release 是非草稿预览版、资产精确为指定 APK 与 `SHA256SUMS.txt`，核验 v1.6.2 和 v1.6.1 APK 的哈希、版本、API 24/36、正式长期证书及 v2 签名；在 `aitext_v162_upgrade_phone` 安装旧版 `1.6.1+15`。
- **Published/Upgrade**：要求同一会话里唯一且有效的 `upgrade.synthetic-state` 与 `upgrade.widget-binding` 证据，复核 v1.6.2 APK 哈希后执行 `adb install -r`，核验已安装 `1.6.2+16` 并返回更新的 `Session`。Candidate/Upgrade 是参数错误。
- **Finish**：要求 `EvidencePath`，与脚本机器检查合并，验证 sessionId、必需检查 ID、唯一性、状态和输出目录内的普通文件；原子写入 `candidate-result.json` 或 `published-result.json`，再关闭本次启动的 AVD。任一必需项缺失、重复、失败、跳过或证据无效，结果为 `failed`。
- **Abort**：可选证据；写入 `status: failed, aborted: true` 和已完成/未完成状态，关闭本次启动的 AVD。成功命令退出 0；参数、环境、证据或断言失败退出 1。发生错误时仅清理本次启动的实例；不卸载应用、不清空既有 AVD 数据。

每次脚本调用的标准输出是一个 JSON 对象；测试、构建、ADB、模拟器和下载日志写入所选盘输出目录。

路径解析必须确认目标在所选盘，链接目标仍在该盘。AVD 启动后以 ADB serial 唯一对应目标 AVD、`sys.boot_completed=1` 且设备实报 API 35 为准；会话记录数据目录、镜像目录和盘符。停止前再次核验归属。StorageFacts 的基线之后若出现选定卷 NTFS 错误、对应物理盘 I/O 错误或可复现读写错误，本轮失败并迁移另一盘重新验收；E 盘证据不得并入 D 盘通过结果。

公开 APK 必须包名正确、校验清单哈希匹配、API 24/36、非 Debuggable、v2 签名有效且长期证书指纹与项目一致。候选 Debug APK 则须为正确包名和 `1.6.2+16` 且 Debuggable。任何核验工具失败不能计作通过。候选交付哈希记录在 `artifactSha256`；公开版会话也记录旧 APK 哈希。

## Android 渲染合同

```kotlin
fun render(context: Context, manager: AppWidgetManager, widgetId: Int): Boolean
fun showPage(context: Context, manager: AppWidgetManager,
             request: HomeWidgetPageRequest): Boolean
```

`render` 在向启动器提交内容或占位后返回 `true`。API 31+ 每个尺寸使用标准 `StackView` 集合页；API 24–30 使用固定行。渲染与翻页共用尺寸、系统字体倍率及布局容量规则。每页使用不透明表面、紧凑标题和时间；单页隐藏分页控件。集合条目通过 pending-intent template 填充 `entry` 或 `page` 目标，透明转发 Activity 处理页目标后直接退出，只有条目目标启动 App。`showPage` 仅在校验通过且目标页已提交时返回 `true`，过期、越界或提交失败返回 `false`，不打开 App。刷新和尺寸变化回到首页，各实例状态隔离。MethodChannel、快照 schema、卡片 ID 和绑定存储兼容既有版本。

## Candidate / Published 检查 ID

Candidate 必需且唯一：

`host.targeted-tests`、`apk.candidate`、`environment.avd-boot`、`install.candidate`，以及 `device.home-order`、`device.todo-order`、`device.widget-source-merge`、`device.widget-exclusions`、`device.widget-seven-day-boundary`、`device.widget-privacy`、`device.widget-2x2`、`device.widget-4x2`、`device.widget-large`、`device.widget-light`、`device.widget-dark`、`device.widget-large-font`、`device.widget-swipe`、`device.widget-page-taps`、`device.widget-resize-reset`、`device.widget-instance-isolation`、`device.widget-cold-click`。

Published 必需且唯一：`release.metadata`、`apk.current`、`apk.previous`、`environment.avd-boot`、`upgrade.previous-install`、`upgrade.synthetic-state`、`upgrade.widget-binding`、`upgrade.cover-install`、`upgrade.data-retained`、`upgrade.widget-paging`。

证据状态只能是 `passed|failed|skipped`；设备结论附截图、界面树或日志。证据路径相对于输出目录，解析后须仍在输出目录且指向存在的普通文件。机器检查由脚本生成，设备证据不得覆盖。缺设备的 API 24–30 与荣耀 90 记未覆盖，不计入 API 35 门禁。

## 推送、发布与升级门禁

Candidate 全部必验项通过后，保留 `c1d0c1b`，更新 README、发行说明、RM_HANDOFF 和结果文档，创建单一 Conventional Commit 并推送 main。只有同一提交的 Flutter CI 成功后才推送 `phone-v1.6.2` 标签；现有 Android Release 工作流负责发布。公开预览版确认仅有 `personal-ai-inbox-v1.6.2-android.apk` 与 `SHA256SUMS.txt` 两项资产。然后在相同候选通过盘位的隔离 AVD 准备合成会话、表、条目与桌面绑定，从公开 `v1.6.1+15` 覆盖升级并核对数据、绑定、翻页和条目点击。复核失败时记录失败并停止交付确认，不移动标签。

本机只执行定向用例，不运行全量测试，不发布 Windows 包。若 GitHub 写权限不可用，保留验收结果并记录具体阻塞步骤；不得用未发布的候选结果描述成公开版或真机验收。

## 2026-11-15 接手后的复验顺序

1. 在 D 盘先检查空间、保留失败结果并新开候选会话。每轮绑定实际安装包 SHA-256、会话 ID 和桌面证据；旧会话截图只用于对照。
2. 点击分三组：App 在后台、用 `adb shell am kill` 杀掉后台进程并用 `pidof` 确认退出、用 `am force-stop` 强停。冷进程门禁用第二组：在当前可见条目的实际坐标点一次，记录接收端日志和详情条目 ID。强停单列，因为它还改变包的停止状态。若普通冷进程也失败，先用日志确认点击是否到达接收器；没到则查集合行的点击绑定，到达则查目标验证和导航交接。
3. 滑动复现用至少三页，从当前可见条目中央开始，分别向上、向下滑。比较前后最前页的条目 ID/页码，不用截图哈希或整棵界面树判断。用按钮翻到中页作对照，记录手势起止坐标和停稳后的页码。若仅按钮有效，再检查 StackView 页根布局、触摸子视图和模拟器启动器的事件分发。
4. 两项核心交互稳定后，补齐排除表、七天边界、简洁/详细、深浅色、大字体、三种尺寸、调整尺寸和双实例矩阵。候选全部通过才提交、推送并等待 CI；最后执行公开包覆盖升级。升级安装回执由脚本生成，不由设备证据填写。

## 2026-11-16 候选结论

API 35 最终候选会话 `91805fc9-169e-49ec-be09-6756b31e9e5d` 的 21 个机器与设备检查全部 `passed`。Debug APK `1.6.2+16` SHA-256 为 `0d11c2805742e77eb4686cd1bb1b3f1b7abdaf4a789e4a339516cb5f12182fb1`。冷进程单次点击、标准 StackView 双向滑动、前后按钮、多实例隔离和尺寸调整均已实测；2×2、4×2、大尺寸、浅色、深色、大字体、简洁、详细和隐藏模式均有证据。API 24–30 固定行与荣耀 90 仍缺设备，未计入 API 35 门禁。

本轮同时修复了 Windows PowerShell 5.1 将无 BOM UTF-8 证据误按本地代码页读取的问题；证据 JSON 现显式按 UTF-8 解码。候选通过后才允许推送 main、等待同提交 CI、创建 `phone-v1.6.2` 标签并执行公开包覆盖升级。
