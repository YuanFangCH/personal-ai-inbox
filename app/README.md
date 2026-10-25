# 懒狗秘书

完整项目介绍、开源许可和安全说明见 [根目录 README](../README.md)。

Flutter 客户端首版，目标覆盖 Android 手机、Android 平板和 Windows。当前实现以本地闭环为先：

- 文本、分享内容与随手记先落本端，不阻塞等待模型。
- Markdown 是一个成果一个文件，SQLite 只保存索引与捕获状态。
- 内置首页、秘书对话、日历、事项、知识、待处理、全局知识、同步和设置；日历统一承载日程、我的一天和待办。
- 每次进入秘书页显示临时新对话；历史会话从抽屉或桌面侧栏继续，未发送退出不创建空会话。
- 对话支持文本、剪贴板粘贴、相册、拍照、Android 文本/图片分享及 SSE 多轮本地工具调用。
- 文件支持 TXT、Markdown、CSV、DOCX、XLSX 和 PDF 文字层提取；解析在本端进行，原始文件不上传，扫描件暂不做 OCR。
- 会话独立保存读取/新增/修改删除权限；普通成果操作按权限执行且可撤销，全局知识候选需逐项人工确认。
- 待处理独立显示草稿、确认捕获、同步冲突及全局知识候选；确认后的全局事实进入知识成果库。
- 模型可自动创建高置信、非敏感、日期明确且未重复的成果；风险项进入待处理，直接操作保留 10 分钟撤销。
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

若本机 Gradle wrapper 或 NDK/CMake 缓存损坏，可用 `scripts/build-android-isolated.ps1` 隔离 Gradle 用户目录、项目缓存及 NDK/CMake staging；该入口仅构建 Debug APK，不绕过 TLS 校验。需要 Flutter、Gradle 和 Android SDK 路径参数；Windows 可使用 `-UseWindowsRootCertificates`。

Windows 构建需要 Visual Studio 的 C++ 桌面工作负载和 ATL 组件。
