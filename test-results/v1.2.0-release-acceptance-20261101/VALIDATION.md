# v1.2.0 发布验收记录

日期：2026-11-01（Asia/Singapore）
执行：DeepSeek Harness / Codex 验收
范围：GitHub Release `v1.2.0` 资产、APK 版本与签名、Windows 便携包元数据、剩余 Android/Windows 交互验收边界。
约束：只读核验为主；不改业务代码、不移动标签、不推送、不触发全量测试/CI；未使用真实用户资料。

## 已执行（真实结果）

| 检查 | 命令/方法 | 结果 |
|---|---|---|
| Release 工作流 | GitHub REST `actions/runs/41218586972`（主管保存 `release-run.json`） | `completed`/`success`，head `7b42167df46cb557697a2152d500b76fb1bf29c2`，17 个业务步骤含 `Verify Android artifact`、`Publish GitHub Release` 全部 success |
| main CI | `main-ci.json`（仅含 `status`/`conclusion`/`headSha`） | `completed`/`success`，head `34b8543eb6071a4f2132b00064e1fcec7db701af` |
| main CI 测试步骤 | 浏览器匿名 REST `actions/runs/41219403100/jobs` | `Test` 步骤 success（该结论不在 `main-ci.json` 中） |
| Release 元数据 | `release.json`（gh 格式，键为 `assets`/`isPrerelease`/`tagName`/`url`） | `tagName=v1.2.0`、`isPrerelease=true`，资产 4/4 `uploaded`；该文件不含发布时间字段 |
| 发布时间 | 浏览器匿名 REST `releases/tags/v1.2.0`（早先只读核验） | `published_at=2026-10-31T16:31:22Z`（=2026-11-01 00:31:22 +08:00）；`release.json` 无此字段 |
| 资产完整性 | `Get-FileHash -Algorithm SHA256` 对比 GitHub API digest 与 `SHA256SUMS.txt` | APK / setup / portable 三项本地哈希与 API digest、`SHA256SUMS.txt` **全部一致**；`ALL_ASSETS_VERIFIED=True`（`asset-verification.txt`） |
| APK 重新下载 | 浏览器通道下载官方资产（88,781,399 B）到 `tests/agent-temp/v1.2.0-release-acceptance-20261101/` | 完整；本地 SHA-256 `896f8cf1...` 与 API digest 一致。此前 `local-hashes.txt` 中 `F2D6...` 为 28,555,771 B 部分下载，已覆盖 |
| APK 版本 | `aapt2 dump badging`（SDK build-tools 36.0.0） | `versionCode='8'`、`versionName='1.2.0'`、`minSdkVersion='24'`、`targetSdkVersion='36'`、`compileSdk='36'`、声明 `android.permission.INTERNET`、label `懒狗秘书` |
| APK 签名 | `apksigner verify --print-certs` / `verify -v` | 证书 DN `CN=Lazy Secretary Android Release, OU=Release, O=YuanFangCH, C=SG`；证书 SHA-256 `51b5e2f3f44ce9374cb680a0173c6498a4e13c718c602a355a8b6a50523f4816`，与 `release.yml` 期望值一致；v2 方案 `true`（v1/v3/v3.1/v4 `false`） |
| Windows 便携包 | `Expand-Archive` 结果与 zip 条目逐一对比（`System.IO.Compression`） | zip 23 个条目，本地 `missing=0`、`size_mismatch=0`；`personal_ai_inbox.exe`、`flutter_windows.dll`、`sqlite3.dll`、`data\app.so`、`LICENSE`、`README-Windows.txt` 均存在 |
| Windows 版本元数据 | `(Get-Item).VersionInfo` | 便携 EXE `FileVersion=1.2.0+8`、`ProductVersion=1.2.0+8`、`ProductName=懒狗秘书`；安装包 `FileVersion=1.2.0.0`、`ProductVersion=1.2.0` |

### 复用的既有证据

- 主机侧秘书/导航定向用例 8/8：`test-results/secretary-embedded-20261031/VALIDATION.md`（主机测试，**不能替代** Android 设备证据）。
- Release 工作流 41218586972 内部已通过格式、分析、`flutter test`（host）与构建；本记录不重复运行。

## 未执行 / 未核实边界

| 项目 | 状态 | 依据 |
|---|---|---|
| Android 秘书页 AVD 定向集成测试 | **未执行（环境阻塞）** | `adb devices` 无设备；有界搜索未发现 `emulator.exe`；`E:\DevTools\Android\Sdk` 为空；`D:\Flutter-recovery-3.47.6\ui-fix-review-20261025\android-sdk` 有 build-tools 36.0.0 / platform-tools / platforms(35,36)，但无 emulator 与 system-images；`D:\DevTools\table-notebook-toolchain` 的 SDK 仅 cmdline-tools。目标用例：`app/integration_test/android_smoke_test.dart` 中 `secretary draft and reply survive switching to calendar and back` |
| Windows 便携包启动验收 | **未执行（无法证明数据隔离）** | 代码使用 `getApplicationSupportDirectory()`（`app/lib/data/device_paths_io.dart:4`、`io_vault_store.dart:22`），未发现环境变量覆盖；只读探测发现真实目录 `C:\Users\18377\AppData\Roaming\com.yuanfang.aitext` 已存在。为避免写入/读取真实数据，未启动应用；未使用独立 Windows 用户或 VM |
| 窗口/主页面可达/退出 | 未执行 | 同上，随启动验收一并未做 |
| 安装包安装/卸载 smoke | 未在本机执行 | Release 工作流已覆盖静默安装、必需文件与卸载步骤（CI 证据）；本机不复跑 |
| 真实用户资料迁移 / 覆盖升级 | 未执行 | 无真实资料备份，且本轮不接触真实数据 |
| APK 其余边界 | versionName/versionCode/签名方案已核验；v3 方案在 `apksigner verify -v` 中为 `false`；**未做 Play 完整性校验** | 当前 minSdk 24 下 v2 方案可满足安装；v3 未启用不构成本轮阻塞 |

## 环境说明（非项目问题）

- 本执行环境 `gh` 未登录，shell 到 GitHub 的通道不可用；GitHub 数据来自主管保存的 REST 快照与本轮浏览器匿名读取，未使用任何凭据。
- Windows 主机为 Windows NT 10.0.26200 / AMD64；便携包已按官方发布资产解压于 `tests/agent-temp/v1.2.0-release-acceptance-20261101/portable/`。

## 证据文件

- `test-results/v1.2.0-release-acceptance-20261101/local-hashes.txt`（主管初检 + 本轮完整 APK 复核追加）
- `test-results/v1.2.0-release-acceptance-20261101/asset-verification.txt`
- `test-results/v1.2.0-release-acceptance-20261101/apk-verification.txt`
- `test-results/v1.2.0-release-acceptance-20261101/windows-portable.txt`
- `test-results/v1.2.0-release-acceptance-20261101/release.json`、`release-run.json`、`main-ci.json`
- `tests/agent-temp/v1.2.0-release-acceptance-20261101/`（四个资产与解压后的 portable 目录）

## 结论

- 发布成功与资产完整性、APK 版本/长期证书指纹、Windows 包结构与版本元数据：**已核实通过**。
- Android 秘书交互与 Windows 启动：**仍未验收**，原因为本机无可用模拟器/系统镜像，以及无法证明 Windows 用户数据隔离。二者不得在交接中写成已通过。
