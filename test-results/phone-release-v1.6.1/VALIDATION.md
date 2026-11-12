# Android 手机 v1.6.1 验收与发布

日期：2026-11-12（Asia/Singapore）

## 当前结论

- 合同：已冻结于 `docs/phone-preview-validation-contract.md`。
- 代码状态：活动实现 `5d763d7`、发布准备 `302ad54`、CI 日期夹具修复 `8a36541` 已推送 main。
- 发布状态：GitHub pre-release `phone-v1.6.1` 已发布，标签指向 `8a36541`。

## 执行记录

| 检查 | 状态 | 说明 |
|---|---|---|
| 合同静态核对 | passed | 4 个相关 Markdown 文件相对链接全部解析；JSON 示例通过解析；`git diff --check` 通过 |
| E 盘 AVD 候选验收 | passed | `aitext_v161_phone` / API 35 / `emulator-5620`；完成、停止、失败、主题和宽屏 4/4 |
| 定向主机测试 | passed | 活动/服务/秘书/大历史 38/38；任务卡与相关秘书 UI 8/8 |
| 全库静态检查 | passed | 293 文件格式 0 change；`flutter analyze --no-pub` 0 issue |
| main CI | passed | 首轮 `43200235300` 因固定过去日期夹具失败；修复后 `43201007670` success |
| GitHub Android Release | passed | `43201383058` success；pre-release、正式签名 APK 与校验清单已发布 |
| 公开 APK 复核 | passed | 92,475,115 字节；SHA-256、版本、API、非 Debuggable、v2 签名与长期证书通过 |
| `v1.6.0` 到 `v1.6.1` 覆盖升级 | passed | E 盘发布 AVD 从 `v1.6.0+14` 覆盖到 `v1.6.1+15`，合成会话、表和条目保留 |

## 未覆盖

- 真机、旧版 Android、平板和 Windows。
- 真实模型、真实用户资料和真实云盘同步。

## 候选产物

- 路径：`E:\DevTools\Android\aitext-validation\phone-v1.6.1\candidate-app-debug.apk`
- 大小：242,247,382 字节
- SHA-256：`e19666357a3e1277bebb9c4a3dd1f50b84d284745f0f601cea90fbd2697b9a1c`
- 版本：`1.6.1+15`
- SDK：minSdk 24 / targetSdk 36
- 结构化结果：`E:\DevTools\Android\aitext-validation\phone-v1.6.1\candidate-result.json`，状态 `passed`
- AVD 数据：`E:\DevTools\Android\.android\avd\aitext_v161_phone.avd`

候选运行期间发现 320dp、1.5 倍字体下失败态任务卡纵向溢出 103px。任务卡现限制为屏幕高度的 28%（140–240dp）并支持内部滚动；复验后完成、停止、失败和主题/宽屏 4/4 通过。

## 公开产物

- GitHub Release：`https://github.com/YuanFangCH/personal-ai-inbox/releases/tag/phone-v1.6.1`
- 状态：非草稿 pre-release；标签目标 `8a36541314e0f7fdd118a89c7bf9011f9e1a675d`
- APK：92,475,115 字节
- SHA-256：`83cf43344c1e64ec01a35579b47b64700972c51ad8fad15a6081849938dd169a`
- 证书 SHA-256：`51b5e2f3f44ce9374cb680a0173c6498a4e13c718c602a355a8b6a50523f4816`
- AVD：`aitext_v161_publish_phone`，API 35，数据位于 E 盘
- 结构化结果：`E:\DevTools\Android\aitext-validation\phone-v1.6.1\published-result.json`，状态 `passed`

## 已执行检查

```powershell
git diff --check
```

结果：通过，无输出。

对 `README.md`、`RM_HANDOFF.md`、`docs/secretary-activity-contract.md` 和 `docs/phone-preview-validation-contract.md` 的本地 Markdown 目标做相对路径解析：4 个文件全部有效。

从合同提取 1 个 `json` 示例并执行 PowerShell `ConvertFrom-Json`：通过。
