# ADR 索引

本系统与实现相关的、难以回退的决定记录在这里。每条 ADR 只回答“决定了什么”和“为什么”。

| 编号 | 决定 | 状态 |
|---|---|---|
| [0001](0001-cloud-drive-sync-no-custom-backend.md) | 成果同步走云盘，不自建集中式后端 | accepted |
| [0002](0002-one-markdown-per-result.md) | 一个成果一个 Markdown 文件 | accepted |
| [0003](0003-conflict-copies-and-tombstones.md) | 冲突保留副本，删除用墓碑 | accepted |
| [0004](0004-onedrive-bidirectional-baidu-one-way.md) | OneDrive 双向同步，百度网盘只做单向发布 | accepted |
| [0005](0005-three-hash-change-detection.md) | 用三项 hash 判断变更，时钟只用于破平局 | accepted |
| [0006](0006-matter-as-first-class-entity.md) | 事项是一等实体 | 新目标由 0020 取代，尚未迁移 |
| [0007](0007-links-one-sided-matter-declared-by-children.md) | 关联单边存储，归属由子项声明 | accepted |
| [0008](0008-flutter-for-three-clients.md) | 三端统一用 Flutter | accepted |
| [0009](0009-open-model-access.md) | 默认用 deepseek-flash，模型接入层保持开放 | accepted |
| [0010](0010-contextual-ai-conversation-and-guarded-auto-write.md) | AI 对话采用本地多会话，并授权高置信自动新增成果 | accepted |
| [0011](0011-mit-open-source-release.md) | 以 MIT 协议公开发布，并使用干净公开历史 | accepted |
| [0012](0012-github-release-artifacts-and-tag-workflow.md) | GitHub Release 作为首发渠道，并按标签自动构建 | accepted |
| [0013](0013-lazy-conversation-creation-and-merged-confirmation.md) | 会话按首次内容创建，确认入口合并到收件箱 | accepted |
| [0014](0014-modular-local-core-and-compatibility-migration.md) | 采用模块化本地核心，并以兼容 facade 分阶段迁移 | accepted |
| [0015](0015-recoverable-local-commits-and-idempotent-actions.md) | 本地持久化使用可恢复提交与幂等动作 | accepted |
| [0016](0016-sync-validation-and-version-bound-conflict-decisions.md) | 同步对象经过校验，冲突裁决绑定观察到的远端版本 | accepted |
| [0017](0017-conversation-permissions-and-reversible-result-actions.md) | AI 对话按会话授权读取及可撤销成果操作，独立待处理页方向由 0020 取代 | accepted（部分目标已更新） |
| [0018](0018-confirmed-global-knowledge-for-secretary.md) | 秘书型助理使用三端同步、按需检索且增改删均人工确认的全局知识（待实现） | accepted |
| [0019](0019-stable-android-release-signing.md) | Android 预览发布从 v1.1.4 起固定使用长期签名密钥 | accepted |
| [0020](0020-notebook-tables-and-content-permissions.md) | 以笔记式表组织内容，AI 表内内容操作免逐次确认、表结构在对话确认；取代事项与独立待处理页方向 | accepted（本地首轮实现；真实资料未迁移） |
| [0021](0021-table-storage-and-calendar-projection.md) | 表与条目是分离的稳定 Markdown 对象；首页和日历仅投影内容 | accepted（本地实现；跨端同步未接入） |
| [0022](0022-persistent-embedded-secretary-page.md) | 秘书作为应用内常驻页面，跨主页面切换保留会话界面状态 | accepted |
| [0023](0023-clean-migrated-legacy-sources.md) | 迁移后清理非全局旧源，保留校验备份及可续跑的完成凭据 | accepted |
| [0024](0024-secretary-agent-permissions-and-deduplication.md) | 专用秘书采用可恢复任务、可选应用内完全权限、可删除预置表与写前查重；完全权限下全局知识免逐项确认 | accepted（已进入 v1.3.0 Android 手机预发布；A01–A30、A34–A35 等剩余审计延期） |

相关文档：

- [可执行方案](../personal-ai-inbox-executable-plan.md)
- [成果同步协议](../sync-protocol.md)
- [术语表](../../CONTEXT.md)
- [表与笔记改版规划](../table-notebook-redesign-plan.md)：用户确认的规则与待定边界；当前进度见执行计划和 RM_HANDOFF。
- [表与内容数据契约](../table-data-contract.md)：本地 schema、归属、投影、回收站和迁移映射；不代表跨端同步格式已切换。
- [表交互契约](../table-interaction-contract.md)：页面文字稿、AI 工具输入/回执与 P0 样例走查。
