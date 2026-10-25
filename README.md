# 个人 AI 收件箱

[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

一个本地优先的个人信息捕获、整理与提醒系统。Android 手机、Android 平板和 Windows 端各自运行独立 Flutter App，以 Markdown 为成果正文权威副本，通过端内规则、云端模型和可替换同步接口完成闭环。

> 当前分支是历史开发快照；请使用默认 `main` 分支和 GitHub Releases 获取当前版本。

## 核心能力

- 本地优先捕获、编辑和查看；Markdown 文件保存成果，SQLite 管理索引与本地状态。
- AI 对话采用本地多会话与受控工具调用；权限由端内核心管理。
- 支持图片、系统分享入口、事项、日历、待办和知识工作区。
- OpenAI 兼容模型接入，API Key 保存在系统安全存储中。

## 架构

```text
Android / Windows / Web
  -> 端内捕获
  -> Markdown vault + SQLite 索引
  -> 规则引擎与受控模型工具调用
  -> 云模型 API（可选）
  -> SyncProvider
```

真实 OneDrive 同步、百度网盘归档和本地通知尚未接入。Windows 安装包未代码签名。

## 运行与构建

```powershell
cd app
flutter pub get
flutter run
flutter build apk --release
flutter build windows --release
```

Web 仅用于界面预览，不作为数据备份或迁移来源。

## 项目结构

```text
app/lib/      Flutter 客户端与本地核心
app/android/  Android 应用配置
app/windows/  Windows 桌面配置
docs/         架构、协议、ADR 与研究
scripts/      构建及仓库维护工具
```

## 安全与许可

不要提交 API Key、OAuth 令牌、签名密钥、环境配置、本地 vault 或包含个人内容的截图。许可证为 MIT，见 [LICENSE](LICENSE)。
