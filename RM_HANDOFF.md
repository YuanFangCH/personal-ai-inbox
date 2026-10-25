# RM 交接总文档

## 1. 文档状态

| 字段 | 当前值 |
|---|---|
| 项目名称 | 个人 AI 收件箱 |
| 当前分支 | `codex/maintainability-upgrade`，历史开发快照 |
| 当前发行 | GitHub 默认 `main` 上的发行版；本分支不作为发布来源 |
| 产品形态 | Android、Windows、Web 预览，统一使用 Flutter |

## 2. 一句话交接

这是个人 AI 收件箱的维护性开发分支；当前发布状态以默认 `main` 和 GitHub Releases 为准。

## 3. 当前目标与范围

- 本地 Markdown 是成果正文权威副本，SQLite 管理索引和运行状态。
- App 提供捕获、AI 对话、日历、事项、待办、知识和设置。
- 模型走 OpenAI 兼容 API；凭据使用系统安全存储。
- OneDrive、百度网盘和通知能力仍是后续产品工作。

## 4. 权威文件

- [AGENTS.md](AGENTS.md)：仓库协作和安全约定。
- [CONTEXT.md](CONTEXT.md)：术语。
- [可执行方案](docs/personal-ai-inbox-executable-plan.md)：产品与架构。
- [同步协议](docs/sync-protocol.md)：成果同步语义。
- [模型接入](docs/model-integration.md)：API 与凭据边界。
- [ADR 索引](docs/adr/README.md)：已接受的架构决定。

## 5. 已锁定决定

- 每个设备独立拥有本地核心，不依赖集中式后端。
- 同步只传确认后的成果，不传会话、原始素材或未确认候选。
- 模型只能提出工具请求；本地核心负责权限、成果写入和恢复语义。
- 当前分支代码可能落后于默认分支。新开发与发布应以默认 `main` 为准。

## 6. 当前进度与验证

本分支保留历史代码快照；产品状态、发行说明和当前协作规则以默认 `main` 为准。

## 7. 风险、阻塞与下一步

- 真实云端同步和本地通知尚未接入。
- Windows 包未代码签名。
- 后续维护应先同步默认 `main` 中的产品文档，再继续本分支代码。

