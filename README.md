# 个人 AI 收件箱

[![Flutter CI](https://github.com/YuanFangCH/personal-ai-inbox/actions/workflows/flutter.yml/badge.svg)](https://github.com/YuanFangCH/personal-ai-inbox/actions/workflows/flutter.yml)
[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

一个本地优先的个人信息捕获、整理与提醒系统。Android 手机、Android 平板和 Windows 端各自运行独立 Flutter App，以 Markdown 为权威成果库，通过端内规则、云端模型和可替换同步接口完成闭环。
这个软件一开始是为我自己设计的，安卓端我仅针对荣耀90,200，m7m8，三星tabs7,9做了实机测试，其他设备不保证能完全运行。

## 下载与安装

首个预发布版本从 [GitHub Releases](https://github.com/YuanFangCH/personal-ai-inbox/releases) 下载：

- Android 7.0 及以上：安装通用 APK。
- Windows 11 x64：选择安装包或便携 ZIP。
- 发布页同时提供 `SHA256SUMS.txt`，下载后应校验文件哈希。

`v1.1.1` 是当前预发布版本，完成本地核心模块化重构，并修复 Android 日历快速新建面板的瞬态布局溢出。

## 核心能力

- 本地优先：文本、分享内容和图片先在本端落盘，离线时捕获、编辑和查看不受影响。
- Markdown 主库：一个成果一个 `.md` 文件，SQLite 只保存索引、同步游标和幂等账本，删库后可重建。
- AI 对话：本地多会话、SSE 流式回复、停止与重试、会话级上下文隔离。
- 图片输入：相册、拍照、Android 图片分享、自动缩放和 EXIF 清理。
- 受控自动记录：模型只可请求新建高置信、非敏感、无日期歧义且未重复的成果，修改和删除永不自动执行。
- 行动与知识：内置事项、日历工作区、知识、确认队列和同步状态页面；日历统一承载日程、我的一天和待办，并提供事件/待办快速新建。
- 系统接入：Android 注册 `ACTION_SEND` 与 `ACTION_PROCESS_TEXT`，支持从其他 App 分享文本和图片。
- 多端形态：同一套 Flutter 代码适配手机、平板、Windows 和 Web 预览。

## 界面预览

| Android 手机 | Android 平板 |
|---|---|
| ![手机浅色界面](docs/test-reports/screenshots/android-phone-light.png) | ![平板横屏界面](docs/test-reports/screenshots/android-tablet-landscape.png) |



## 模型配置

设置页支持 OpenAI 兼容配置：

- `Base URL`
- 模型名
- API Key
- 是否允许图片发送到云端

默认端点为 `https://api.deepseek.com`，默认模型为 `deepseek-flash`。




## 许可证

Copyright (c) 2026 YuanFangCH

本项目采用 [MIT License](LICENSE)。
