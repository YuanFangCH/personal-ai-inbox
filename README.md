# 懒狗秘书

[![Flutter CI](https://github.com/YuanFangCH/personal-ai-inbox/actions/workflows/flutter.yml/badge.svg)](https://github.com/YuanFangCH/personal-ai-inbox/actions/workflows/flutter.yml)
[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

一个本地优先的个人信息捕获、整理与提醒系统。Android 手机、Android 平板和 Windows 端各自运行独立 Flutter App，以 Markdown 为权威成果库，通过端内规则、云端模型和可替换同步接口完成闭环。

## 下载与安装

首个预发布版本从 [GitHub Releases](https://github.com/YuanFangCH/personal-ai-inbox/releases) 下载：

- Android 7.0 及以上：安装通用 APK。
- Windows 11 x64：选择安装包或便携 ZIP。
- 发布页同时提供 `SHA256SUMS.txt`，下载后应校验文件哈希。

`v1.1.3` 是当前预览版候选：将收件箱改为 AI 秘书对话，支持会话权限、成果改删与撤销、全局知识审批，以及本地文件和语音输入。三端 100 例验收已通过；发布状态以 [GitHub Releases](https://github.com/YuanFangCH/personal-ai-inbox/releases) 为准。

## 核心能力

- 本地优先：文本、分享内容和图片先在本端落盘，离线时捕获、编辑和查看不受影响。
- Markdown 主库：一个成果一个 `.md` 文件，SQLite 保存派生索引、同步游标和本地操作/撤销账本。Markdown 仍是成果正文权威副本；可撤销的前一版本仅在本地账本短暂保留，现采用 10 分钟窗口。
- AI 秘书对话：会话管理、SSE 多轮工具回复；按会话保存读取/新增/修改删除权限，直接操作普通成果并可撤销。
- 图片输入：相册、拍照、Android 图片分享、自动缩放和 EXIF 清理。
- 受控自动记录：模型可请求新建高置信、非敏感、无日期歧义且未重复的普通成果；普通成果改删按权限执行并支持撤销，全局知识改动始终需人工确认。
- 行动与知识：内置事项、日历、全局知识管理、独立待处理和同步状态页面；日历统一承载日程、我的一天和待办，并提供事件/待办快速新建。
- 系统接入：Android 注册 `ACTION_SEND` 与 `ACTION_PROCESS_TEXT`，支持从其他 App 分享文本和图片。
- 多端形态：同一套 Flutter 代码适配手机、平板、Windows 和 Web 预览。

## 当前进展

已完成 [S0–S12 实施计划](docs/secretary-implementation-plan.md)及[三端 100 例新功能验收](docs/testing/secretary-100-case-plan.md)：手机 AVD 50/50、平板 AVD 25/25、Windows 桌面 25/25，合计 100/100 通过。最终代码 SHA、逐例状态、设备信息和日志见[验收报告](test-results/secretary-100-final/20261020-110321-37d96f71/verification.md)。真实 OneDrive 同步和麦克风/扬声器仍待单独接入/验证。

追加规划已确认：软件显示名称为“懒狗秘书”，AI 默认担任秘书型助理；全局知识库以 `knowledge` 成果承载，候选本地留端，确认后的事实按成果同步，AI 按需检索且受读取权限控制，新增、修改、删除均须人工确认。界面与审批核心已实现；真实 OneDrive 接入和三端同步仍未完成。见[角色与全局知识库补充计划](docs/secretary-and-global-knowledge-plan.md)。

检索以节省开销与响应时间为目标：当前会话足够则不检索，必要时定向查询、少量返回、足够即停，复用有效结果并在内容变化后失效。见[检索策略与预算](docs/ai-retrieval-policy.md)，尚未实现或测量提速。

收件箱已改为参考 DeepSeek 手机端的 AI 秘书对话界面：每次进入显示新对话，历史会话可从侧栏管理，待处理独立成页；读取、新增、修改与删除权限按会话保存，默认全开。普通成果改删直接执行并可撤销，全局知识改动需人工确认；AI 支持按需检索、本地文件文本提取、语音转文字和回复朗读。手机、平板、Windows 的 100 例验收全部通过。当前 Chat Completions 未声明内置联网能力，联网按钮禁用。见 [改造计划](docs/ai-conversation-redesign-plan.md)、[权限与成果操作 ADR](docs/adr/0017-conversation-permissions-and-reversible-result-actions.md) 和[全局知识 ADR](docs/adr/0018-confirmed-global-knowledge-for-secretary.md)。

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
