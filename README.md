# 懒狗秘书

[![Flutter CI](https://github.com/YuanFangCH/personal-ai-inbox/actions/workflows/flutter.yml/badge.svg)](https://github.com/YuanFangCH/personal-ai-inbox/actions/workflows/flutter.yml)
[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

一个本地优先的个人信息捕获、整理与提醒系统。Android 手机、Android 平板和 Windows 端各自运行独立 Flutter App，以 Markdown 为权威成果库，通过端内规则、云端模型和可替换同步接口完成闭环。

## 下载与安装

首个预发布版本从 [GitHub Releases](https://github.com/YuanFangCH/personal-ai-inbox/releases) 下载：

- Android 7.0 及以上：安装通用 APK。
- Windows 11 x64：选择安装包或便携 ZIP。
- 发布页同时提供 `SHA256SUMS.txt`，下载后应校验文件哈希。

`v1.1.5` 是当前预览版，延续 Android 长期发布证书，并包含 DeepSeek 风格界面改版和输入/布局回归修复。v1.1.3 及之前的包无法保证与本版直接覆盖安装；本版真实 Android 设备、IME 与截图视觉验收尚未完成，详见 [GitHub Release](https://github.com/YuanFangCH/personal-ai-inbox/releases/tag/v1.1.5) 和[发行说明](docs/releases/v1.1.5.md)。

## 核心能力

- 本地优先：文本、分享内容和图片先在本端落盘，离线时捕获、编辑和查看不受影响。
- Markdown 主库：一个成果一个 `.md` 文件，SQLite 保存派生索引、同步游标和本地操作/撤销账本。Markdown 仍是成果正文权威副本；可撤销的前一版本仅在本地账本短暂保留，现采用 10 分钟窗口。
- AI 秘书对话：会话管理、SSE 多轮工具回复；按会话保存读取/新增/修改删除权限，直接操作普通成果并可撤销。
- 图片输入：相册、拍照、Android 图片分享、自动缩放和 EXIF 清理。
- 受控自动记录：模型可请求新建高置信、非敏感、无日期歧义且未重复的普通成果；普通成果改删按权限执行并支持撤销，全局知识改动始终需人工确认。
- 行动与知识：内置事项、日历、全局知识管理、独立待处理和同步状态页面；日历统一承载日程、我的一天和待办，并提供事件/待办快速新建。
- 系统接入：Android 注册 `ACTION_SEND` 与 `ACTION_PROCESS_TEXT`，支持从其他 App 分享文本和图片。
- 多端形态：同一套 Flutter 代码适配手机、平板、Windows 和 Web 预览。

## 项目交接


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
