# v1.2.0 发布准备验证

日期：2026-10-31（Asia/Singapore）

## 已执行

| 检查 | 结果 |
|---|---|
| `git status --short --branch` | 初始工作区干净；`main` 相对 `origin/main` 领先 25 个提交 |
| `git log --oneline origin/main..HEAD` | 25/25 个提交均属于表/笔记改版、AI 表内操作、旧事项迁移、迁移验证或秘书页嵌入范围 |
| `git config --get core.hooksPath` | `.githooks` 已启用 |
| `scripts/scan-public-release.ps1 -AllRefs` | 通过；未发现禁止发布路径或匹配的秘密模式 |
| 远端版本状态 | `origin/main` 仍为 `b8f1ba18c7af888080fcbbf79e3deda26cf301e0`；未发现 `v1.2.0` 标签或 Release |
| 应用版本 | `app/pubspec.yaml` 更新为 `1.2.0+8`；Android versionName/versionCode 分别由 Flutter 读取为 `1.2.0`/`8`，发布工作流会进一步验证 APK |

## 未执行 / 未覆盖

- 尚未提交发布准备变更、推送 main 或创建标签。
- GitHub Actions 全量格式、静态分析、测试和 Android/Windows 发布构建尚未执行。
- Android APK 长期证书、Windows 安装包/便携包以及最终 SHA-256 尚未验证。
- Android 模拟器秘书页发送/切页/草稿与附件往返交互未完成；CI 结果不能替代该项。
- 未用真实用户资料执行旧事项迁移或覆盖升级。

## 发行范围与限制

25 个待发布提交均对应当前批准的 v1.2.0 范围。本版本要求升级前备份旧版应用数据和完整 Markdown 主库；跨设备表同步及通知尚未接入。
