# 首页与桌面平铺时间轴验证

日期：2026-11-19
范围：首页表模块、桌面投影、Android RemoteViews 列表和点击绑定。

## 结果

| 检查 | 结果 | 说明 |
|---|---|---|
| 首页/小组件定向 Dart 测试 | 通过 33/33 | 合同 6、投影 10、工作区 10、桥接 1、首页 UI 6 |
| Dart 目标静态分析 | 通过，0 issue | 5 个生产文件、4 个测试文件 |
| 格式检查 | 通过 | `dart format` 8 个文件，最终 0 变化 |
| 空白检查 | 通过 | `git diff --check` |
| Android arm64 Debug 构建 | 通过 | Gradle `assembleDebug` |
| APK Manifest | 通过 | 含 `HomeWidgetListService` 和 `BIND_REMOTEVIEWS`，不含 `HomeWidgetClickReceiver` |
| Android App Lint Analyse | 通过 | `:app:lintAnalyzeDebug --offline` |
| Android 全模块 `lintDebug` | 未完成 | `flutter_secure_storage` 的单测 Lint 模型下载 `nativeruntime-dist-compat-1.0.18.jar` 时远端 TLS 握手终止 |
| API 35 启动器视觉/交互 | 未执行 | 本轮没有启动 AVD、固定小组件或截图 |
| API 24–30 启动器视觉/交互 | 未执行 | 需要对应系统镜像和桌面验证 |

Android APK：

- 路径：`app/build/app/outputs/flutter-apk/app-debug.apk`
- 大小：`203,460,625` 字节
- SHA-256：`987F40F5A56B8F8AB29D90EA5E4CD494881391CAD6C7F4E911954176E5D1929B`

## 命令

### Dart 测试

Windows 缺少 `Microsoft.VisualStudio.Component.VC.Tools.x86.x64`，测试前临时创建仓库脚本约定的 `app/.dart_tool/aitext_skip_windows_pdfium_gate`，仅跳过 Windows PDFium Hook；测试后已删除。

```powershell
flutter test --no-pub `
  test/home_widgets/home_widget_contract_test.dart `
  test/home_widgets/home_widget_projection_test.dart `
  test/home_widgets/widget_workspace_test.dart `
  test/home_widget_bridge_test.dart `
  test/home_page_ui_test.dart
```

### 静态检查

```powershell
dart analyze `
  lib/core/table_entry_order.dart `
  lib/ui/pages/home_page.dart `
  lib/modules/home_widgets/home_widget_contract.dart `
  lib/modules/home_widgets/home_widget_projection.dart `
  lib/ui/pages/widget_settings_page.dart `
  test/home_page_ui_test.dart `
  test/home_widgets/home_widget_contract_test.dart `
  test/home_widgets/home_widget_projection_test.dart

git diff --check
```

### Android 构建

环境变量使用 D 盘缓存、SDK、Android 用户目录和项目调试证书，避免当前环境指向不可用的 E 盘：

```powershell
$env:GRADLE_USER_HOME='D:\GradleCache'
$env:ANDROID_HOME='D:\DevTools\Android\Sdk'
$env:ANDROID_SDK_ROOT='D:\DevTools\Android\Sdk'
$env:ANDROID_USER_HOME='D:\DevTools\Android\.android'
$env:AITEXT_DEBUG_KEYSTORE_PATH='D:\DevTools\Android\.android\debug.keystore'
flutter build apk --debug --no-pub --target-platform android-arm64
```

构建输出包含既有 `flutter_tts` 未来 Kotlin Gradle Plugin 迁移警告；本轮构建成功，警告与本次小组件改动无直接关系。

### Manifest

```powershell
aapt2 dump xmltree `
  app/build/app/outputs/flutter-apk/app-debug.apk `
  --file AndroidManifest.xml
```

核验结果为 `HomeWidgetListService`、`BIND_REMOTEVIEWS` 存在，`HomeWidgetClickReceiver` 不存在。

## 行为覆盖

- 首页表卡中提前时间的日程排在较晚待办前，无时间笔记最后。
- 首页表卡不显示已完成待办；活动页把待办改为完成后，表卡收到通知并自动移除。
- 小组件旧 `todo_state=any` 和 `updated_at` 配置仍会隐藏完成待办，并按业务时间排序。
- 详细可见性只生成标题和业务时间，时间是独立 detail，供 Android 第二行小字渲染。
- 工作区去抖刷新和桥接发布测试通过。

## 未覆盖

- 未在真实 Android 启动器固定组件，未验证 RemoteViewsService 绑定、列表滚动、尺寸缩放、大字体、深色主题和冷进程点击。
- 未执行全量测试、Windows UI、平板、物理手机或发布构建。
