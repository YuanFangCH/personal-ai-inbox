# 秘书 Android 模拟器全量检测

日期：2026-11-02  
代码提交：`a03b1e598d12b77db3c20d17bda4cea00a4c9ad0`

## 环境

- Flutter `3.47.6`，Android API 35 `google_apis/x86_64`。
- 手机：Pixel 6 AVD，1080×2400，420 dpi，逻辑宽度 411.4dp。
- 平板：Medium Tablet AVD，2560×1600，320 dpi，逻辑宽度 1280dp。
- 安装包：签名 release APK，`versionName=1.2.0`、`versionCode=8`。
- APK SHA-256：`8B9F21665DEEEE09065E9D46FB94E88434AEB4E9B0E42249837B1E86B2A8B26D`。
- v2 验签通过；证书 SHA-256：`51b5e2f3f44ce9374cb680a0173c6498a4e13c718c602a355a8b6a50523f4816`。

## 确定性回归

| 平台 | 场景结果 | 证据 |
|---|---|---|
| Android 手机 | 50/50 通过 | `drive/phone.log` |
| Android 平板 | 25/25 通过 | `drive/tablet.log` |
| 合计 | 75/75 通过 | 两个日志均包含 `All tests passed!` |

测试使用真实 Flutter UI、SQLite 和确定性模型/同步/语音 fixture；不调用云模型。Windows 25 场景按确认范围未执行。

本机 Android 15 AVD 上 `flutter test -d ...` 会停在 VM Service 附加阶段，测试代码尚未启动；改用同仓库 `test_driver/integration_test.dart` 的 `flutter drive` 后，同一测试目标全部通过。这属于本机测试工具链执行方式差异，不是应用场景失败。

## 真实 DeepSeek 冒烟

在全新手机 AVD 安装上述 release APK，通过临时安全输入配置 `https://api.deepseek.com`、`deepseek-flash` 和测试 Key：

| 检查 | 结果 |
|---|---|
| 设置页“测试模型连接” | 成功，回复 `connection-ok` |
| 发送“你好” | 收到完整秘书回复，无 HTTP 400 |
| “列出表库”工具轮 | 成功；返回事件、日程、待办三张默认表 |
| 首页往返 | 返回秘书页后，消息、工具结果和回复仍在 |
| 应用日志 | 未发现 HTTP 400、Flutter 未处理异常或 fatal crash |

实机证据：

- `live/live-connection-result.png`
- `live/live-share-hello.png`
- `live/live-tool.png`
- `live/live-tool.xml`
- `live/live-return.png`
- `live/live-return.xml`
- `live/live-app.log`

API Key 未写入仓库、命令输出、测试日志或本记录；验证后已执行应用数据清理、关闭模拟器并删除两个临时 AVD。

## 环境处理

- 本机 `C:\Users\18377\.android` 路径异常，Emulator 无法创建 `emu-last-feature-flags` 锁；通过隔离的 `ANDROID_EMULATOR_HOME` 绕开。
- D 盘接近耗尽，构建时把生成的 `app/build` 移到 C 盘并使用目录联接；源码、锁文件和用户数据未移动。
- 平板与手机同时运行时资源不足，改为串行执行两个 AVD。

## 未覆盖

- Windows 25 场景未执行。
- 用户真实手机尚未覆盖安装；其无线调试在上一轮排障时变为 `offline`，仍需恢复后安装并还原 Base URL。
- 未执行真实 OneDrive、通知、用户真实资料迁移或全平台测试。
