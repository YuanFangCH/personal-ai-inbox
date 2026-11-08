# Flutter 原生无预算 Harness 验证

日期：2026-11-08  
范围：单 Agent 无累计任务预算、用量账本 v3、并行只读/写屏障、完全权限表工具、查重自动前进、恢复与状态 UI。

## 主机静态检查

- `dart analyze lib test integration_test`：通过，0 issue。
- `dart format --output=none --set-exit-if-changed <changed dart files>`：通过，25 文件，0 changed。
- `git diff --check`：通过；仅出现仓库既有 CRLF 转换提示。

## 主机定向测试

命令：

```powershell
flutter test --no-pub test/agent_tool_executor_test.dart test/agent_task_store_test.dart test/agent_task_status_card_test.dart test/agent_budget_file_recovery_test.dart test/chat_service_agent_test.dart test/conversation_workspace_scheduler_test.dart test/conversation_workspace_agent_runtime_test.dart test/content_intake_test.dart test/table_action_processor_test.dart test/model_duplicate_decision_source_test.dart test/table_ai_runtime_test.dart
```

结果：149/149 通过。

覆盖：

- 超过旧 240 次请求边界仍继续；记录超过 2 小时活动时长但不阻断。
- 重复工具调用在阈值只注入提醒，不硬暂停。
- 并行只读工具按上限执行、结果保序；写工具独占隔离。
- 完全权限暴露 `recovery_list`、`recovery_preview`、`recovery_restore`、`inbox_targets_read`，并放宽 revision/幂等键必填摩擦。
- 完全权限查重冲突新建独立条目并标记待核对；标准模式保持冲突询问。
- AgentTaskCheckpoint v1/v2 迁移到 v3，旧预算暂停任务重新排队，用量和恢复状态保留。
- 任务暂停/继续、后台生命周期、停止、重启恢复、写回执和上下文压缩失败路径。

## Android AVD

设备：`aitext_agent_c_phone`，Android 15 / API 35，serial `emulator-5620`，独立 ADB 5041。

命令：

```powershell
flutter test --no-pub -d emulator-5620 integration_test/table_ai_android_test.dart
```

结果：1/1 通过。覆盖 AI 表内写入、结构确认、日程创建与改期、删表和重启恢复。测试 fixture 已调整为真实 Harness 的“工具轮 → 最终答复”序列。

## 未执行

- 未运行全量测试，符合当前项目测试约定。
- 未运行平板 AVD、Windows 启动、真实模型 API、真实用户资料迁移、真实云同步或通知能力。
- 设备长测未重新执行；旧 900 秒长测证据属于上一提交，不用于证明本轮所有改动。
