# 个人 AI 信息收集系统调研：收集入口与知识库

> 调研日期：2026-10-03（Asia/Hong_Kong）
>
> 证据口径：优先使用项目官网、官方文档、GitHub 仓库、README、源码与 GitHub API。动态数据来自 2026-10-03 的 GitHub API 查询，后续会变化。
>
> 标记方式：`已验证事实`表示可由官方页面或当前仓库直接确认；`判断/建议`表示面向本项目的工程判断，不是项目官方承诺。

> **适用范围说明**：本文撰写于 v1.0 的“服务器中心”架构。v2.1 已改为三端独立 App + 云端大模型 API + Markdown 为主 + 只同步最终成果，结论请以 [个人 AI 收件箱与提醒系统：可执行方案](../personal-ai-inbox-executable-plan.md) 为准；本文的官方资料与能力边界仍然有效。

## 1. 执行摘要

`已验证事实`

- 没有单一候选同时做好“多端极速采集、知识/事项分流、图片 OCR、长期知识编辑、语义检索、自动报告、低运维”全部环节。
- Memos、Karakeep、AnythingLLM Mobile 最接近手机端采集入口。
- Obsidian、Joplin、Logseq 最接近个人长期知识库；其中 Joplin 近期的内置语义检索与 MCP 能力增长最快。
- Dify、RAGFlow、AnythingLLM、Khoj 更接近 AI 工作流、RAG 或自动报告层，而不是原始采集入口。
- Weaviate、Qdrant、Milvus 只是索引基础设施，不提供采集 UI、OCR、知识编辑或报告工作流。

`判断/建议`

- 推荐将系统拆成四层：`采集入口 -> 分流编排 -> 知识存储 -> 检索/报告`。
- 最稳妥的个人架构是“专用采集入口 + Markdown/Joplin 作为可迁移主库 + 外部 RAG/工作流服务”的混合方案。
- 若不希望维护大量服务，优先组合是：`Memos 或 AnythingLLM Mobile 采集 + Joplin 主库/OCR/语义检索 + Dify 做分流与报告`。
- 若更强调数据主权和长期可迁移性，优先组合是：`Memos/Karakeep 采集 + Obsidian Markdown 主库 + Qdrant 索引 + Dify 编排`。
- 不建议把 AppFlowy 自托管作为当前核心：其活动服务器已转向商业闭源发行版，操作和数据路径都更重。
- Khoj 的产品形态很贴合“第二大脑 + 自动报告”，但截至 2026-10-03 的仓库活跃度明显低于主流候选，不宜作为唯一关键路径。

## 2. 动态事实与方法

采集工具与规则：

- 仓库元数据、最近 push、最近 release：GitHub REST API。
- 许可证：GitHub API `license.spdx_id`，对 `NOASSERTION` 项目继续读取仓库 `LICENSE`。
- 功能、移动端、导入、API、部署：项目 README、官网和官方文档。
- GitHub stars 只作为生态活跃度的弱信号，不作为质量结论。

### 2.1 候选项目当前状态

| 项目 | 许可证 | 最近 push（UTC） | 最近 release | Stars | 主要层级 |
|---|---|---:|---|---:|---|
| [Obsidian](https://github.com/obsidianmd/obsidian-releases) | 闭源专有；客户端免费 | 2026-10-03 | [1.13.8](https://github.com/obsidianmd/obsidian-releases/releases/tag/v1.13.8)，2026-08-21 | 21,974 | Markdown 知识库与编辑层 |
| [Logseq](https://github.com/logseq/logseq) | AGPL-3.0 | 2026-10-03 | [2.0.1 Beta Testing](https://github.com/logseq/logseq/releases/tag/2.0.1)，2026-07-13 | 45,116 | 大纲知识库、任务捕获 |
| [Joplin](https://github.com/laurent22/joplin) | 默认 AGPL-3.0-or-later；部分子目录另证 | 2026-10-03 | [3.7.21](https://github.com/laurent22/joplin/releases/tag/v3.7.21)，2026-09-25 | 56,571 | 跨端笔记、OCR、语义检索、MCP |
| [AppFlowy](https://github.com/AppFlowy-IO/AppFlowy) | 核心 AGPL-3.0；自托管服务器为商业闭源发行 | 2026-10-01 | [0.14.6](https://github.com/AppFlowy-IO/AppFlowy/releases/tag/0.14.6)，2026-10-01 | 77,088 | 团队协作工作区 |
| [Memos](https://github.com/usememos/memos) | MIT | 2026-10-02 | [0.31.0](https://github.com/usememos/memos/releases/tag/v0.31.0)，2026-09-19 | 63,481 | 轻量采集收件箱 |
| [Karakeep](https://github.com/karakeep-app/karakeep) | AGPL-3.0 | 2026-09-29 | [0.33.2](https://github.com/karakeep-app/karakeep/releases/tag/v0.33.2)，2026-08-11 | 29,396 | 链接/图片/截图采集与 AI 标签 |
| [Paperless-ngx](https://github.com/paperless-ngx/paperless-ngx) | GPL-3.0 | 2026-10-03 | [3.2.1](https://github.com/paperless-ngx/paperless-ngx/releases/tag/v3.2.1)，2026-09-20 | 46,243 | 文档与截图归档、OCR |
| [AnythingLLM](https://github.com/Mintplex-Labs/anything-llm) | 主项目 MIT；Android 客户端 GPL-3.0 | 2026-10-03 | [1.17.0](https://github.com/Mintplex-Labs/anything-llm/releases/tag/v1.17.0)，2026-10-01 | 66,684 | 本地 RAG、Agent、手机采集 |
| [Khoj](https://github.com/khoj-ai/khoj) | AGPL-3.0 | 2026-08-02 | [2.0.0-beta.28](https://github.com/khoj-ai/khoj/releases/tag/2.0.0-beta.28)，2026-03-26 | 37,556 | 第二大脑、检索、自动报告 |
| [RAGFlow](https://github.com/infiniflow/ragflow) | Apache-2.0 | 2026-10-03 | [1.0.0-rc1](https://github.com/infiniflow/ragflow/releases/tag/v1.0.0-rc1)，2026-09-29 | 91,619 | 文档解析、RAG、Agent |
| [Open WebUI](https://github.com/open-webui/open-webui) | Open WebUI License，含品牌保留限制 | 2026-10-02 | [0.11.4](https://github.com/open-webui/open-webui/releases/tag/v0.11.4)，2026-09-21 | 153,851 | AI 工作台、知识库聊天 |
| [Dify](https://github.com/langgenius/dify) | 修改版 Apache 2.0，含多租户/logo 限制 | 2026-10-03 | [1.17.1](https://github.com/langgenius/dify/releases/tag/1.17.1)，2026-09-10 | 157,756 | 工作流编排、知识库、报告 |
| [Weaviate](https://github.com/weaviate/weaviate) | BSD-3-Clause + `wl/` 企业许可证 | 2026-10-02 | [1.39.8](https://github.com/weaviate/weaviate/releases/tag/v1.39.8)，2026-10-01 | 16,861 | 向量/混合检索基础设施 |
| [Qdrant](https://github.com/qdrant/qdrant) | Apache-2.0 | 2026-10-03 | [1.19.1](https://github.com/qdrant/qdrant/releases/tag/v1.19.1)，2026-09-04 | 34,908 | 向量/混合检索基础设施 |
| [Milvus](https://github.com/milvus-io/milvus) | Apache-2.0 | 2026-10-02 | [3.0.2](https://github.com/milvus-io/milvus/releases/tag/v3.0.2)，2026-09-20 | 46,310 | 可扩展向量数据库 |
| [SiYuan](https://github.com/siyuan-note/siyuan) | AGPL-3.0 | 2026-10-03 | [3.8.6](https://github.com/siyuan-note/siyuan/releases/tag/v3.8.6)，2026-09-29 | 46,618 | 本地优先知识工作区 |
| [TriliumNext](https://github.com/TriliumNext/Trilium) | AGPL-3.0 | 2026-10-03 | [0.106.0](https://github.com/TriliumNext/Trilium/releases/tag/v0.106.0)，2026-09-25 | 38,184 | 层级知识库 |
| [SilverBullet](https://github.com/silverbulletmd/silverbullet) | MIT | 2026-10-03 | [2.11.1](https://github.com/silverbulletmd/silverbullet/releases/tag/2.11.1)，2026-09-22 | 6,202 | Markdown + Lua 可编程笔记 |

### 2.2 面向本项目的快速矩阵

评分含义：`高`表示能直接满足大部分需求，`中`表示需要组合或二次开发，`低`表示只适合作为组件。

| 项目 | 手机文本采集 | 截图/图片导入 | OCR/视觉理解 | API/自动化 | RAG/报告 | 运维复杂度 |
|---|---|---|---|---|---|---|
| Obsidian | 中 | 中 | 低，需插件 | 中，URI/插件/文件系统 | 中，需外部索引 | 低 |
| Logseq | 中 | 中 | 低 | 中，插件/CLI/HTTP 生态 | 中 | 低到中 |
| Joplin | 高 | 高 | 高，桌面 OCR | 高，Data API/MCP | 高，语义搜索 + 外部 AI | 低 |
| AppFlowy | 高 | 高 | 中 | 中 | 中 | 中到高 |
| Memos | 高 | 高 | 中，可配 AI 转录 | 高，REST/gRPC/Webhooks/MCP | 低到中，无内置向量检索 | 低 |
| Karakeep | 高 | 高 | 高，OCR + AI 标签 | 高，REST/MCP/CLI | 高，全文/语义检索和摘要 | 中 |
| Paperless-ngx | 中 | 高 | 高，OCR | 高，REST/Workflows/Webhooks | 中到高，文档 AI | 中到高 |
| AnythingLLM | 高，Android | 高 | 高，视觉模型 | 高，Developer API/Agent | 高 | 低到中 |
| Khoj | 中到高，PWA/WhatsApp | 高 | 中到高 | 中，客户端与自动化 | 高，含邮件报告 | 中 |
| RAGFlow | 低，无原生移动端 | 高 | 高，DeepDoc/OCR | 高，HTTP/Python API | 很高，含知识编译 | 高 |
| Open WebUI | 中，PWA | 高 | 中到高 | 高，API/插件/Knowledge Sync | 高 | 低到中 |
| Dify | 低，无原生移动端 | 高 | 中到高 | 很高，Workflow/API/Webhook | 很高 | 中 |
| Weaviate | 无 | 无 | 无 | 高 | 仅检索 | 中 |
| Qdrant | 无 | 无 | 无 | 高 | 仅检索 | 低到中 |
| Milvus | 无 | 无 | 无 | 高 | 仅检索 | 中到高 |

## 3. 候选项目逐项比较

### 3.1 Obsidian

`已验证事实`

- 定位：本地 Markdown 知识库、编辑器、插件生态和跨端客户端。官方 README 明确说明该仓库不包含 Obsidian 源码，Obsidian 不是开源软件。[官方 README](https://github.com/obsidianmd/obsidian-releases)
- 许可证：闭源专有。官网称个人、商业和非营利均可免费使用，商业许可证为可选支持项；Sync/Publish 为可选付费服务。[官方许可证说明](https://obsidian.md/license)
- 活跃度：发布仓库最近 push 为 2026-10-03，最近正式版为 1.13.8，发布日期 2026-08-21。[GitHub Releases](https://github.com/obsidianmd/obsidian-releases/releases)
- 部署复杂度：客户端极低。同步可选择官方 Sync、Dropbox、OneDrive、Git、Syncthing 等；官方 Sync 是付费服务。[数据存储文档](https://obsidian.md/help/data-storage) [官方 Sync](https://obsidian.md/sync)
- 文本/图片导入：原生 Markdown 文件、附件和图片；支持拖放文件或文件夹，官方 Importer 可导入 Markdown、ZIP 等。[Markdown 导入](https://obsidian.md/help/import/markdown)
- 手机端：官方 Android 应用支持 Android 5.1+、设备存储、Widgets、Quick Settings 和快捷入口。官方 Android 文档没有给出“从系统分享菜单直接发截图到 Obsidian”的同等原生工作流。[Android 说明](https://obsidian.md/help/android) [移动端说明](https://obsidian.md/help/mobile)
- API/插件：官方提供插件 API 和 Obsidian URI，可执行打开、创建、追加、搜索、Daily Note 等动作。[开发者文档](https://docs.obsidian.md) [Obsidian URI](https://obsidian.md/help/uri)

`判断/建议`

- 检索/自动报告适配：本身擅长知识编辑、双向链接和本地文件管理，不是完整采集或报告服务。通用 HTTP API 不是核心一等能力，通常需要 Local REST API 社区插件、文件监听器或外部服务补齐。
- 明显缺点：闭源；官方 Sync 付费；手机截图入站和 AI 自动化依赖插件或外部编排；图片不会由 Web Clipper 自动下载，需要后续处理。[官方 Web Clipper](https://obsidian.md/help/web-clipper/capture)
- 适合层级：最适合作为长期 Markdown 主库和人工编辑界面，不适合作为采集网关或 RAG 引擎。

### 3.2 Logseq

`已验证事实`

- 定位：隐私优先、本地优先的知识管理与协作平台，支持 Markdown、Org-mode、PDF 标注和任务管理。[官方 README](https://github.com/logseq/logseq)
- 许可证：AGPL-3.0。[GitHub API](https://github.com/logseq/logseq)
- 活跃度：最近 push 为 2026-10-03，最近 release 为 2.0.1，发布名称仍包含 Beta Testing。[Release](https://github.com/logseq/logseq/releases/tag/2.0.1)
- 重要状态：DB 版本处于 beta；新的移动端和 RTC 同步处于 alpha。官方 README 明确警告 DB 版本可能发生数据丢失，并建议先用于非关键项目。[官方 README](https://github.com/logseq/logseq)
- 部署复杂度：文件图模式较低。同步为付费功能，也可自托管；DB 版本的 CLI 已包含登录、同步、图导入导出和备份命令。[DB 版本说明](https://github.com/logseq/docs/blob/master/db-version.md) [CLI 文档](https://github.com/logseq/logseq/blob/master/docs/cli/logseq-cli.md)
- 文本/图片导入：支持 Markdown 和 Org-mode 文件图；DB 版本仅支持 Markdown，Org-mode 不再支持。PDF 标注和图片是核心笔记内容。
- 手机端：旧版移动应用可访问桌面端大部分功能；DB 版本的新 iOS 应用已开放 alpha，但官方 README 写明 Android 仍在准备中。[官方 README](https://github.com/logseq/logseq)
- API/插件：提供 JS/CLJS Plugin API；CLI 支持按块插入 Markdown、搜索页面、标签和属性；部分社区工具使用 HTTP API。[插件文档](https://plugins-doc.logseq.com/) [CLI 文档](https://github.com/logseq/logseq/blob/master/docs/cli/logseq-cli.md)

`判断/建议`

- 检索/自动报告适配：适合快速日志、任务和大纲式知识，但内置 AI/RAG 能力不是重点，需要外部索引或自动化。
- 明显缺点：DB 迁移期间数据模型和移动端存在断裂；Android 新客户端尚未开放；数据丢失警告对关键收集系统不可忽视。
- 适合层级：可作为个人大纲知识库或任务捕获前端，当前不建议作为唯一主库。

### 3.3 Joplin

`已验证事实`

- 定位：跨平台开源笔记与待办应用，支持 Windows、macOS、Linux、Android、iOS，SQLite 存储和 Markdown 笔记。[官方 README](https://github.com/laurent22/joplin)
- 许可证：仓库默认 AGPL-3.0-or-later，但子目录可带自己的 LICENSE；服务端等目录需要单独确认。[LICENSE](https://github.com/laurent22/joplin/blob/dev/LICENSE)
- 活跃度：最近 push 为 2026-10-03，最近 release 为 3.7.21，发布日期 2026-09-25。[Release](https://github.com/laurent22/joplin/releases/tag/v3.7.21)
- 部署复杂度：客户端开箱即用，支持 Joplin Cloud、WebDAV、Nextcloud、S3、OneDrive、Dropbox 等同步；自托管需要 Joplin Server 或兼容 WebDAV。[同步文档](https://joplinapp.org/help/apps/sync/)
- 文本/图片导入：支持 Markdown、ENEX、HTML 等导入，支持图片和附件。内置 OCR 可扫描 PNG、JPEG、PDF，适合清晰截图和打印文本，不支持手写。[OCR 文档](https://joplinapp.org/help/apps/ocr/)
- 手机端：官方 Android/iOS 应用可用。OCR 只在桌面处理，移动端通过同步读取 OCR 结果；Android 可手动安装插件，iOS 只允许推荐插件。[移动端说明](https://joplinapp.org/help/apps/mobile/) [插件说明](https://github.com/laurent22/joplin/blob/dev/readme/apps/plugins.md)
- API/插件：官方 Data API 提供 REST 接口，可创建、修改、删除笔记、笔记本、标签和附件；插件 API 可在桌面和移动端工作。[Data API](https://joplinapp.org/help/api/references/rest_api/)
- AI 能力：3.7 起支持本地 embeddings 语义搜索、AI Chat 面板和 MCP server。语义搜索在桌面运行，索引不跨设备同步；MCP 可向外部 AI 应用开放搜索、读取和可选写入工具。[语义搜索](https://joplinapp.org/help/apps/ai_semantic_search/) [MCP](https://joplinapp.org/help/apps/ai_mcp/)

`判断/建议`

- 检索/自动报告适配：当前候选中最完整的一体化开源方案之一。Joplin 可以承担采集、OCR、知识主库、语义检索和 MCP 网关，报告可由外部 Agent 或 Dify 完成。
- 明显缺点：AI Chat 面板默认只读当前笔记，不提供跨笔记上下文；跨笔记检索要走语义搜索或 MCP。语义索引每台设备各自构建，移动端不运行 embeddings。截图 OCR 依赖桌面端在线处理。
- 适合层级：强烈建议作为主库候选。适合承担 `知识存储 + OCR + 本地语义搜索 + MCP`，采集入口可由 Memos 或 AnythingLLM Mobile 补充。

### 3.4 AppFlowy

`已验证事实`

- 定位：AI 协作工作区、Notion 替代品，覆盖文档、数据库、任务、看板和团队协作。[官方 README](https://github.com/AppFlowy-IO/AppFlowy)
- 许可证：客户端和核心仓库为 AGPL-3.0；但活动自托管服务器已经转向 [AppFlowy-SelfHost-Commercial](https://github.com/AppFlowy-IO/AppFlowy-SelfHost-Commercial)，采用 AppFlowy Self-Hosted Commercial License。旧 [AppFlowy-Cloud](https://github.com/AppFlowy-IO/AppFlowy-Cloud) 已归档。[官方迁移说明](https://github.com/AppFlowy-IO/AppFlowy-Cloud)
- 活跃度：主仓库最近 push 为 2026-10-01，最近 release 为 0.14.6。商业自托管服务持续更新。[Release](https://github.com/AppFlowy-IO/AppFlowy/releases/tag/0.14.6)
- 部署复杂度：客户端低，官方自托管需要 Docker Compose 和多项服务。Free Tier 为单用户席位，其他功能与商业 tier 有关。[自托管仓库](https://github.com/AppFlowy-IO/AppFlowy-SelfHost-Commercial)
- 文本/图片导入：文档支持图片、文件、代码、公式等 20+ 内容类型；新版自托管支持 PDF/DOCX 导入和 Confluence ZIP 导入。[Google Play](https://play.google.com/store/apps/details?id=io.appflowy.appflowy) [商业自托管 README](https://github.com/AppFlowy-IO/AppFlowy-SelfHost-Commercial)
- 手机端：官方 Android 应用要求 Android 10+，支持离线、跨设备同步和 AppFlowy AI。[官方 README](https://github.com/AppFlowy-IO/AppFlowy)
- API/插件：商业服务器提供管理 API、搜索服务、MCP 数据库工具和 AI 配置；与社区版客户端的版本兼容需要按发布说明匹配。

`判断/建议`

- 检索/自动报告适配：搜索服务支持关键词和语义检索，AI Chat 可以引用工作区内容，但这是团队工作区能力，不是为个人“随手发消息”优化的采集系统。
- 明显缺点：最强自托管路径已转为商业闭源发行；部署和升级复杂；对单人知识收集属于明显过重。
- 适合层级：仅适合作为已经采用 AppFlowy 的协作知识前端，不建议作为本项目的核心采集或 RAG 层。

### 3.5 Memos

`已验证事实`

- 定位：轻量、自托管的个人时间线笔记，强调无标题、无目录的快速记录，Markdown、标签、图片和文件。[官方 README](https://github.com/usememos/memos)
- 许可证：MIT。[LICENSE](https://github.com/usememos/memos/blob/main/LICENSE)
- 活跃度：最近 push 为 2026-10-02，最近 release 为 0.31.0，发布日期 2026-09-19。[Release](https://github.com/usememos/memos/releases/tag/v0.31.0)
- 部署复杂度：低。官方提供单容器 Docker 启动；支持 SQLite、MySQL、PostgreSQL。[官方 README](https://github.com/usememos/memos)
- 文本/图片导入：Markdown、标签、图片、视频、音频、PDF 和普通附件；Web Clipper 可保存网页、选区和图片；编辑器支持录音频并在配置 AI provider 后转写。[Quick Capture](https://www.usememos.com/features/quick-capture) [Attachments](https://www.usememos.com/features/media-integration)
- 手机端：提供可安装 PWA，可添加到 Android 主屏；官方同时提供 Telegram 捕获集成 Memogram。[PWA](https://www.usememos.com/features/pwa-support) [Telegram 捕获](https://www.usememos.com/features/quick-capture)
- API/插件：官方 REST 和 gRPC API 覆盖全部功能；支持 Personal Access Token、Webhooks 和内置 MCP server。[API Access](https://www.usememos.com/docs/integrations/api-access) [Webhooks](https://www.usememos.com/docs/integrations/webhooks)
- 搜索：当前官方说明为 SQLite/MySQL/PostgreSQL 中的大小写不敏感文本匹配和 CEL 过滤，不宣称内置向量语义检索。[Search](https://www.usememos.com/features/universal-search)

`判断/建议`

- 检索/自动报告适配：采集入口极强，RAG 和报告能力弱。正适合作为“原始收件箱”，让 Dify 等外部服务消费。
- 明显缺点：没有内建向量检索、自动分流和报告；长期文档版本、复杂知识结构和双向链接能力弱于 Obsidian/Joplin。
- 适合层级：本项目的第一采集入口候选。建议用 Telegram/PWA/API 接住文本和截图，再通过 Webhook 触发分流。

### 3.6 Karakeep（原 Hoarder）

`已验证事实`

- 定位：自托管“收藏一切”应用，管理链接、文本笔记、图片和附件，带 AI 自动标签、全文和语义检索。[官方 README](https://github.com/karakeep-app/karakeep)
- 许可证：AGPL-3.0。[LICENSE](https://github.com/karakeep-app/karakeep/blob/main/LICENSE)
- 活跃度：最近 push 为 2026-09-29，最近 release 为 0.33.2，发布日期 2026-08-11。[Release](https://github.com/karakeep-app/karakeep/releases/tag/v0.33.2)
- 部署复杂度：中。官方 Docker Compose 包含应用、Chrome 抓取和 Meilisearch 等组件；AI 标签可选 OpenAI 或本地替代 provider。[Docker 安装](https://docs.karakeep.app/installation/docker)
- 文本/图片导入：支持链接、纯文本、图片/PDF asset；图片 OCR、全文与语义搜索、自动标签、网页归档和离线阅读。[官方 README](https://github.com/karakeep-app/karakeep)
- 手机端：官方 iOS 和 Android app，支持移动端离线阅读。[官方 README](https://github.com/karakeep-app/karakeep)
- API/插件：完整 REST API，支持创建和搜索书签、上传 asset、摘要；官方 MCP server 可供 Codex/Claude 等调用。[API](https://docs.karakeep.app/api/karakeep-api) [创建书签](https://docs.karakeep.app/api/create-bookmark) [MCP](https://docs.karakeep.app/integrations/mcp)
- 知识检索：支持全文检索、语义检索、查询语言和单条摘要。[Search API](https://docs.karakeep.app/api/search-bookmarks)

`判断/建议`

- 检索/自动报告适配：截图、链接和图片采集优于 Memos，OCR 和自动标签直接可用。自动报告仍需要 Dify、AnythingLLM 或其他 Agent。
- 明显缺点：本质是 read-it-later/收藏系统，不是长文编辑器和结构化笔记库；Docker Compose 组件比 Memos 多；AI provider 和 Meilisearch 会增加维护面。
- 适合层级：最适合作为“手机截图/链接采集入口 + OCR/标签预处理层”。可与 Markdown 主库或 RAGFlow 组合。

### 3.7 Paperless-ngx

`已验证事实`

- 定位：文档管理系统，将扫描件和 PDF 转为可搜索归档，强调文档、标签、correspondent、document type 和工作流。[官方 README](https://github.com/paperless-ngx/paperless-ngx)
- 许可证：GPL-3.0。[GitHub API](https://github.com/paperless-ngx/paperless-ngx)
- 活跃度：最近 push 为 2026-10-03，最近 release 为 3.2.1，发布日期 2026-09-20。[Release](https://github.com/paperless-ngx/paperless-ngx/releases/tag/v3.2.1)
- 部署复杂度：中到高。推荐 Docker Compose；当前支持 SQLite，但多用户/较高吞吐建议 PostgreSQL，Redis/Valkey 用于任务，Tika/Gotenberg 可选。[安装文档](https://docs.paperless-ngx.com/setup/)
- 文本/图片导入：consume 文件夹、Web UI 上传、邮件、REST API；默认 OCR，生成可归档 PDF/A，并用 OCR 文本参与搜索。[使用文档](https://docs.paperless-ngx.com/usage/)
- 手机端：官方没有第一方原生应用；官方文档指向第三方移动上传软件，也可通过 Web/API 使用。[移动上传](https://docs.paperless-ngx.com/usage/#mobile-upload)
- API/插件：完全文档化的 versioned REST API，支持上传、检索、批量编辑、权限和 webhook；Workflows 支持消费、增加、更新、定时触发和 webhook/email 动作。[API](https://docs.paperless-ngx.com/api/) [Workflows](https://docs.paperless-ngx.com/usage/#workflows)
- AI 能力：当前文档提供 OpenAI-compatible 或 Ollama 模型的 embeddings、相似搜索和问答。[使用文档](https://docs.paperless-ngx.com/usage/)

`判断/建议`

- 检索/自动报告适配：非常适合“截图/票据/PDF 进入长期档案”的工作流，文档级 OCR、分类、工作流和 API 成熟。
- 明显缺点：不是短文本、想法、日常知识的大纲/编辑器；偏向不可变文档归档；第三方移动端依赖，运维复杂度高于 Memos/Karakeep。
- 适合层级：文档和票据专用归档层。截图若是正式票据、合同、证件或长图，交给 Paperless；普通知识截图优先 Karakeep/Joplin。

### 3.8 AnythingLLM

`已验证事实`

- 定位：本地优先、自托管的多用户 AI 应用，支持文档聊天、Agent、RAG、向量数据库和完整 Developer API。[官方 README](https://github.com/Mintplex-Labs/anything-llm)
- 许可证：主项目 MIT；官方 Android 客户端仓库为 GPL-3.0。[主项目 LICENSE](https://github.com/Mintplex-Labs/anything-llm/blob/master/LICENSE) [Mobile LICENSE](https://github.com/Mintplex-Labs/anythingllm-mobile/blob/main/LICENSE)
- 活跃度：主仓库最近 push 为 2026-10-03，最近 release 为 1.17.0；Android 客户端 2026-10-02 仍有 v1.3.2 发布。[主 Release](https://github.com/Mintplex-Labs/anything-llm/releases/tag/v1.17.0) [Mobile Release](https://github.com/Mintplex-Labs/anythingllm-mobile/releases)
- 部署复杂度：低到中。桌面版、Docker 或 Bare Metal 部署；多用户和嵌入聊天组件以 Docker 为主。[官方 README](https://github.com/Mintplex-Labs/anything-llm)
- 文本/图片导入：支持 PDF、TXT、DOCX 等文档；Android 客户端支持从任意 app 分享照片、文档和链接，链接会抓取，文档会解析，并能用视觉模型理解图片。[Mobile README](https://github.com/Mintplex-Labs/anythingllm-mobile)
- 手机端：Android 客户端是真正的手机端 Agent harness，可完全设备内运行小模型，也可连接桌面/服务器。支持系统分享、选中文本、屏幕截图和默认助手入口；目前没有 iOS 客户端。[Mobile README](https://github.com/Mintplex-Labs/anythingllm-mobile)
- API/插件：主服务提供完整 Developer API、Agent Flows、自定义 Agent、MCP/工具等能力；Android 客户端可连接主服务进行 workspace 与文档聊天。[官方 README](https://github.com/Mintplex-Labs/anything-llm)

`判断/建议`

- 检索/自动报告适配：手机采集和 RAG 体验都很强，适合做“AI 前台”。自动报告需要 Agent Flow 或外部触发器来补调度。
- 明显缺点：不是长期知识编辑器；主服务、手机本地库和外部知识库之间存在数据边界；要区分“手机本地数据”和“连接服务器后的 workspace 数据”，否则备份策略会混乱。
- 适合层级：最适合同时承担 Android 采集入口和 RAG 对话前台。长期主库仍建议是 Markdown/Joplin，避免知识只存在于聊天和向量库。

### 3.9 Khoj

`已验证事实`

- 定位：个人 AI 第二大脑，支持本地文档、网页、语义搜索、Agent、Automations 和自托管。[官方 README](https://github.com/khoj-ai/khoj)
- 许可证：AGPL-3.0。[GitHub API](https://github.com/khoj-ai/khoj)
- 活跃度：最近 push 为 2026-08-02，最近 release 为 2.0.0-beta.28，发布日期 2026-03-26。相对其他核心候选明显偏慢。[GitHub](https://github.com/khoj-ai/khoj) [Release](https://github.com/khoj-ai/khoj/releases/tag/2.0.0-beta.28)
- 部署复杂度：中。Docker Compose 或 pip，自托管可接 OpenAI、Anthropic、Gemini、Ollama、LM Studio 等。[安装文档](https://docs.khoj.dev/get-started/setup)
- 文本/图片导入：支持图片、PDF、Markdown、Org-mode、Word、Notion 等；Web app 支持上传，Obsidian/Desktop/Emacs 可同步目录。[功能列表](https://docs.khoj.dev/features/all-features) [Web 客户端](https://docs.khoj.dev/clients/web)
- 手机端：可用手机浏览器 PWA；WhatsApp 可直接聊天，但要把 WhatsApp 与自己的数据连接，需要 Khoj Cloud 账号。文档还写明 `/share` 上传文档仍在开发中。[WhatsApp](https://docs.khoj.dev/clients/whatsapp) [Web PWA](https://docs.khoj.dev/clients/web)
- API/插件：官方客户端覆盖 Desktop、Emacs、Obsidian、Web、WhatsApp；Automations 可按计划运行查询并把研究报告发到邮箱。[Automations](https://docs.khoj.dev/features/automations)
- 检索：官方支持语义搜索、PDF/文档索引和多种客户端查询。[功能列表](https://docs.khoj.dev/features/all-features)

`判断/建议`

- 检索/自动报告适配：概念上非常贴合“收集后自动生成报告”，Automations 甚至已经覆盖邮件报告。
- 明显缺点：仓库活跃度风险；手机端自有数据采集依赖 Cloud 或自托管 Web/PWA；WhatsApp 文档上传尚未完成；对 Android 系统分享、截图 OCR 的体验不如 AnythingLLM/Karakeep。
- 适合层级：可作为报告 Agent 的实验候选，不建议现在作为关键存储或唯一入口。

### 3.10 RAGFlow

`已验证事实`

- 定位：开源 RAG 引擎，融合文档解析、检索、Agent 和知识编译。[官方 README](https://github.com/infiniflow/ragflow)
- 许可证：Apache-2.0。[LICENSE](https://github.com/infiniflow/ragflow/blob/main/LICENSE)
- 活跃度：最近 push 为 2026-10-03，最近 release 为 1.0.0-rc1，发布日期 2026-09-29。[Release](https://github.com/infiniflow/ragflow/releases/tag/v1.0.0-rc1)
- 部署复杂度：高。通常需要 Elasticsearch 或 Infinity、MySQL、MinIO、Redis/Kvrocks 等多服务；1.0 Go 版本还有迁移说明。[Docker 指南](https://ragflow.io/docs/) [HTTP API](https://ragflow.io/docs/http_api_reference)
- 文本/图片导入：支持本地文件、关联数据源和文件管理导入；文档解析后才生成 chunks。DeepDoc 处理版面分析和 OCR，适合复杂 PDF、表格和扫描件。[文档管理](https://ragflow.io/docs/files_dataset_document_management) [官方 README](https://github.com/infiniflow/ragflow)
- 手机端：官方能力中心是 Web UI、HTTP/Python API 和 Agent/Workflow，未提供第一方移动应用；手机采集应交给 Memos、Karakeep 或 AnythingLLM Mobile。
- API/插件：完整 REST API，支持数据集、文档、chunks、检索、Chat 和 Agent；兼容 OpenAI chat completions。[HTTP API](https://ragflow.io/docs/http_api_reference)
- 知识编译：可从文档生成 knowledge graph、knowledge tree、page index、mind map、timeline、Wiki 和 knowledge page。[知识编译](https://ragflow.io/docs/knowledge_compilation/overview)
- Agent：支持无代码画布、条件分支、工具调用、知识检索和多步编排。[Agent](https://ragflow.io/docs/agent_overview)

`判断/建议`

- 检索/自动报告适配：如果知识以 PDF、论文、扫描件和长文档为主，RAGFlow 是当前候选中解析和结构化能力最强的专用层。
- 明显缺点：部署与升级负担最高；1.0 仍为 RC；不是采集 UI，也不是人工编辑主库；单用户小规模使用时资源收益比不佳。
- 适合层级：可作为重量级“知识解析 + RAG + 报告 Agent”后端，前台仍需采集入口。

### 3.11 Open WebUI

`已验证事实`

- 定位：自托管 AI 平台，提供聊天、模型、工具、知识库、插件和 Agents。[官方 README](https://github.com/open-webui/open-webui)
- 许可证：Open WebUI License，允许使用但含“不得移除/替换 Open WebUI 品牌”等附加条件；小规模部署有品牌修改例外。[LICENSE](https://github.com/open-webui/open-webui/blob/main/LICENSE)
- 活跃度：最近 push 为 2026-10-02，最近 release 为 0.11.4，发布日期 2026-09-21。[Release](https://github.com/open-webui/open-webui/releases/tag/v0.11.4)
- 部署复杂度：低到中。Docker 单容器可启动，Ollama/CUDA 有官方镜像，也支持 Kustomize/Helm。[官方 README](https://github.com/open-webui/open-webui)
- 文本/图片导入：文件上传、Knowledge Base、集中 File Manager；支持 PDF、Word、文本等。RAG 文档抽取支持 Tika、Docling、Mistral OCR、PaddleOCR-vl 和外部 loader。[File Management](https://docs.openwebui.com/features/chat-conversations/data-controls/files) [RAG](https://docs.openwebui.com/features/chat-conversations/rag/)
- 手机端：官方 README 明确提供响应式设计和 PWA；没有第一方 Android/iOS 应用。
- API/插件：每个账号可创建 API key，可调用聊天、模型列表、文件上传和 RAG 等 Web UI 同源 API；支持 Filters、Actions、Pipes、Tools、Skills、MCP 和 OpenAPI tool servers。[API Keys](https://docs.openwebui.com/features/authentication-access/api-keys) [官方 README](https://github.com/open-webui/open-webui)
- 知识同步：官方 oikb 可从本地目录、GitHub、S3 等 44 类来源增量同步到 Knowledge Base。[Knowledge Base Sync](https://docs.openwebui.com/ecosystem/knowledge-base-sync/)

`判断/建议`

- 检索/自动报告适配：知识上传、RAG、插件和 PWA 都强，适合作为个人 AI 工作台。
- 明显缺点：不是手机采集入口；自动报告需要外部触发器；许可证存在品牌保留限制；外部向量库必须与 Open WebUI 使用完全一致的 embedding 模型，否则检索结果会失真。[RAG 外部知识源](https://docs.openwebui.com/features/chat-conversations/rag/)
- 适合层级：适合作为知识对话前台、模型网关和插件宿主，不建议作为原始信息主存。

### 3.12 Dify

`已验证事实`

- 定位：LLM 应用开发平台，组合 Workflow、RAG pipeline、Agent、模型管理和可观测性。[官方 README](https://github.com/langgenius/dify)
- 许可证：基于 Apache 2.0 的修改版，多租户服务和前端 logo/版权移除需要额外商业许可；个人单租户自托管通常处在较宽松范围。[LICENSE](https://github.com/langgenius/dify/blob/main/LICENSE)
- 活跃度：最近 push 为 2026-10-03，最近 release 为 1.17.1，发布日期 2026-09-10。[Release](https://github.com/langgenius/dify/releases/tag/1.17.1)
- 部署复杂度：中。官方 Docker Compose 启动，组件较多，但相比 RAGFlow 更适合应用编排。[官方 README](https://github.com/langgenius/dify)
- 文本/图片导入：Knowledge API 支持文本、PDF、TXT、DOCX 等文件；JPG/JPEG/PNG/GIF 小于 2 MB 时可自动抽取为 chunk 附件，多模态 embedding 可进一步索引图片。[上传文件](https://docs.dify.ai/en/cloud/use-dify/knowledge/create-knowledge/import-text-data/readme) [创建文档](https://docs.dify.ai/en/api-reference/documents/create-document-by-file)
- 手机端：没有第一方原生移动端，主要通过 Web App、API 或其他采集入口接入。
- API/插件：所有产品能力有相应 API；Workflow 可通过 run API 调用，也可由 schedule、webhook 或集成事件触发。[Run Workflow](https://docs.dify.ai/en/api-reference/workflow-runs/run-workflow) [Workflow](https://docs.dify.ai/en/cloud/use-dify/build/workflow-chatflow)
- 报告能力：官方把 Workflow 明确定位为一次输入到输出，适合自动化报告、数据处理和批处理。[Workflow](https://docs.dify.ai/en/cloud/use-dify/build/workflow-chatflow)

`判断/建议`

- 检索/自动报告适配：本调研中最佳的“分流和报告控制面”。可在采集 webhook 后执行：去重、OCR 补全、知识/事项分类、路由、写库、调用索引、生成日报/周报。
- 明显缺点：不是采集入口，也不是长期知识主库；许可证对 SaaS/多租户和品牌有额外限制；工作流配置和版本管理增加系统复杂度。
- 适合层级：建议作为统一编排层和报告生成层，不应替代 Markdown/Joplin 主库。

### 3.13 Weaviate

`已验证事实`

- 定位：开源向量数据库，将对象和向量结合，支持向量搜索与结构化过滤。[官方 README](https://github.com/weaviate/weaviate)
- 许可证：仓库源码分别使用 BSD-3-Clause 或 Weaviate License；`wl/` 目录及子目录为企业许可。[LICENSE](https://github.com/weaviate/weaviate/blob/main/LICENSE)
- 活跃度：最近 push 为 2026-10-02，最近 release 为 1.39.8，发布日期 2026-10-01。[Release](https://github.com/weaviate/weaviate/releases/tag/v1.39.8)
- 部署复杂度：中。支持 Weaviate Cloud 和 Docker 本地 Quickstart，REST/gRPC 都有官方客户端。[Quickstart](https://weaviate.io/developers/weaviate/quickstart)
- 文本/图片导入：数据库层只接收对象和向量，不负责手机采集、OCR、Markdown 解析或文档 UI。
- API：REST、gRPC 以及 Python、JavaScript、Go、Java、C# 客户端；支持向量化和 generative RAG 模块。[Quickstart](https://weaviate.io/developers/weaviate/quickstart)

`判断/建议`

- 检索/自动报告适配：如果检索需要复杂过滤、混合搜索或 Agent RAG，Weaviate 很强。
- 明显缺点：所有采集、抽取、切块、embedding、权限、报告都需自行构建；混合许可证增加企业功能边界。
- 适合层级：索引基础设施。只有自研知识服务时才值得选，否则优先由 Joplin、Qdrant 或现成 RAG 平台承担。

### 3.14 Qdrant

`已验证事实`

- 定位：高性能向量数据库和向量搜索服务，支持 payload、过滤、混合查询和本地部署。[官方 README](https://github.com/qdrant/qdrant)
- 许可证：Apache-2.0。[GitHub API](https://github.com/qdrant/qdrant)
- 活跃度：最近 push 为 2026-10-03，最近 release 为 1.19.1，发布日期 2026-09-04。[Release](https://github.com/qdrant/qdrant/releases/tag/v1.19.1)
- 部署复杂度：低到中。Docker 快速启动，REST、Web UI、gRPC 均可用。[Local Quickstart](https://qdrant.tech/documentation/quickstart/)
- 文本/图片导入：不负责文本/图片解析，只存向量和 payload。
- API：REST、gRPC 和多语言客户端，包含过滤、混合查询、快照和 MCP 工具生态。[官方文档](https://qdrant.tech/documentation/)

`判断/建议`

- 检索/自动报告适配：适合作为自建 Markdown/RAG 方案的默认向量索引，维护成本明显低于 Milvus。
- 明显缺点：只是索引，解决不了采集、图片 OCR、知识编辑、权限、报告和源数据一致性。
- 适合层级：Markdown 主库对应的独立索引层首选之一。

### 3.15 Milvus

`已验证事实`

- 定位：云原生、面向大规模 ANN 检索的向量数据库。[官方 README](https://github.com/milvus-io/milvus)
- 许可证：Apache-2.0。[GitHub API](https://github.com/milvus-io/milvus)
- 活跃度：最近 push 为 2026-10-02，最近 release 为 3.0.2，发布日期 2026-09-20。[Release](https://github.com/milvus-io/milvus/releases/tag/v3.0.2)
- 部署复杂度：中到高。Standalone Docker Compose 默认启动 Milvus、etcd、MinIO 三个容器；分布式模式更复杂。[Docker Compose](https://milvus.io/docs/install_standalone-docker-compose.md)
- 文本/图片导入：无采集与文件解析能力。
- API：官方支持 REST/gRPC 和多语言 SDK，适合大规模向量服务。

`判断/建议`

- 检索/自动报告适配：当向量规模达到数百万以上或需要分布式检索时才明显有价值。
- 明显缺点：对个人知识系统过度复杂，组件和存储管理成本高于收益。
- 适合层级：未来规模化索引层，当前不建议首选。

### 3.16 SiYuan

`已验证事实`

- 定位：本地优先、自托管、面向人与 AI Agent 协作的知识工作区。[官方 README](https://github.com/siyuan-note/siyuan)
- 许可证：AGPL-3.0。[GitHub API](https://github.com/siyuan-note/siyuan)
- 活跃度：最近 push 为 2026-10-03，最近 release 为 3.8.6，发布日期 2026-09-29。[Release](https://github.com/siyuan-note/siyuan/releases/tag/v3.8.6)

`判断/建议`

- 适合作为 Obsidian/Logseq 的中文友好替代，尤其是重视块级引用、自托管和 AI Agent 的场景。
- 仍需单独评估移动采集分享、开放 API 稳定性和外部索引接入；本次不把它列为主推荐，避免候选数量扩张后产生平行主库。

### 3.17 TriliumNext

`已验证事实`

- 定位：面向个人知识库的层级式笔记应用。[官方 README](https://github.com/TriliumNext/Trilium)
- 许可证：AGPL-3.0。[GitHub API](https://github.com/TriliumNext/Trilium)
- 活跃度：最近 push 为 2026-10-03，最近 release 为 0.106.0，发布日期 2026-09-25。[Release](https://github.com/TriliumNext/Trilium/releases/tag/v0.106.0)

`判断/建议`

- 适合强层级、脚本化和自托管同步的知识库需求。
- 对 Android 原生分享采集、通用 HTTP API 和外部 RAG 的成熟度不如 Memos、Joplin、Obsidian 生态清晰，不建议作为本项目第一阶段主库。

### 3.18 SilverBullet

`已验证事实`

- 定位：由 Markdown 和 Lua 驱动的可编程知识库。[官方 README](https://github.com/silverbulletmd/silverbullet)
- 许可证：MIT。[GitHub API](https://github.com/silverbulletmd/silverbullet)
- 活跃度：最近 push 为 2026-10-03，最近 release 为 2.11.1，发布日期 2026-09-22。[Release](https://github.com/silverbulletmd/silverbullet/releases/tag/2.11.1)

`判断/建议`

- 适合愿意用 Lua 自建采集和索引逻辑的技术用户，数据模型透明。
- 生态、移动体验和面向非开发者的稳定性弱于 Obsidian/Joplin，不适合作为默认推荐。

## 4. “直接文件/Markdown 库 + 索引”与“专用知识库/RAG 服务”对比

### 4.1 路线 A：直接文件/Markdown 库 + 索引

`已验证事实`

- Obsidian 官方明确说明笔记是本地文件系统中的 Markdown 纯文本，其他编辑器和文件管理器可修改，Obsidian 会自动刷新外部变化。[数据存储](https://obsidian.md/help/data-storage)
- Joplin 支持 Markdown 导入导出和 Data API，同时提供内部数据库、同步和桌面语义索引。[Markdown 导入](https://joplinapp.org/help/apps/import_export/) [Data API](https://joplinapp.org/help/api/references/rest_api/)
- Qdrant、Weaviate、Milvus 都只能提供向量检索，采集、解析、切块、embedding 和报告必须由其他组件完成。

`判断/建议`

- 优点：数据可读、可 diff、可 Git、可备份、可迁移；长期风险最低；RAG 数据库可以随时重建；适合人工审阅和知识演化。
- 缺点：需要自建统一入口、去重、OCR、切块、embedding、权限、删除传播和报告调度；移动端与 Windows 同时写入时仍要解决同步冲突；图片 OCR 和视觉理解会更依赖桌面服务或外部模型。
- 适用场景：知识要保留 5 年以上、需要人工编辑、担心数据库锁定、愿意维护一条轻量索引流水线。
- 推荐实现：`原始 inbox 保留 + Markdown 主库 + SQLite FTS5/OpenSearch/Qdrant + Dify 报告`。

### 4.2 路线 B：专用知识库/RAG 服务

`已验证事实`

- AnythingLLM、RAGFlow、Open WebUI、Dify 都提供文档上传、解析、索引、检索和基于知识的回答。
- RAGFlow 提供复杂文档 DeepDoc/OCR、知识编译和 Agent 编排。[知识编译](https://ragflow.io/docs/knowledge_compilation/overview)
- Dify Workflow 可由 schedule、webhook 或集成事件触发，并直接支持自动报告流程。[Workflow](https://docs.dify.ai/en/cloud/use-dify/build/workflow-chatflow)

`判断/建议`

- 优点：上线更快；内置解析、切块、向量检索、引用、Agent 和 API；适合快速实现分流与报告；复杂文档兼容性通常更好。
- 缺点：知识容易变成数据库里的 chunks，人工编辑和迁移体验弱；多系统产生重复数据；升级和备份更复杂；检索质量依赖解析、embedding 和 chunk 参数；供应商锁定风险上升。
- 适用场景：文档和 PDF 为主、团队共享、自动报告优先、可接受额外服务运维。
- 推荐实现：`Memos/Karakeep 采集 + RAGFlow 或 Dify 解析/检索 + 定期把高价值知识回写 Markdown`。

### 4.3 结论

`判断/建议`

- 不应二选一。最稳妥的是“Markdown/Joplin 作为源数据，专用 RAG 服务作为可重建派生层”。
- 采集入口、原始截图、OCR 文本、分类结果、报告都应保留外部 ID 和来源，确保向量库可以随时重建。
- 如果只允许维护两套服务，优先保留一个采集 inbox 和一个主库；RAG 先使用 Joplin 内置语义搜索或 AnythingLLM，RAGFlow 后置。

## 5. 面向目标场景的推荐架构

`判断/建议`

### 5.1 推荐方案 A：低运维个人版

组成：

1. Android/平板/Windows 使用 `Memos` PWA、Telegram Bot、Web Clipper 或 API 采集文本和截图。
2. 使用 `Joplin` 作为知识主库、桌面 OCR、本地语义搜索和 MCP 网关。
3. 使用 `Dify` 或轻量自建服务接收 Memos webhook，完成知识/事项分类、整理、写回和报告。
4. 事项写入独立任务系统；知识写入 Joplin；截图先 OCR，再把文本和附件写回。

优点：

- 服务数量少，Memos 和 Joplin 都可低资源运行。
- Joplin 已覆盖笔记、同步、OCR、语义检索和 MCP，近期维护活跃。
- Dify 只在需要智能分流和报告时引入。

风险：

- Joplin 语义索引只在桌面运行，手机依赖同步。
- 若 Joplin Data API 只在桌面 Web Clipper 服务运行时开放，自动写入需要桌面端在线。
- Memos 没有语义搜索，因此必须把 RAG 放到 Joplin/Dify。

### 5.2 推荐方案 B：数据主权与可迁移版

组成：

1. 使用 `Memos` 作为文本收件箱，使用 `Karakeep` 作为截图/链接/图片收件箱。
2. 使用 `Obsidian` vault 作为唯一知识主库，图片进入 `assets/`，笔记使用 frontmatter 保存 `source_id/type/created_at`。
3. 使用 `Qdrant` 建立派生索引；embedding 和 OCR 由 Windows 侧 worker 完成。
4. 使用 `Dify` 定时或 webhook 触发 Weekly Review、主题报告和待办提取。
5. 所有派生物都使用 source hash 和 upsert，删除/更新通过事件传播到索引。

优点：

- Markdown 主库完全可迁移，索引和报告可以删后重建。
- Karakeep 的移动端 OCR、AI 标签和 REST/MCP 很适合截图入口。
- 与原始需求“文本或截图发给 AI”最匹配。

风险：

- 需要自建 worker、同步策略和幂等机制。
- Obsidian 移动端写入与 Windows 索引器并发时，要处理文件冲突和重复 embedding。

### 5.3 文档密集型方案

`判断/建议`

- 票据、合同、证件和长 PDF 交给 `Paperless-ngx`。
- 论文、手册、复杂表格和需要知识图谱/时间线的材料交给 `RAGFlow`。
- 普通随手笔记仍交给 `Joplin/Obsidian + Memos`，不要把每一条短文本都送入重型 RAG。

### 5.4 自动分流的最低可靠设计

`判断/建议`

1. 接入层只做鉴权、去重和原始事件落库，返回快速 ACK。
2. 用 `source_id + SHA-256` 作为幂等键，避免重试产生重复知识。
3. OCR/VLM 先生成可审阅文本，再做分类；不要只依赖分类器直接丢弃原图。
4. 分类输出至少包含 `knowledge/task/uncertain`，低置信度进入人工确认队列。
5. 知识路由到 Markdown/Joplin，事项路由到任务系统。
6. 所有写入都产生事件，索引器只消费事件，不直接扫描和猜测。
7. 日报/周报引用原笔记，不要生成无法回溯的“摘要孤岛”。

## 6. 最终排名与选型

### 6.1 采集入口

`判断/建议`

1. `Karakeep`：截图、图片、链接、OCR、自动标签、移动端和 API 最均衡。
2. `Memos`：文本、Telegram、PWA、Webhook、MCP 和低运维最强。
3. `AnythingLLM Mobile`：Android 系统分享和视觉理解体验最强，但更像 AI 助手而非可靠 inbox。
4. `Joplin`：适合直接把笔记和附件收进最终主库，但手机分享链路不如前三者明确。

### 6.2 知识主库

`判断/建议`

1. `Joplin`：开源、跨端、OCR、语义搜索、Data API 和 MCP 的综合分最高。
2. `Obsidian`：编辑体验、插件生态和 Markdown 可迁移性最好，但闭源且自动化需外接。
3. `Logseq`：大纲和任务优秀，但 2.0/DB/Android 迁移风险使其暂列第三。
4. `SiYuan/Trilium/SilverBullet`：适合特定偏好，当前生态与接入确定性不如前三者。

### 6.3 RAG 与报告

`判断/建议`

1. `Dify`：最适合做统一分流、路由、写库和报告编排。
2. `RAGFlow`：复杂文档解析和知识制品最强，但运维最重。
3. `AnythingLLM`：低门槛、自带 Agent，并可覆盖 Android 入口。
4. `Open WebUI`：优秀的 AI 工作台和插件宿主，但调度与采集不是强项。
5. `Khoj`：报告理念最好，但活跃度风险使其只能作为备选。

### 6.4 索引基础设施

`判断/建议`

1. `Qdrant`：个人项目默认首选。
2. `Weaviate`：需要混合检索和复杂过滤时考虑，注意企业目录许可。
3. `Milvus`：只有大规模或分布式需求时考虑。

## 7. 不建议直接采用的组合

`判断/建议`

- `AppFlowy 商业自托管作为唯一主库`：开放核心已收紧，服务复杂，单人收益低。
- `Khoj 作为唯一采集和存储`：当前仓库活跃度不足，WhatsApp 自有数据依赖 Cloud。
- `RAGFlow 作为第一版入口`：采集与编辑能力弱，部署重，容易把项目拖入基础设施维护。
- `只用向量数据库`：没有采集、OCR、编辑、报告和来源管理，最终会变成半成品。
- `只把 Markdown 文件堆在同步盘里`：能存但不会自动分流、OCR、索引和生成可靠报告。

## 8. 官方来源索引

- Obsidian: [官网](https://obsidian.md/), [数据存储](https://obsidian.md/help/data-storage), [Android](https://obsidian.md/help/android), [URI](https://obsidian.md/help/uri), [开发者文档](https://docs.obsidian.md), [GitHub 发布仓库](https://github.com/obsidianmd/obsidian-releases)
- Logseq: [GitHub](https://github.com/logseq/logseq), [README](https://github.com/logseq/logseq/blob/master/README.md), [DB 版本](https://github.com/logseq/docs/blob/master/db-version.md), [Plugin API](https://plugins-doc.logseq.com/)
- Joplin: [官网](https://joplinapp.org/), [GitHub](https://github.com/laurent22/joplin), [Data API](https://joplinapp.org/help/api/references/rest_api/), [OCR](https://joplinapp.org/help/apps/ocr/), [语义搜索](https://joplinapp.org/help/apps/ai_semantic_search/), [MCP](https://joplinapp.org/help/apps/ai_mcp/)
- AppFlowy: [主仓库](https://github.com/AppFlowy-IO/AppFlowy), [自托管商业仓库](https://github.com/AppFlowy-IO/AppFlowy-SelfHost-Commercial), [旧 Cloud 仓库归档说明](https://github.com/AppFlowy-IO/AppFlowy-Cloud), [Android](https://play.google.com/store/apps/details?id=io.appflowy.appflowy)
- Memos: [官网](https://usememos.com/), [GitHub](https://github.com/usememos/memos), [API Access](https://www.usememos.com/docs/integrations/api-access), [Webhooks](https://www.usememos.com/docs/integrations/webhooks), [Search](https://www.usememos.com/features/universal-search)
- Karakeep: [官网](https://karakeep.app/), [GitHub](https://github.com/karakeep-app/karakeep), [Docker](https://docs.karakeep.app/installation/docker), [API](https://docs.karakeep.app/api/karakeep-api), [MCP](https://docs.karakeep.app/integrations/mcp)
- Paperless-ngx: [文档](https://docs.paperless-ngx.com/), [GitHub](https://github.com/paperless-ngx/paperless-ngx), [REST API](https://docs.paperless-ngx.com/api/), [Usage](https://docs.paperless-ngx.com/usage/)
- AnythingLLM: [官网](https://anythingllm.com/), [主仓库](https://github.com/Mintplex-Labs/anything-llm), [Android 客户端](https://github.com/Mintplex-Labs/anythingllm-mobile), [文档](https://docs.anythingllm.com/)
- Khoj: [官网](https://khoj.dev/), [GitHub](https://github.com/khoj-ai/khoj), [文档](https://docs.khoj.dev/), [WhatsApp](https://docs.khoj.dev/clients/whatsapp), [Automations](https://docs.khoj.dev/features/automations)
- RAGFlow: [官网](https://ragflow.io/), [GitHub](https://github.com/infiniflow/ragflow), [HTTP API](https://ragflow.io/docs/http_api_reference), [知识编译](https://ragflow.io/docs/knowledge_compilation/overview)
- Open WebUI: [官网](https://openwebui.com/), [GitHub](https://github.com/open-webui/open-webui), [文档](https://docs.openwebui.com/), [许可证](https://github.com/open-webui/open-webui/blob/main/LICENSE)
- Dify: [官网](https://dify.ai/), [GitHub](https://github.com/langgenius/dify), [文档](https://docs.dify.ai/), [许可证](https://github.com/langgenius/dify/blob/main/LICENSE)
- Weaviate: [文档](https://weaviate.io/developers/weaviate/), [GitHub](https://github.com/weaviate/weaviate), [许可证](https://github.com/weaviate/weaviate/blob/main/LICENSE)
- Qdrant: [文档](https://qdrant.tech/documentation/), [GitHub](https://github.com/qdrant/qdrant)
- Milvus: [文档](https://milvus.io/docs/), [GitHub](https://github.com/milvus-io/milvus)
