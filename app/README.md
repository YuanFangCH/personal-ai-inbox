# 个人 AI 收件箱

完整项目介绍、开源许可和安全说明见 [根目录 README](../README.md)。

Flutter 客户端首版，目标覆盖 Android 手机、Android 平板和 Windows。当前实现以本地闭环为先：

- 文本、分享内容与随手记先落本端，不阻塞等待模型。
- Markdown 是一个成果一个文件，SQLite 只保存索引与捕获状态。
- 内置首页、收件箱、日历、待办、事项、知识、确认、同步和设置。
- 收件箱提供本地多会话 AI 对话：每次冷启动新建会话，历史会话上下文相互隔离。
- 对话支持文本、剪贴板粘贴、相册、拍照和 Android 文本 / 图片分享，并通过 SSE 流式回复。
- 云端模型可以自动新建高置信、非敏感的成果；风险项进入待整理区，成功创建后保留 10 分钟撤销。
- 同步层已有 `SyncProvider` 接口、三项 hash 判定、冲突副本和墓碑逻辑。
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

## 验证

```powershell
flutter analyze
flutter test
flutter build web --release
```

200 条跨端回归矩阵：

```powershell
dart run tool/generate_regression_cases.dart
flutter test test/regression_200_cases_test.dart
```

Android 100 条 UI 矩阵：

```powershell
dart run tool/generate_android_ui_cases.dart
flutter test test/android_ui_100_cases_test.dart
flutter test integration_test/android_ui_100_test.dart -d emulator-5554
```

AI 对话与自动记录回归：

```powershell
flutter test test/conversation_store_test.dart
flutter test test/model_client_stream_test.dart
flutter test test/chat_flow_test.dart
flutter test test/chat_widget_test.dart
```

三星平板与荣耀手机 100 条设备验收矩阵：

```powershell
dart run tool/generate_device_acceptance_cases.dart
flutter test test/device_acceptance_100_cases_test.dart
flutter test integration_test/device_acceptance_physical_test.dart `
  -d <device-id> --dart-define=DEVICE_UNDER_TEST=honor-phone
flutter test integration_test/device_acceptance_physical_test.dart `
  -d <device-id> --dart-define=DEVICE_UNDER_TEST=galaxy-tab
```

带厂商和型号门禁的组合入口：

```powershell
powershell -ExecutionPolicy Bypass -File ..\scripts\verify-device-acceptance.ps1 -SkipPhysical
powershell -ExecutionPolicy Bypass -File ..\scripts\verify-device-acceptance.ps1 `
  -HonorSerial <honor-serial> -GalaxySerial <galaxy-tab-serial>
```

提供设备序列号时，脚本还会构建或复用 release APK，自动验证 `ACTION_SEND`、`ACTION_PROCESS_TEXT`、系统 chooser 选择和强制停止后的恢复，并把截图写入 `build/device-acceptance/`。
仅跳过系统探针时加 `-SkipSystemProbes`；正式验收不要跳过。

双 AVD 虚拟设备验收：

```powershell
powershell -ExecutionPolicy Bypass -File ..\scripts\verify-virtual-device.ps1
```

脚本会自动创建 `aitext_honor_phone` 和 `aitext_galaxy_tab`，依次执行主机 100 条、两台 AVD 各 50 条 UI 用例和系统入口探针，然后关闭 AVD。

20 个大型综合场景：

```powershell
dart run tool/generate_large_scenarios.dart
flutter test test/large_scenario_20_cases_test.dart
flutter test integration_test/large_scenario_20_test.dart -d <device-id>
```

每个场景包含两轮对话、1 个事项、2 个事件、1 个待办和 2 条知识，共 120 个自动记录载荷。

导出人工检查用 Markdown：

```powershell
dart run tool/export_large_scenario_vault.dart
```

输出到 `build/manual-review-vault/vault/`，包含 120 个大型场景成果和 100 条设备验收用例，共 220 份 Markdown。

真实平台冒烟：

```powershell
flutter test integration_test/windows_smoke_test.dart -d windows
flutter test integration_test/android_smoke_test.dart -d emulator-5554
```

Android release APK 当前使用 Flutter 模板的 debug 签名，便于本机安装验证；正式分发前需要配置独立签名密钥。
