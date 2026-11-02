# 秘书真实模型工具名修复验证

日期：2026-11-02  
范围：Android 真机 `REA-AN00`、秘书表模式、DeepSeek OpenAI 兼容 Chat Completions。

## 故障与根因

- 现象：秘书发送“你好”等普通消息稳定显示 `Model chat request failed with HTTP 400`；设置页连接诊断成功返回 `connection-ok`。
- 原始服务端错误：`Invalid 'tools[0].function.name': string does not match pattern. Expected a string that matches the pattern '^[a-zA-Z0-9_-]+$'`。
- 根因：表工具函数名含点号，例如 `table.search`、`content.search`、`content.create`。模型、端点和 Key 均正常，只有附带工具定义的完整聊天请求被拒绝。

## 修复

- 发往模型的 12 个表工具函数名改为 `table_search`、`content_create` 等合法下划线名称。
- 本地仍映射回原 `table.search`、`content.create` 等操作名；已持久化操作卡、历史会话和动作处理不迁移。
- 历史工具 transcript 中的旧点号名称在再次发送给模型前同样转换为下划线。
- 增加断言：所有实际声明的工具函数名必须匹配 `^[a-zA-Z0-9_-]+$`。

## 验证

| 检查 | 结果 |
|---|---|
| `flutter test --no-pub test/chat_service_tools_test.dart test/table_ai_runtime_test.dart test/table_action_processor_test.dart` | 13/13 通过 |
| `dart analyze`（聊天服务、两个定向测试、Android 表 AI 集成用例、真实场景 runner） | 无诊断 |
| `dart format --output=none --set-exit-if-changed` 对应改动范围 | 通过 |
| 同长期证书签名 release APK | 构建成功；v2 验签通过，证书 SHA-256 `51b5e2f3f44ce9374cb680a0173c6498a4e13c718c602a355a8b6a50523f4816` |
| APK SHA-256 | `8B9F21665DEEEE09065E9D46FB94E88434AEB4E9B0E42249837B1E86B2A8B26D` |
| Android 覆盖安装与真实会话复验 | 未执行：构建期间无线调试连接变为 `offline`，原端口已失效 |

## 未覆盖

- APK 尚未覆盖安装到真机，因此尚未在设备上确认修复后的真实多轮工具回复。
- 真机设置页在排障中临时改为回环代理地址；恢复无线调试后必须覆盖安装新 APK，并把 Base URL 恢复为 `https://api.deepseek.com`。
- 未运行全量测试、其他设备或云同步验证。
