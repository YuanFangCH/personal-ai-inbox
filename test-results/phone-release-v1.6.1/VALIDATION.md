# Android 手机 v1.6.1 验收与发布

日期：2026-11-12（Asia/Singapore）

## 当前结论

- 合同：已冻结于 `docs/phone-preview-validation-contract.md`。
- 代码状态：秘书运行活动和浅蓝主题实现提交为 `5d763d7`；`1.6.1+15` 发布准备已写入工作区并完成 E 盘 Android 候选验收。
- 发布状态：`phone-v1.6.1` 标签和 GitHub Release 尚不存在。

## 执行记录

| 检查 | 状态 | 说明 |
|---|---|---|
| 合同静态核对 | passed | 4 个相关 Markdown 文件相对链接全部解析；JSON 示例通过解析；`git diff --check` 通过 |
| E 盘 AVD 候选验收 | passed | `aitext_v161_phone` / API 35 / `emulator-5620`；完成、停止、失败、主题和宽屏 4/4 |
| 定向主机测试 | passed | 活动/服务/秘书/大历史 38/38；任务卡与相关秘书 UI 8/8 |
| 全库静态检查 | passed | 293 文件格式 0 change；`flutter analyze --no-pub` 0 issue |
| main CI | not executed | 发布准备尚未提交 |
| GitHub Android Release | not executed | 尚未打标签 |
| 公开 APK 复核 | not executed | 尚无公开资产 |
| `v1.6.0` 到 `v1.6.1` 覆盖升级 | not executed | 等待公开包 |

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

## 已执行检查

```powershell
git diff --check
```

结果：通过，无输出。

对 `README.md`、`RM_HANDOFF.md`、`docs/secretary-activity-contract.md` 和 `docs/phone-preview-validation-contract.md` 的本地 Markdown 目标做相对路径解析：4 个文件全部有效。

从合同提取 1 个 `json` 示例并执行 PowerShell `ConvertFrom-Json`：通过。
