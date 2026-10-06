# ADR 索引

本系统与实现相关的、难以回退的决定记录在这里。每条 ADR 只回答“决定了什么”和“为什么”。

| 编号 | 决定 | 状态 |
|---|---|---|
| [0001](0001-cloud-drive-sync-no-custom-backend.md) | 成果同步走云盘，不自建集中式后端 | accepted |
| [0002](0002-one-markdown-per-result.md) | 一个成果一个 Markdown 文件 | accepted |
| [0003](0003-conflict-copies-and-tombstones.md) | 冲突保留副本，删除用墓碑 | accepted |
| [0004](0004-onedrive-bidirectional-baidu-one-way.md) | OneDrive 双向同步，百度网盘只做单向发布 | accepted |
| [0005](0005-three-hash-change-detection.md) | 用三项 hash 判断变更，时钟只用于破平局 | accepted |
| [0006](0006-matter-as-first-class-entity.md) | 事项是一等实体 | accepted |
| [0007](0007-links-one-sided-matter-declared-by-children.md) | 关联单边存储，归属由子项声明 | accepted |
| [0008](0008-flutter-for-three-clients.md) | 三端统一用 Flutter | accepted |
| [0009](0009-open-model-access.md) | 默认用 deepseek-flash，模型接入层保持开放 | accepted |
| [0010](0010-contextual-ai-conversation-and-guarded-auto-write.md) | AI 对话采用本地多会话，并授权高置信自动新增成果 | accepted |
| [0011](0011-mit-open-source-release.md) | 以 MIT 协议公开发布，并使用干净公开历史 | accepted |
| [0012](0012-github-release-artifacts-and-tag-workflow.md) | GitHub Release 作为首发渠道，并按标签自动构建 | accepted |

相关文档：

- [可执行方案](../personal-ai-inbox-executable-plan.md)
- [成果同步协议](../sync-protocol.md)
- [术语表](../../CONTEXT.md)
