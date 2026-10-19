# S3 全局知识审批核心验证

- 日期：2026-10-20（Asia/Singapore）
- 改动：全局知识范围/结构化事实元数据、候选状态 SQLite v5、摘要及目标版本绑定、确认后幂等提交；阻止普通保存/删除/撤销绕过审批。
- 执行：从 `app/` 运行 `E:\DevTools\Flutter\bin\flutter.bat test test/result_repository_test.dart test/sqlite_index_database_test.dart test/sqlite_migration_coordinator_test.dart test/capture_workflow_test.dart --reporter compact`。
- 结果：通过，29/29。覆盖新增、修改、删除确认；错误摘要、普通成果入口和撤销绕过拒绝；候选重启持久化、索引 v4→v5 迁移及现有捕获流程。
- 执行：从仓库根目录运行 `E:\DevTools\Flutter\bin\cache\dart-sdk\bin\dart.exe analyze app/lib/core/models.dart app/lib/data/index_database.dart app/lib/data/memory_index_database.dart app/lib/data/result_repository.dart app/lib/data/sqlite_index_database.dart app/lib/data/sqlite_migration_coordinator.dart app/lib/modules/results/result_library.dart app/test/result_repository_test.dart app/test/sqlite_index_database_test.dart app/test/sqlite_migration_coordinator_test.dart app/test/capture_workflow_test.dart`。
- 结果：通过，无问题。`dart format` 检查上述 11 个文件，零差异。
- 修复记录：首次测试发现防绕过撤销检查在写锁内重入 vault 锁；改为使用锁内读取后，完整定向组通过。
- 未执行：对话/设置 UI、模型工具、真实同步、Android/Windows 设备以及新功能 100 例；也未执行全项目测试。
