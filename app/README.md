# 懒狗秘书

完整项目介绍、开源许可和安全说明见 [根目录 README](../README.md)。

Flutter 客户端首版，目标覆盖 Android 手机、Android 平板和 Windows。当前实现以本地闭环为先：

- 文本、分享内容与随手记先落本端，不阻塞等待模型。
- Markdown 是一个成果一个文件，SQLite 只保存索引与捕获状态。
- 内置首页、秘书对话、笔记式表、日历、全局知识、同步和设置。三张默认表只作兜底收纳；自定义表可混合放笔记、待办、日程、事件及六种自定义字段。
- 每次进入秘书页显示临时新对话；历史会话从抽屉或桌面侧栏继续，未发送退出不创建空会话。
- 对话支持文本、剪贴板粘贴、相册、拍照、Android 文本/图片分享及 SSE 多轮本地工具调用。
- 文件支持 TXT、Markdown、CSV、DOCX、XLSX 和 PDF 文字层提取；解析在本端进行，原始文件不上传，扫描件暂不做 OCR。
- 会话独立保存读取/新增/修改删除权限；AI 按表检索，表内内容操作默认直接执行且可撤销，表结构操作显示聊天内确认卡；全局知识候选需逐项人工确认。
- 表与笔记页接管旧草稿和捕获审核；同步冲突在同步页处理。旧事项/知识管理页面及独立待处理页已移除，旧资料由只读迁移门保护。
- 捕获按待办、日程、事件、笔记归入默认表；分类不确定或模型失败时保留原文为笔记，不将普通笔记的时间文字送入日历。
- 同步层已有 `SyncProvider` 接口、三项 hash 判定、冲突副本和墓碑逻辑。
- 本地核心已拆分为 `DevicePreferences`、`ResultLibrary`、`CaptureWorkflow`、`ConversationWorkspace` 和 `SyncWorkspace` 模块；`AppController` 仅保留迁移期兼容 facade。
- 云端模型走 OpenAI 兼容配置，密钥进入系统安全存储。
- Android 注册 `ACTION_SEND` 与 `ACTION_PROCESS_TEXT`，可从其他 App 分享文本。

## 表与笔记改版状态

P0–P9 首轮实现、定向验收和候选构建已完成。P8替换了旧事项/待处理入口；P9生成 Android Debug APK 和 Windows Release 候选。Android 15 AVD 的表页、捕获、AI表操作/日程改期/删除恢复及合成旧资料迁移用例通过。真实用户资料尚未迁移，Windows 候选未运行验收。详见根目录 [RM_HANDOFF](../RM_HANDOFF.md)、[执行计划](../docs/table-notebook-implementation-plan.md) 和 [验证记录](../test-results/table-notebook-p8-p9-20261030/VALIDATION.md)。

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
