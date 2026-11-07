# v1.3.0 Android 手机发布验证

日期：2026-11-08，Asia/Singapore。

## 结论

Android 手机发布候选版本为 `1.3.0+10`。最终运行时代码清单为 182 项：

`f9c8c219edb3218bb21b96d5225d2257fc8042bb0d2f101f5170537740cfde50`

手机定向回归、静态分析、格式门和新增“最近任务划掉”设备场景均通过。GitHub Android Release 已发布，公开 APK 已完成下载、哈希、签名、版本、SDK 和权限复核。

首轮 Android Release run `42403556704` 在 tag 校验失败：工作流错误查找 `docs/releases/1.3.0.md`，实际发行说明为 `docs/releases/v1.3.0.md`。该轮未安装签名密钥、未构建 APK、未创建 Release；修复后移动同一标签重跑。

## GitHub 发布

- Release：`https://github.com/YuanFangCH/personal-ai-inbox/releases/tag/phone-v1.3.0`
- 发布属性：pre-release
- Main CI：run `42403931513`，success
- Android Release：run `42403946155`，job `128497527923`，success
- 发布提交：`11de92600c5cac25bb1a5b5b7b494d74da6578f1`
- APK：`personal-ai-inbox-v1.3.0-android.apk`
- APK 大小：90,731,435 bytes
- APK SHA-256：`a81c32f7382d194e42151a9ba59816ddaf9a3e91fdc417cb3afe4b95c9754fbb`
- `SHA256SUMS.txt` 内容与本地重新计算的 APK 哈希一致。
- APK：`versionCode=10`、`versionName=1.3.0`、minSdk 24、targetSdk 36。
- 必要权限：`INTERNET`、`POST_NOTIFICATIONS`、`FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_DATA_SYNC`、`WAKE_LOCK` 均存在。
- `apksigner verify`：通过，v2 signed；证书 SHA-256 为 `51b5e2f3f44ce9374cb680a0173c6498a4e13c718c602a355a8b6a50523f4816`。

## 主机验证

命令：

```powershell
D:\Flutter-recovery-3.47.6\sdk\flutter\bin\dart.bat format --output=none --set-exit-if-changed lib test integration_test tool
D:\Flutter-recovery-3.47.6\sdk\flutter\bin\flutter.bat analyze --no-pub
D:\Flutter-recovery-3.47.6\sdk\flutter\bin\flutter.bat test --no-pub --reporter expanded `
  test/conversation_lifecycle_test.dart `
  test/conversation_large_history_ui_test.dart `
  test/secretary_conversation_ui_test.dart `
  test/app_background_lifecycle_test.dart `
  test/chat_service_tools_test.dart `
  test/table_ai_runtime_test.dart `
  test/table_action_processor_test.dart `
  test/table_migration_service_test.dart `
  test/table_migration_gate_test.dart `
  test/table_migration_io_test.dart `
  test/app_runtime_test.dart
```

结果：

- 格式：259 个文件，0 个变化，exit 0。
- `flutter analyze --no-pub`：No issues found，exit 0。
- 定向测试：68/68 通过，exit 0。完整输出见 `targeted-tests.log`。
- PowerShell AST：`scripts/run-secretary-agent-android-acceptance.ps1` 0 errors。
- `git diff --check`：通过，仅有既有 README/RM CRLF 提示。

## 设备验证

新增场景：`recents_swipe_recovery`。

- AVD：`aitext_agent_c_phone`
- Android：API 35
- Emulator：通过脚本读取并记录版本
- ADB：独立 server 5041
- Serial：`emulator-5620`
- Source manifest：`f9c8c219edb3218bb21b96d5225d2257fc8042bb0d2f101f5170537740cfde50`
- Integration Debug APK：`956d33fa4b85672dd706835c72f8e6384b6207115e32a281b2317a2060732dd0`，`versionName=1.3.0`、`versionCode=10`
- 结果：prepare 与 recovery 两阶段通过，`scenario_result=passed`，`cleanup_failures=none`
- 路径：`test-results/secretary-agent-implementation/luna-c/20261107T183122Z-phone-recents_swipe_recovery/`

场景通过真实最近任务界面滑动移除 app task，而不是调用不存在的 `am task remove`。冷启动后 15 秒内模型请求数不增加；显式继续传入原 task ID；原 operation 的幂等回执可重复出现，但每次均绑定同一 entry/table；表内最终只有一个对应 entry。

## 复用与边界

- 复用既有最终设备证据：phone 50/50、phone A31/A32/A33 和 900 秒长测；长测完成 47 条唯一写入与回执核对。
- 未执行全量测试。
- 本轮不补跑平板和 Windows UI，不构建新的 Windows 资产。
- A01–A30、A34–A35 的遗留主机组合延期。
- 未操作真实用户资料。
