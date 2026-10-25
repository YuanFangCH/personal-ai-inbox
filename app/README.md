# 个人 AI 收件箱

完整项目介绍、开源许可和安全说明见 [根目录 README](../README.md)。

Flutter 客户端首版，目标覆盖 Android 手机、Android 平板和 Windows。当前实现以本地闭环为先：

- 文本、分享内容与随手记先落本端，不阻塞等待模型。
- Markdown 是一个成果一个文件，SQLite 只保存索引与捕获状态。
- 内置首页、收件箱、日历工作区、事项、知识、同步和设置；日历工作区统一承载日程、我的一天和待办。
- 收件箱合并等待确认的捕获、同步冲突、草稿和本地多会话 AI 对话。
- 冷启动直接进入首页；点击“新对话”只打开临时输入页，首次发送非空文字或图片时才创建会话。
- 对话支持文本、剪贴板粘贴、相册、拍照和 Android 文本 / 图片分享，并通过 SSE 流式回复。
- 云端模型可以自动新建高置信、非敏感的成果；风险项进入待整理区，成功创建后保留 10 分钟撤销。
- 同步层已有 `SyncProvider` 接口、三项 hash 判定、冲突副本和墓碑逻辑。
- 本地核心已拆分为 `DevicePreferences`、`ResultLibrary`、`CaptureWorkflow`、`ConversationWorkspace` 和 `SyncWorkspace` 模块；`AppController` 仅保留迁移期兼容 facade。
- 云端模型走 OpenAI 兼容配置，密钥进入系统安全存储。
- Android 注册 `ACTION_SEND` 与 `ACTION_PROCESS_TEXT`，可从其他 App 分享文本。

## 运行

```powershell
flutter pub get
flutter run
```

Web 预览：

```powershell
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 7357
```

Android 构建：

```powershell
flutter build apk --debug
flutter build apk --release
flutter build windows --release
```

Windows 构建需要 Visual Studio 的 C++ 桌面工作负载和 ATL 组件。
