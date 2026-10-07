# 维护性升级方案

> 状态：第一阶段已实施
> 日期：2026-10-07
> 相关：[ADR 0014](../adr/0014-modular-local-core-and-compatibility-migration.md)

## 目标

把本地核心从单一应用控制器迁移为模块化深 module。每个 module 用较小 interface 隐藏复杂 implementation，让捕获、会话、成果存储、同步和端配置可以独立测试、替换和演进。

保留以下不变量：

- 一个成果一个 Markdown 文件，Markdown 是权威存储，SQLite 只做可重建索引和账本。
- 冲突永不静默覆盖，删除使用墓碑，AI 会话和原始素材不进入同步区。
- 自动记录只允许高置信新建，不能自动修改或删除已有成果。
- 三端对等，无集中式后端，模型和同步通过可替换 adapter 接入。

## 当前模块

| module | interface | 隐藏的 implementation |
|---|---|---|
| `DevicePreferences` | 不可变 `AppSettings`、`initialize`、`update`、密钥读写 | SharedPreferences、系统安全存储、默认值和迁移 |
| `ResultLibrary` | 不可变成果快照、创建/保存/删除/重建、候选成果 | Markdown 编解码、SQLite、revision、墓碑和派生列表 |
| `CaptureWorkflow` | 捕获、确认、拒绝、待确认快照 | 原文先落盘、规则/模型分析、失败恢复和待确认状态 |
| `ConversationWorkspace` | 会话、消息、发送、停止、重试、撤销 | 会话存储、附件、SSE、上下文裁剪、工具调用和自动记录 |
| `SyncWorkspace` | 同步报告、冲突列表、同步和裁决 | 三项 hash、provider、冲突副本和可见错误 |

`AppRuntime` 只负责组合和生命周期。当前 `AppController` 是迁移期兼容 facade，业务实现已退出该文件；UI 和既有测试迁移完成后应删除。

## 目录

```text
app/lib/
├─ bootstrap/      组合根
├─ domain/         纯领域失败契约
├─ modules/        端配置、成果库、捕获、会话、同步
├─ data/           Markdown、SQLite、provider 和 adapter
├─ services/       迁移期 facade 与模型/捕获适配
└─ ui/             shell、页面和拆分后的视图组件
```

UI 不得直接导入 `data/`、SQLite、Markdown 实现或同步实现。module 不得反向导入 UI 或 bootstrap。该规则由 `app/test/architecture_test.dart` 持续检查。

## 已实施

- 新增 `AppFailure`/`AppOperationException` 失败契约。
- 新增端配置、成果库、捕获、会话和同步 module 及各自测试。
- 应用控制器从约 1110 行降至约 427 行，业务写入统一委托 module。
- 对话自动记录经 `ResultLibrary` 写入，待确认项经 `CaptureWorkflow` 入队。
- 同步报告新增结构化 `SyncFailure` 列表。
- 日历视图、快速新建和对话页拆成小于约 350 行的内部组件。
- 新增架构依赖测试和模块契约测试。

## 后续阶段

1. 将首页、日历、知识、收件箱、设置和同步页逐页改读 module 快照。
2. 把同步决策、模型请求策略、上下文裁剪和自动记录准入抽为纯策略 module。
3. 把 `ModelClient` 提升为 OpenAI 兼容端口，并集中模型配置、能力表和图片出网策略。
4. 持续拆分剩余超过 500 行的生产文件，但以职责和变化轴为准，不做机械切分。
5. 引入配置/数据库 schema version 和迁移；把全量刷新改为增量快照，并为知识搜索补 FTS。
6. UI 迁移完成后删除 `AppController` 兼容 facade。

## 验证门禁

- `dart format --output=none --set-exit-if-changed lib test integration_test tool`
- `flutter analyze`
- `flutter test`
- Android release、Windows release、Web release 构建
- Windows 原生 integration smoke
- Android AVD/设备 smoke 与 Android UI 100 条矩阵
