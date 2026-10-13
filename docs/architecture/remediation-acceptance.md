# 架构整改验收清单

本清单按 2026-10-13 审查中的 F1–F12 逐项记录代码与测试证据。主机回归只使用合成数据/MockClient；真实 Key、用户 vault、云盘及通知未作为测试依赖。

| 发现 | 实施证据 | 定向证据 | 状态 / 未验证边界 |
|---|---|---|---|
| F1 图片总开关未进入请求边界 | `ModelRequestPolicy` 在请求构造前过滤所有历史/分享图片；能力和总开关分别限制图片 | `chat_flow_test.dart`、`model_request_policy_test.dart` | 已修复；未用真实模型 Key 联调 |
| F2 EOF 被视为完整响应 | SSE 只有 `[DONE]` 或有效 `stop/tool_calls` 才正常终结；取消、截断、超时和协议错误保持不完整 | `model_client_stream_test.dart`、`conversation_workspace_test.dart`、`chat_flow_test.dart` | 已修复；线上网关行为未实测 |
| F3 成果替换可能丢失权威文件 | 唯一暂存/恢复副本/提交日志、hash/revision 检查、跨进程锁和启动恢复；索引更新失败可重放日志 | `result_repository_test.dart`、`io_vault_store_test.dart` | 应用崩溃与注入 I/O 已测；未测物理断电和真实用户目录升级 |
| F4 工具 schema 宽松 | 自动记录严格校验类型、未知字段、日期顺序、置信度和 `sensitive`；只允许安全新增 | `chat_flow_test.dart`、`conversation_workspace_test.dart` | 已修复；不代表敏感内容识别能力 |
| F5 远端对象身份可错配 | 同步逐对象验证 ID、类型、canonical 状态、路径和重算 hash；写入使用 create-only/eTag 条件 | `sync_engine_test.dart`、`sync_workspace_test.dart` | 演练 Provider 已测；真实云盘尚未接入 |
| F6 冲突裁决不能收敛 | 冲突绑定本地 hash/远端 hash/eTag；裁决先重新核对版本，成功后才推进基线；相同远端冲突去重 | `sync_engine_test.dart`、`sync_workspace_test.dart` | 两类裁决与过期决定已测；远端条件竞争只由确定性 Provider 模拟 |
| F7 同步与可见快照分离 | 远端导入通过成果仓库提交；同步后 `ResultLibrary` 快照刷新，页面按所属模块订阅 | `sync_workspace_test.dart`、`result_library_test.dart`、`architecture_test.dart` | 已修复；多进程同时运行同一 vault 的 UI 行为未做设备测量 |
| F8 恢复与命令幂等不足 | SQLite `actions` 和 `generation_runs` 持久化稳定键、目标 ID、完整响应及阶段；未完成网络请求改为手动重试 | `result_repository_test.dart`、`conversation_workspace_test.dart`、`sqlite_index_database_test.dart` | 合成故障/重启路径已测；真实数据升级仍未演练 |
| F9 模块边界与依赖门禁不足 | 生产入口改为 `AppRuntime`；UI 不导入存储或 `AppController`；领域模型不依赖 Flutter；按页面监听模块快照 | `architecture_test.dart`（含违规负例与模块环检测） | 已修复主要 UI/root 边界；模块到具体 data adapter 的接口抽象仍可继续深化 |
| F10 模型能力与配置生命周期不足 | 版本化完整设置快照、用户能力覆盖、未知模型仅文本、配置校验、Key 安全槽切换、便携设置和固定文本连接测试 | `settings_service_test.dart`、`device_preferences_test.dart`、`model_capabilities_test.dart`、`chat_connection_test.dart`、`settings_page_test.dart` | MockClient/内存安全存储已测；真实 Key 网络诊断未执行 |
| F11 migration、诊断和大库读取不足 | SQLite 索引 v3/会话库 v1；Markdown schema 版本及未知字段往返；重建按路径报告并排除重复 ID；查询按更新时间/ID 分页 50 项 | `sqlite_migration_coordinator_test.dart`、`markdown_codec_test.dart`、`result_repository_test.dart`、`incremental_search_test.dart` | 10k 合成成果只读当前 50 个文件；未实施向量/FTS，外部文件扫描可手动触发，前台自动扫描未接入 |
| F12 静态门禁与工具链漂移 | CI/Release/PowerShell 断言 Flutter 3.47.6 / Dart 3.13.5；阶段 F 格式检查和 `flutter analyze` 通过 | `scripts/assert-flutter-version.ps1`、阶段 F 定向验证 | 已修复；阶段 F 只运行受影响测试，未重跑全量套件；Web/Windows/Android release 构建已通过 |

## 阶段 F 定向验收

阶段 F 修改后只运行受影响的设置、模型策略/连接、请求流和设置页测试，不重跑全量测试。10 个受影响测试文件 59 项通过，另有 AppRuntime 与 SQLite migration 两个直接相关测试文件 5 项通过。完整主机套件的最近一次全量结果是阶段 E 的 339/339；不能将其写成阶段 F 的全量验收。Web、Windows、Android release 构建及 Windows 冒烟通过；Android AVD 因当前没有连接设备未运行。最终格式检查、静态分析及受影响测试的命令/结果记录在 `RM_HANDOFF.md`。
