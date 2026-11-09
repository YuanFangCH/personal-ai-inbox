# 完全体模式验证记录

日期：2026-11-09

## 范围

- 设置快照 v6、可移植设置 v2、会话库 v7 与迁移兼容。
- 设置页完全体模式即时开关、现有/新会话全局覆盖、关闭后策略恢复。
- 会话权限面板锁定、控制面保护、整段会话/附件回收站。
- 输出长度续写、瞬时故障超过标准重试上限、本地检索无累计调用边界。
- 安全启动检查点自动续跑、文件/压缩包/图片输入无固定应用上限。

## 执行命令

```powershell
cd D:\Dsk\aitext\app
flutter analyze --no-pub
flutter test --no-pub `
  test/settings_service_test.dart `
  test/settings_page_test.dart `
  test/device_preferences_test.dart `
  test/ai_policy_test.dart `
  test/conversation_store_test.dart `
  test/conversation_permission_sheet_test.dart `
  test/full_agent_recovery_test.dart `
  test/full_agent_retry_test.dart `
  test/file_input_service_test.dart `
  test/chat_repository_trash_test.dart `
  test/model_client_stream_test.dart `
  test/local_retrieval_test.dart `
  test/retrieval_pagination_test.dart `
  test/sqlite_migration_coordinator_test.dart `
  test/chat_service_agent_test.dart `
  test/chat_service_tools_test.dart `
  test/agent_tool_executor_test.dart `
  test/conversation_workspace_agent_runtime_test.dart `
  test/conversation_workspace_scheduler_test.dart `
  test/agent_context_manager_test.dart
flutter test -d emulator-5620 integration_test/full_agent_android_test.dart --no-pub
```

## 结果

- `flutter analyze --no-pub`：通过，0 issue。
- 主机定向测试：179/179 通过；原始输出见 `final-tests.log`。
- Android AVD：`emulator-5620`，`aitext_agent_c_phone`，Debug APK 构建、安装、完全体模式开关启用/关闭及会话策略恢复 1/1 通过。
- Android AVD 原始输出见 `android-avd.log`。
- Android 构建提示 `flutter_tts` 的 Kotlin Gradle Plugin 未来兼容警告和 SDK XML 版本提示；不影响本次构建与测试结果。

## 未覆盖

- 未执行全量 Flutter 测试。
- 未连接真实模型密钥，未验证供应商额度、真实 429 或真实网络恢复。
- 未执行 Windows、平板、物理 Android 设备或强制停止/重启后的真机自动续跑。
- 完全体模式不解除模型上下文/输出硬限额、磁盘、网络和系统生命周期限制。
