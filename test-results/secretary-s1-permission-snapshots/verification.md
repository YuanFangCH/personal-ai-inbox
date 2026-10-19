# S1：权限默认值与会话快照

日期：2026-10-20。改动：新增设置默认权限、每会话权限持久化，以及旧快照/旧会话数据库迁移；新增设置页控制。目标行为尚未接入模型工具。

## 验证

| 项目 | 命令 | 结果 |
|---|---|---|
| 格式 | `dart format` 对 S1 修改的 19 个 Dart 文件执行 | 通过，19 files formatted 0 changed |
| 定向测试 | `flutter test test/conversation_store_test.dart test/sqlite_migration_coordinator_test.dart test/settings_service_test.dart test/device_preferences_test.dart test/conversation_workspace_test.dart test/settings_page_test.dart --reporter compact`（在 `app/`） | 通过，27/27；包含 v1→v2 会话列迁移、跨索引/会话数据库启动协调、设置 v2→v3 兼容、便携设置兼容/往返/恢复默认、现有会话不随新默认改变、设置页保存行为 |
| 定向静态分析 | `dart analyze` 对 S1 生产文件与对应测试文件清单执行（在 `app/`） | 通过，No issues found |
| 差异空白 | `git diff --check` | 提交前执行，结果见最终检查 |

首轮编译发现 `AiPermissions` 类型未被两个 adapter 文件直接导入，已增加直接 import；设置页测试初版滚动到错误的嵌套滚动区域，已改用外层测试视口定位后加入最终通过运行。迁移协调测试也发现旧数据库夹具只把 `user_version` 改成 0 但没有删除新增列；夹具现先移除权限列，再验证真实旧结构升级。修正后上述最终 27 项通过。

## 未执行与边界

- 未执行全量测试、Android/Windows 设备测试、新 SEC-001–100 矩阵、真实模型、云盘或真实音频。
- 本次确立的是持久化与默认值行为，尚未让 `ChatService`/工具执行强制权限；不得把 S1 说成完整权限安全闭环。
- 设置数据库版本为 3，会话数据库为 2，成果索引版本仍为 3；真实用户目录恢复/断电未测。
