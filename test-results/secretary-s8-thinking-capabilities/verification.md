# S8 Thinking mode 与联网能力边界验证

- 日期：2026-10-20（Asia/Singapore）
- 改动：`deepseek-flash` + 官方 DeepSeek API host 声明支持 thinking；thinking 默认关闭，可在对话 composer 中启用，高级能力设置可覆盖声明；开启时发 `thinking.type=enabled` / `reasoning_effort=high`，关闭时在已知 DeepSeek 接口显式发 `disabled`。流式 `reasoning_content` 不进入用户正文；assistant/tool transcript 及必要隐藏推理保存在本端会话 SQLite v5 并回传。当前 Chat Completions 不支持内置联网搜索，联网入口保持禁用。
- 执行：从 `app/` 运行 `E:\DevTools\Flutter\bin\flutter.bat test test/model_capabilities_test.dart test/settings_service_test.dart test/settings_page_test.dart test/model_client_stream_test.dart test/chat_service_tools_test.dart test/conversation_workspace_test.dart test/conversation_store_test.dart test/sqlite_migration_coordinator_test.dart test/secretary_conversation_ui_test.dart test/app_runtime_test.dart --reporter compact`。
- 结果：通过，37/37。覆盖端点/模型能力判定、用户覆盖、thinking 开/关参数、reasoning 与多轮工具协议回传、隐藏内容不进入 assistant 正文、SQLite transcript 持久化/v1 迁移、权限界面开关状态和启动装配。
- 执行：对 22 个关联 Dart 源码/测试文件运行 `dart analyze`，无问题；`dart format` 最终零差异。
- 技术依据：核对官方 [Thinking Mode](https://api-docs.deepseek.com/guides/thinking_mode/) 对 `thinking`/`reasoning_effort` 与工具回合必需 reasoning 回传的说明；[Chat Completions API](https://api-docs.deepseek.com/api/create-chat-completion/) 未声明 server-side web search；独立 Search/Fetch 使用独立 endpoints，Responses API 属另一协议。相关边界见[模型接入说明](../../docs/model-integration.md)。
- 未执行：真实模型 Key、真实 reasoning/tool 调用、计费/响应时延、独立云搜索、Android/Windows 设备和新功能 100 例；未执行全项目全量测试。
