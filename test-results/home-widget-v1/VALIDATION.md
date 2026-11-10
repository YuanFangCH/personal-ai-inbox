# Android 桌面小组件原型验证

## API 35 手机模拟器验收 · 2026-11-10

- 正式候选已在 `aitext_agent_c_phone` / Android 15 / API 35 / `emulator-5620` 完成启动器验收。
- 通过：多表与自定义字段、日期和待办状态筛选、2×2 摘要、4×2 短列表、4×4 滚动、深色、同一卡片两个实例同步更新、不同卡片独立绑定、取消固定、归档和恢复、标题及条目导航、杀进程后条目冷启动。
- 通过：同一 Debug 签名从 `v1.5.1+13` 覆盖升级到 `1.6.0+14`，5 张合成表、17 条条目和含 2 条消息的会话均保留。
- 未执行：荣耀 90 真机、API 24–30 固定行对应系统镜像。
- 完整证据与筛选条件见 `test-results/phone-release-v1.6.0/VALIDATION.md`。

## 正式接入候选 · 2026-11-10

用户同意先完成正式接入，设备实测延后。集成基线 `9c46bb3`。

- 通过：`dart format` 检查本次 27 个 Dart 文件，无需格式调整；`dart analyze <本次 27 个 Dart 文件>` 无诊断；`git diff --check` 通过。
- 通过：在 `app/` 运行 `flutter test --no-pub --reporter expanded test/home_widgets test/home_widget_bridge_test.dart test/widget_tools_test.dart test/agent_tool_executor_test.dart test/app_runtime_test.dart test/table_migration_gate_test.dart test/app_background_lifecycle_test.dart`，45/45。覆盖投影与缓存裁剪、隐私、原子保存、撤销和版本冲突、幂等、授权复核、刷新失败回执、迁移门、通道与生命周期。
- 通过：`flutter build apk --debug --no-pub`。首次编译发现旧资源名和 AtomicFile 读取类型问题，修正后最终构建成功。现有 flutter_tts 的 Kotlin Gradle Plugin 兼容提醒仍在。
- 通过：用 `aapt2 dump badging` 和 `aapt2 dump xmltree` 核对 APK，包名为 `com.yuanfang.aitext.personal_ai_inbox`，min/target SDK 为 24/36，含 AppWidget Provider、配置 Activity、点击 Activity、固定回执 Receiver 和 API 31 尺寸元数据。候选路径 `app/build/app/outputs/flutter-apk/app-debug.apk`，SHA-256 `a2c6e7f3c26804780573e0e21cd8fee7405f0a8d50feefa91877658768a009fc`。
- 未执行：API 24–30、API 35 模拟器及荣耀 90 安装和桌面实际交互、同签名覆盖升级、全量测试、正式签名构建和发布。Debug 候选使用正式包名、Debug 签名，不能用于覆盖正式版。

## 隔离原型

2026-11-10，基线 `663b4ca`。

- 通过：在 `tests/agent-temp/home-widget-v1/prototype/` 运行 `powershell -ExecutionPolicy Bypass -File .\build.ps1`。最终隔离包 `com.yuanfang.aitext.widgetprototype`，minSdk 24，targetSdk 35，38,566 字节。APK SHA-256：`8df19d2faf08b8b9451fa0d57965c182bbafaf1e5ad4b236a1e1ce3cb61bfd9e`；构建及签名输出见原型的 `build/outputs/build-validation.txt`。
- 通过：PowerShell 解析共享 v1 JSON，确认包含两张合成表和不同条目目标；git diff --check。
- 未执行：用户要求暂缓设备实测。API 35 模拟器仅启动并确认系统版本，未安装或运行原型。荣耀 90 无线 ADB 离线，未安装。未覆盖添加、滚动、缩放、深色、点击、实例恢复或升级。
- 未执行：生产接入、生产 APK 构建、Flutter 定向或全量测试。该 APK 仅用于后续设备门禁。
