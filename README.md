# 个人 AI 收件箱

[![Flutter CI](https://github.com/YuanFangCH/personal-ai-inbox/actions/workflows/flutter.yml/badge.svg)](https://github.com/YuanFangCH/personal-ai-inbox/actions/workflows/flutter.yml)
[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

一个本地优先的个人信息捕获、整理与提醒系统。Android 手机、Android 平板和 Windows 端各自运行独立 Flutter App，以 Markdown 为权威成果库，通过端内规则、云端模型和可替换同步接口完成闭环。

## 下载与安装

首个预发布版本从 [GitHub Releases](https://github.com/YuanFangCH/personal-ai-inbox/releases) 下载：

- Android 7.0 及以上：安装通用 APK。
- Windows 11 x64：选择安装包或便携 ZIP。
- 发布页同时提供 `SHA256SUMS.txt`，下载后应校验文件哈希。

`v1.1.2` 是当前预发布版本：新增 100 条真实端到端测试场景并在手机、平板和 Windows 三端全部通过，同时修复手机高字体下待确认状态标签的横向溢出。

## 核心能力

- 本地优先：文本、分享内容和图片先在本端落盘，离线时捕获、编辑和查看不受影响。
- Markdown 主库：一个成果一个 `.md` 文件，SQLite 只保存索引、同步游标和幂等账本，删库后可重建。
- AI 对话：本地多会话、SSE 流式回复、停止与重试、会话级上下文隔离。
- 图片输入：相册、拍照、Android 图片分享、自动缩放和 EXIF 清理。
- 受控自动记录：模型只可请求新建高置信、非敏感、无日期歧义且未重复的成果，修改和删除永不自动执行。
- 行动与知识：内置事项、日历工作区、知识、确认队列和同步状态页面；日历统一承载日程、我的一天和待办，并提供事件/待办快速新建。
- 系统接入：Android 注册 `ACTION_SEND` 与 `ACTION_PROCESS_TEXT`，支持从其他 App 分享文本和图片。
- 多端形态：同一套 Flutter 代码适配手机、平板、Windows 和 Web 预览。

## 当前规划

已细化 [S0–S12 实施任务与完成门禁](docs/secretary-implementation-plan.md)，安排业务修改完成后执行[三端 100 例新功能验收](docs/testing/secretary-100-case-plan.md)：手机模拟器 50、平板模拟器 25、Windows 桌面 25。当前已实现 S1 会话权限快照、默认值与旧数据迁移；检索、成果操作、全局知识和新矩阵仍在后续阶段，100 例尚未执行。

追加规划已确认：软件显示名称改为“懒狗秘书”，AI 默认担任秘书型助理；全局知识库随成果三端同步，AI 按需检索且受读取权限控制，新增、修改、删除均须人工确认。见[角色与全局知识库补充计划](docs/secretary-and-global-knowledge-plan.md)；运行版本尚未更名或实现知识库。

检索以节省开销与响应时间为目标：当前会话足够则不检索，必要时定向查询、少量返回、足够即停，复用有效结果并在内容变化后失效。见[检索策略与预算](docs/ai-retrieval-policy.md)，尚未实现或测量提速。

已确认将收件箱改为参考 DeepSeek 手机端的 AI 对话界面：每次进入显示新对话，待处理独立成页，三组会话权限默认开启，成果改删直接执行并可撤销。文件、语音转文字、回复朗读和深度思考纳入计划；联网仅用当前模型接口内置能力，不支持则禁用。见 [改造计划](docs/ai-conversation-redesign-plan.md) 与 [ADR 0017](docs/adr/0017-conversation-permissions-and-reversible-result-actions.md)。目前仅完成规划，上述新增能力尚未实现；上方核心能力描述仍对应运行版本。

## 模型配置

设置页支持 OpenAI 兼容配置：

- `Base URL`
- 模型名
- API Key
- 是否允许图片发送到云端
- 高级能力覆盖、响应期限与上下文/图片上限

默认端点为 `https://api.deepseek.com`，默认模型为 `deepseek-flash`。

API Key 单独保存在本机安全存储中。设置导入/导出不包含 Key 或设备 ID。连接测试会单独发送一条固定文本请求，不会发送历史消息或图片，也不会自动更改能力声明。

Web 版本仅用于界面预览。浏览器中的 Markdown 结果可能写入本地浏览器存储，但索引、会话与图片使用内存 adapter；不要把 Web 当作可靠备份或数据迁移来源。




## 许可证

Copyright (c) 2026 YuanFangCH

本项目采用 [MIT License](LICENSE)。
