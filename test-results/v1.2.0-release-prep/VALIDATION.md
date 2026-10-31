# v1.2.0 发布准备验证

日期：2026-11-01（Asia/Singapore）

## 已执行

| 检查 | 结果 |
|---|---|
| `git status --short --branch` | 初始工作区干净；`main` 相对 `origin/main` 领先 25 个提交 |
| `git log --oneline origin/main..HEAD` | 25/25 个提交均属于表/笔记改版、AI 表内操作、旧事项迁移、迁移验证或秘书页嵌入范围 |
| `git config --get core.hooksPath` | `.githooks` 已启用 |
| `scripts/scan-public-release.ps1 -AllRefs` | 通过；未发现禁止发布路径或匹配的秘密模式 |
| 远端版本状态 | `origin/main` 仍为 `b8f1ba18c7af888080fcbbf79e3deda26cf301e0`；未发现 `v1.2.0` 标签或 Release |
| 应用版本 | `app/pubspec.yaml` 更新为 `1.2.0+8`；Android versionName/versionCode 分别由 Flutter 读取为 `1.2.0`/`8`，发布工作流会进一步验证 APK |
| 首轮 GitHub Actions | 运行 `41215153819` 在 `Check Dart formatting` 失败，定位到 `app/lib/ui/pages/global_knowledge_page.dart`；分析、测试和构建未开始，也未产生发布资产/Release |
| 格式修复 | 使用 Flutter 3.47.6 格式化上述文件后，完整 `dart format --output=none --set-exit-if-changed lib test integration_test tool` 检查通过 |
| 第二轮 GitHub Actions | Release `41215486744` 和 main CI `41215475349` 在全量测试阶段失败；格式与分析通过。主要失败是测试仍按旧的事项存储、离开秘书页即取消生成、旧筛选项与旧导航断言 |
| 回归修复 | AI 新建待办断言改查默认表内容；秘书离开期间回复预期完成；更新 Android/设备矩阵脚本和导航/筛选断言；迁移只读页改从模块边界 DTO 读取，修复架构检查的 UI→data 依赖 |
| 本地定向回归 | Flutter 3.47.6 下 Android UI 100、设备验收 100、秘书 100、秘书 smoke 和现实流程 smoke 共 328 项通过；SEC-054/085/089 三个发布失败场景单独重跑通过 |
| 静态检查与扫描 | `dart format --output=none --set-exit-if-changed lib test integration_test tool` 通过（220 files）；`flutter analyze` 无诊断；`scripts/scan-public-release.ps1 -AllRefs` 通过 |
| Release 状态 | `gh release view v1.2.0` 返回 release not found；无发布资产。标签仍指向旧 CI 修复提交 `112c2fd`；修复提交推送后需确认仍无 Release，再更新标签 |

## 未执行 / 未覆盖

- 回归修复尚未提交/推送；修复后的 GitHub 完整 Release 工作流尚未开始。
- 第二轮 CI 格式、分析已通过；第二轮全量测试失败。修复后的全量 CI、Android/Windows 发布构建尚未执行。
- Android APK 长期证书、Windows 安装包/便携包以及最终 SHA-256 尚未验证。
- Android 模拟器秘书页发送/切页/草稿与附件往返交互未完成；CI 结果不能替代该项。
- 未用真实用户资料执行旧事项迁移或覆盖升级。

## 发行范围与限制

25 个原始待发布提交均对应当前批准的 v1.2.0 范围。本版本要求升级前备份旧版应用数据和完整 Markdown 主库；跨设备表同步及通知尚未接入。发布准备提交为 `0d1a361`；此前 CI 格式修复提交为 `112c2fd`；修复后的回归调整尚未提交。目前 GitHub 无对应 Release。新修复提交完成后需确认无 Release，再将标签更新至新提交以重新触发工作流。
