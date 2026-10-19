# S4 有预算的本地检索验证

- 日期：2026-10-20（Asia/Singapore）
- 改动：成果/全局知识限定索引查询、Unicode 中文会话全文索引、单次检索预算与读权限门禁；索引 `user_version=6`，会话库 `user_version=3`。
- 执行：从 `app/` 运行 `E:\DevTools\Flutter\bin\flutter.bat test test/conversation_store_test.dart test/sqlite_index_database_test.dart test/sqlite_migration_coordinator_test.dart test/capture_workflow_test.dart test/result_repository_test.dart test/local_retrieval_test.dart --reporter compact`。
- 结果：通过，34/34。覆盖中文跨会话搜索、排除当前会话、SQLite v4 索引迁移、权限关闭零次外部查询、全局知识定向搜索、摘要/详情预算、重复请求去重和超限停止；包含 S3 审批回归。
- 执行：从 `app/` 运行 `E:\DevTools\Flutter\bin\cache\dart-sdk\bin\dart.exe analyze`，目标为此次变更的 17 个 Dart 源码与测试文件。
- 结果：通过，无问题。`dart format` 对同一组文件检查，格式化 3 个文件后最终格式稳定。
- 修复记录：首次本地检索验证发现 FTS5 内置 unicode61 对中文连续词的切分不足，改为在端内建立 CJK 字符索引；旧库夹具也改为真实模拟没有 FTS 表的 v2 状态。最终相关组全部通过。
- 未执行：模型工具/多轮 SSE 接线、对话 UI、真实模型/云盘、Android/Windows 设备和新功能 100 例；未执行全项目全量测试。
