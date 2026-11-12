# Android 手机验收与预览版发布合同

> 状态：合同已冻结，实施待执行。  
> 冻结日期：2026-11-12（Asia/Singapore）  
> 本文件定义 `v1.6.1+15` 手机候选的模拟器验收、GitHub 预发布和公开包复核边界。脚本、Android 集成测试、版本升级和发布本身尚未由本文件完成。

## 1. 目标与固定标识

本轮只交付 Android 手机预览版，验证秘书运行活动与浅蓝主题。继续使用现有活动事件、会话 transcript、模型客户端和 `phone-v*` 发布工作流，不新增网络 API、模型请求类型、数据库字段或持久化迁移。

| 项目 | 合同值 |
|---|---|
| 应用版本 | `1.6.1+15`，发布实施时写入 `app/pubspec.yaml` |
| Git 标签 | `phone-v1.6.1` |
| Android applicationId | `com.yuanfang.aitext.personal_ai_inbox` |
| 最低 Android | API 24 |
| 目标 Android | API 36 |
| 发布类型 | GitHub pre-release |
| APK 资产名 | `personal-ai-inbox-v1.6.1-android.apk` |
| 校验资产名 | `SHA256SUMS.txt` |
| 长期证书 SHA-256 | `51b5e2f3f44ce9374cb680a0173c6498a4e13c718c602a355a8b6a50523f4816` |
| 上一版公开安装包 | `phone-v1.6.0` 的 `personal-ai-inbox-v1.6.0-android.apk` |

标签、`versionName` 和 `docs/releases/v1.6.1.md` 必须一致。标签只能指向已经通过 main CI 的同一提交；标签推送后不得移动或复用。

## 2. 文件结构

| 路径 | 类型 | 职责 |
|---|---|---|
| `scripts/verify-secretary-activity-phone.ps1` | 实施新增 | 启动 E 盘 AVD，执行候选验收或公开包复核，输出结构化 JSON。不推送代码、不打标签、不创建 Release。 |
| `app/integration_test/secretary_activity_phone_test.dart` | 实施新增 | 在 Android 集成测试入口注入可控模型流，验证活动状态、主题、滚动、停止/失败和会话恢复。 |
| `app/lib/modules/conversation/conversation_workspace.dart` | 实施修改 | 工具真实派发时立即通知界面，回执结算继续沿用原有流式批量更新。 |
| `app/lib/ui/pages/conversation/agent_task_status_card.dart` | 实施修改 | 在低高度和 1.5 倍字体下约束任务状态卡高度并提供内部滚动，避免挤压秘书消息区。 |
| `docs/phone-preview-validation-contract.md` | 本合同 | 冻结文件边界、函数接口、结果格式、验收和发布门禁。 |
| `docs/releases/v1.6.1.md` | 发布准备新增 | GitHub Release 的中文发行说明，描述活动展示、浅蓝主题、兼容性、验证结论和未覆盖项。 |
| `test-results/phone-release-v1.6.1/VALIDATION.md` | 验证记录 | 记录候选、CI、公开资产、E 盘路径、升级复核及未执行项。 |
| `app/pubspec.yaml` | 发布准备修改 | 版本改为 `1.6.1+15`。 |
| `README.md` | 发布准备修改 | 更新下载入口、版本状态和验证记录链接。 |
| `RM_HANDOFF.md` | 每次正式修改同步 | 更新状态、验证、风险、下一步和变更记录。 |

本地构建包、AVD 日志、截图、UI hierarchy、下载的公开 APK 和校验清单统一放在：

```text
E:\DevTools\Android\aitext-validation\phone-v1.6.1
```

该目录不纳入 Git。仓库只保存合同、长期测试、发布说明和精简后的验证结论。

## 3. 现有系统边界

本轮的设备测试使用以下已实现接口；合同不改变其事件、流或持久化语义：

- `ChatService.streamReply(..., ChatActivitySink? onActivity)` 继续产生 `ChatActivityPhaseChanged` 和 `ChatActivityToolDispatched`。
- `ConversationWorkspace.liveActivityFor(String assistantMessageId)` 只向当前未取消的助手回复提供内存快照。
- 历史工具行继续由 `ChatMessage.toolTranscript` 经 `completedChatActivityTools` 投影，不新增数据库字段。
- 模型测试替身只替换现有 OpenAI 兼容模型客户端；请求仍走 `POST /chat/completions` 流式响应格式。
- 活动事件和 UI 不显示原始推理、工具参数、目标 ID 或工具结果正文。
- 模拟器测试不得调用真实模型或真实用户数据。API Key、OAuth 令牌、签名材料和设备备份不得进入脚本参数、结果 JSON、控制台日志或仓库。

## 4. PowerShell 主入口

脚本入口为：

```powershell
./scripts/verify-secretary-activity-phone.ps1 `
  -Stage Candidate
```

参数定义：

```powershell
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Candidate', 'Published')]
    [string]$Stage,

    [string]$SdkRoot = 'E:\DevTools\Android\Sdk',
    [string]$AvdHome = 'E:\DevTools\Android\.android\avd',
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$AvdName = 'aitext_v161_phone',
    [string]$OutputDir = 'E:\DevTools\Android\aitext-validation\phone-v1.6.1',
    [ValidateRange(1, [int]::MaxValue)]
    [int]$BootTimeoutSeconds = 180
)
```

公共校验：

1. `SdkRoot`、`AvdHome` 和 `OutputDir` 都必须是绝对路径。
2. 路径本身、符号链接/目录联接的最终目标以及 AVD 实际数据目录必须位于 `E:`。
3. `SdkRoot` 必须包含 `adb`、`emulator`、`cmdline-tools`/`build-tools` 和目标系统镜像；AVD 配置引用的 system image 实际路径也必须位于 `E:`。
4. `AvdName` 必须已存在且没有被其他 emulator 实例占用。
5. 输出目录会创建但不得清空其中与本次版本无关的文件。同名运行产物可覆盖，其他内容不得删除。
6. 任何输入或路径门禁失败都必须退出 `1`；若输出目录已可写，也要写入失败结果。

标准退出码：

- `0`：该阶段所有必需检查通过，结果 JSON 的 `status` 为 `passed`。
- `1`：参数、环境、执行、断言或结果写入失败，结果 JSON 的 `status` 为 `failed`。

脚本不提供 `0` 以外的其他成功码，不吞掉子进程失败，也不以仅有日志作为成功证据。

## 5. 辅助函数

### `Start-ValidationAvd`

```powershell
function Start-ValidationAvd {
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] [string]$SdkRoot,
        [Parameter(Mandatory = $true)] [string]$AvdHome,
        [Parameter(Mandatory = $true)] [string]$AvdName,
        [Parameter(Mandatory = $true)] [string]$OutputDir,
        [Parameter(Mandatory = $true)] [int]$BootTimeoutSeconds
    )
}
```

成功时返回 `[pscustomobject]`：

| 字段 | 类型 | 含义 |
|---|---|---|
| `Serial` | `string` | 本次实例的 ADB serial，例如 `emulator-5556` |
| `ProcessId` | `int` | 本次 emulator 根进程 PID |
| `DataPath` | `string` | AVD 实际数据目录，必须位于 E 盘 |

行为：

- 校验参数和路径；解析 AVD 配置及 system image 的最终路径。
- 将子进程的 `TEMP`、`TMP`、`ANDROID_USER_HOME`、`ANDROID_AVD_HOME`、`ANDROID_EMULATOR_HOME` 和 Android preferences temp 指向 `OutputDir` 下的运行目录，避免模拟器大文件落到 C 盘。
- 启动前确认该 AVD 未被占用；只使用本次启动返回的 serial 执行后续 ADB 命令。
- 等待 `sys.boot_completed=1`，最多 `BootTimeoutSeconds` 秒。等待期间进程退出、serial 无法唯一归属或超时都抛错。
- 结束时只关闭本次启动实例。优先执行 `adb -s <Serial> emu kill`；若进程仍在，只终止返回的 `ProcessId`，不得按 `emulator` 名称批量结束其他实例。
- 成功返回前验证 `DataPath` 和 system image 最终路径仍在 E 盘。

抛错条件包括：输入无效、SDK/ADB/emulator 缺失、系统镜像或 AVD 不在 E 盘、AVD 已占用、无法识别唯一 serial、启动失败、boot 超时和路径逃逸。

### `Test-PublishedApk`

```powershell
function Test-PublishedApk {
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] [string]$ApkPath,
        [Parameter(Mandatory = $true)] [string]$ChecksumsPath,
        [Parameter(Mandatory = $true)] [string]$SdkRoot,
        [Parameter(Mandatory = $true)] [string]$ExpectedVersion,
        [Parameter(Mandatory = $true)] [int]$ExpectedBuild,
        [Parameter(Mandatory = $true)] [string]$ExpectedCertificateSha256
    )
}
```

成功时返回 `[pscustomobject]`：

| 字段 | 类型 | 约束 |
|---|---|---|
| `Sha256` | `string` | APK 实际 SHA-256，小写 64 位十六进制 |
| `CertificateSha256` | `string` | APK 签名证书 SHA-256，小写 64 位十六进制 |
| `VersionName` | `string` | 必须等于 `ExpectedVersion` |
| `VersionCode` | `int` | 必须等于 `ExpectedBuild` |
| `MinSdk` | `int` | 必须为 `24` |
| `TargetSdk` | `int` | 必须为 `36` |

函数必须完成以下原子校验；任一项不符即抛错，不返回部分成功对象：

1. APK 和 `SHA256SUMS.txt` 存在且为普通文件。
2. 清单中恰有一条记录引用 APK 文件名，文件名与路径传入值的 basename 一致。
3. APK 实际 SHA-256 与清单值一致，清单中的额外空行可忽略，重复目标记录视为失败。
4. 使用现有 Android build-tools 的 `aapt2 dump badging` 读取版本和 API。
5. Android manifest 中 application `debuggable` 必须为 false。
6. 使用 `apksigner` 验证 v2 签名；证书 SHA-256 与 `ExpectedCertificateSha256` 一致。
7. `ExpectedVersion` 必须匹配 `^\d+\.\d+\.\d+$`，`ExpectedBuild` 必须大于 0，证书参数必须是 64 位十六进制。

`Candidate` 阶段也可对本地正式签名 APK 调用该函数，但发布前的最低门禁以公开下载资产为准。

## 6. 结果 JSON

`Candidate` 写入 `<OutputDir>\candidate-result.json`；`Published` 写入 `<OutputDir>\published-result.json`。文件采用 UTF-8、indented JSON，并在执行结束后原子替换。

顶层结构：

```json
{
  "stage": "Candidate",
  "status": "passed",
  "version": "1.6.1",
  "buildNumber": 15,
  "avdName": "aitext_v161_phone",
  "deviceSerial": "emulator-5556",
  "artifactSha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
  "checks": [
    {
      "id": "activity.completed-fold",
      "status": "passed",
      "detail": "折叠入口存在，展开后显示已匹配回执的工具。"
    }
  ]
}
```

字段约束：

| 字段 | 类型 | 约束 |
|---|---|---|
| `stage` | `string` | `Candidate` 或 `Published` |
| `status` | `string` | `passed` 或 `failed` |
| `version` | `string` | 必须是 `1.6.1` |
| `buildNumber` | `int` | 必须是 `15` |
| `avdName` | `string` | 本次目标 AVD |
| `deviceSerial` | `string \| null` | 未启动或已清理实例时为 `null` |
| `artifactSha256` | `string \| null` | 未能产出或下载 APK 时为 `null` |
| `checks[].id` | `string` | 稳定、机器可读 |
| `checks[].status` | `string` | `passed`、`failed` 或 `skipped` |
| `checks[].detail` | `string` | 可诊断结果；不得包含推理、参数、结果正文或秘密 |

`status` 只有在所有必需检查均为 `passed` 时才可为 `passed`。任一必需检查为 `failed`，或环境/执行失败，结果为 `failed`；`skipped` 必须写明原因，不能把未覆盖项伪装成通过。

## 7. 集成测试接口

`app/integration_test/secretary_activity_phone_test.dart` 定义测试专用枚举：

```dart
enum SecretaryActivityScenario {
  completed,
  stopped,
  failed,
}
```

测试私有辅助函数：

```dart
Future<void> runSecretaryActivityScenario(
  WidgetTester tester, {
  required SecretaryActivityScenario scenario,
}) async;
```

成功时正常返回，由测试运行器统一判定通过。任何界面断言失败、异常或超时都由 `WidgetTester` 抛出，函数不得吞错或把失败改写为跳过。

函数行为：

- 每个场景使用独立的临时 vault、SQLite 索引、内存会话存储和合成附件存储；不得读取真实用户资料。
- 使用 `MockClient.streaming` 替换现有模型客户端，并按 `POST /chat/completions` 的 SSE 响应格式返回片段。
- 使用 `Completer`/stream controller 或等价暂停点，在首个推理片段、首个正文片段、工具回执和下一轮模型请求处控制放行；断言不得依赖固定 `sleep`。
- `completed` 场景产生思考、工具调用、回执和最终正文。
- `stopped` 场景在工具回执后或下一轮模型请求前停止，并保留已有回执对应的折叠入口。
- `failed` 场景通过可控制的流错误或模型响应失败进入失败收尾；已有工具回执仍可折叠回看。
- 测试输入包含可识别的合成推理、参数和结果文本，并断言这些原文未出现在活动区。
- 重开会话场景从同一内存/临时存储重新挂载界面，验证历史工具行由 transcript 投影恢复。

## 8. 候选验收检查

稳定检查 ID 至少包括：

| ID | 验收内容 |
|---|---|
| `environment.avd-e-drive` | SDK、system image、AVD 数据和子进程临时目录最终路径均在 E 盘 |
| `environment.avd-boot` | 指定 AVD 唯一启动并完成 boot |
| `host.activity-projection` | 活动投影、同轮去重、跨轮复用和孤立回执回归通过 |
| `host.chat-service` | 首字前阶段、实际派发、重试、取消和停止时序通过 |
| `host.secretary-ui` | 完成、停止、失败、折叠与历史恢复 UI 回归通过 |
| `host.large-history` | `conversation_large_history_ui_test.dart` 通过 |
| `device.activity-before-first-token` | 首字前可见准备/等待/思考状态 |
| `device.activity-tool-running` | 实际操作前显示调用工具，未派发调用不显示 |
| `device.activity-tool-returned` | 回执保存后用相同工具键替换为已返回 |
| `device.activity-completed-fold` | 完成后默认折叠，展开可见匹配回执工具 |
| `device.activity-stopped-fold` | 停止后清理运行中状态并保留已有回执历史 |
| `device.activity-failed-fold` | 失败后清理运行中状态并保留已有回执历史 |
| `device.activity-history-reopen` | 重开会话后历史活动恢复顺序和分页通过 |
| `device.activity-privacy` | 活动区不显示原始推理、参数、目标 ID 或结果正文 |
| `device.theme-light` | 浅色主题使用合同浅蓝色且发送按钮一致 |
| `device.theme-dark` | 深色主题使用合同深色强调色且正文/背景不回退 |
| `device.layout-narrow` | 320dp、1.5 倍字体无溢出、遮挡或不可点控件 |
| `device.layout-wide` | 宽屏布局保持可读和可操作 |
| `device.scroll-follow` | 流式正文和活动行遵循现有滚动跟随规则 |
| `device.reopen-persistence` | 有工具回执的完成会话重开后仍显示折叠入口 |

候选阶段还必须运行现有定向测试：

```powershell
flutter test --no-pub `
  test/chat_activity_test.dart `
  test/chat_service_agent_test.dart `
  test/secretary_conversation_ui_test.dart `
  test/conversation_large_history_ui_test.dart
```

设备集成测试：

```powershell
flutter test --no-pub `
  integration_test/secretary_activity_phone_test.dart `
  -d <Start-ValidationAvd 返回的 Serial> `
  --reporter expanded
```

如已有测试入口能覆盖更多现有秘书矩阵，可以复用，但不得因此跳过上述直接相关检查。

候选 APK 由当前检出的 `app` 构建：

```powershell
flutter build apk --debug
```

构建产物复制到 `<OutputDir>\candidate-app-debug.apk`，`artifactSha256` 记录该文件摘要。脚本还要核对 `versionName=1.6.1`、`versionCode=15`、minSdk 24 和 targetSdk 36；Debug 候选允许保留 `debuggable=true`，正式签名与 v2 门禁由 `Published` 阶段执行。

`Published` 阶段的稳定检查 ID 至少包括：

| ID | 验收内容 |
|---|---|
| `release.metadata` | Release 存在、标签为 `phone-v1.6.1`、状态为 pre-release |
| `release.assets` | 只使用合同规定的 APK 与 `SHA256SUMS.txt` 作为本轮发布资产 |
| `apk.checksum` | 公开 APK 文件名、实际 SHA-256 与清单一致 |
| `apk.version` | `versionName=1.6.1`、`versionCode=15` |
| `apk.sdk` | minSdk 24、targetSdk 36 |
| `apk.debuggable` | application 非 Debuggable |
| `apk.signature` | v2 签名有效，长期证书记录一致 |
| `upgrade.previous-install` | E 盘 AVD 可安装 `v1.6.0+14` 公开包 |
| `upgrade.synthetic-data` | 写入可识别的合成会话与表数据 |
| `upgrade.overwrite-install` | 使用同一长期签名的 `v1.6.1+15` 覆盖安装成功 |
| `upgrade.data-retained` | 新包启动后合成会话、表和内容保留 |

## 9. 发布顺序

1. 将版本改为 `1.6.1+15`，新增 `docs/releases/v1.6.1.md`，同步 README 与 RM。
2. 在 E 盘 AVD 执行 `-Stage Candidate`。检查 JSON 必须是 `passed`，且所有 E 盘路径检查通过。
3. 检查 C 盘没有本次 AVD/system image 大文件；发现迁移、链接或回退到 C 盘时停止，修正后从干净实例重测。
4. 完成直接相关静态检查和定向测试，创建一个原子提交，保留已有功能提交。
5. 正常推送 `main`，等待 Flutter CI success。
6. 在通过 CI 的同一提交创建并推送 `phone-v1.6.1`，等待 Android Release success。
7. 确认 Release 是非草稿、`prerelease=true`，并只含通用 APK 与 `SHA256SUMS.txt`。
8. 下载公开资产，执行 `-Stage Published`。必须通过清单哈希、版本、API、非 Debuggable、v2 签名和长期证书校验。
9. 在 E 盘 AVD 安装上一版 `v1.6.0` 公开包，写入合成会话和表数据；再覆盖安装 `v1.6.1`，确认可启动、版本更新且合成数据保留。
10. 将 CI run、Release URL、公开 APK 哈希、证书、升级结论和未覆盖项写入 `test-results/phone-release-v1.6.1/VALIDATION.md`。

候选或公开包任一必需检查失败时，不发布或停止后续复核，先修复并重新走门禁。不得用 Debug 包代替公开 APK 验收，不得用固定延时掩盖模型流或 UI 时序问题，不得把模拟器通过描述为真机通过。

## 10. 发布说明与记录

`docs/releases/v1.6.1.md` 必须包含：

- 运行阶段与工具活动展示。
- 完成、停止和失败后的折叠历史。
- 浅色与深色主题的浅蓝色变化。
- 安装兼容性、长期签名和升级说明。
- 实际执行的定向测试、Android AVD、CI 和公开资产结论。
- 真机、旧版 Android、平板、Windows 和未执行项。

`test-results/phone-release-v1.6.1/VALIDATION.md` 必须区分 `passed`、`failed`、`skipped` 和 `not executed`，记录实际命令、设备 serial/API、AVD 数据路径、APK 路径/哈希、CI run、标签目标、Release URL 和公开包升级结果。未实际验证的内容不得写成通过。
