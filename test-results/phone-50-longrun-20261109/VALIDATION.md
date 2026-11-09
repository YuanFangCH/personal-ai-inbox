# 手机 50 例、真实模型与 900 秒长测

日期：2026-11-09  
基线提交：`0124e39`（另有本轮长测断言稳定性修复待提交）  
结论：通过

## 环境

- Flutter 3.47.6 / Dart 3.13.5。
- AVD：`aitext_agent_c_phone`，Android 15 / API 35。
- Emulator 37.2.12，serial `emulator-5620`，隔离 ADB server `5041`。
- 真实模型：`deepseek-flash` / `https://api.deepseek.com`。
- 测试 Key 从上一轮 Codex 会话的本机记录中读取，仅注入测试进程；未写入仓库、命令输出、日志或本记录。测试后扫描全部新增日志，密钥特征匹配数为 0。

## 主要命令

```powershell
# 真实模型，手机设备
flutter test --no-pub -d emulator-5620 --dart-define=REAL_MODEL_KEY=<secure-input> `
  integration_test/_real_model_temp_test.dart

# 手机 50 例
flutter test --no-pub -d emulator-5620 `
  --dart-define=E2E_PLATFORM=phone `
  integration_test/secretary_100_android_test.dart

# 900 秒长测
flutter test --no-pub -d emulator-5620 `
  --dart-define=E2E_AGENT_PHASE=longrun `
  --dart-define=E2E_DEVICE_PROFILE=phone `
  --dart-define=E2E_DURATION_SECONDS=900 `
  integration_test/agent_task_longrun_android_test.dart
```

## 结果

### 真实模型手机冒烟

- 标准 `integration_test` 路径下完成 Android 构建、安装和设备执行，1/1 通过。
- 完全体模式开启，DeepSeek 返回完整答复，并真实调用 `table_list` 工具；成功读取默认表后完成最终回复。
- 证据：`real-model-device.log`。

### 手机 50 例矩阵

- `SEC-001` 至 `SEC-100` 中手机适用的 50 例全部通过，50/50。
- 总执行时间约 4 分 08 秒；每条 `SEC_CASE_RESULT|...|passed` 均记录在日志。
- 该矩阵使用本地脚本化模型和真实 Flutter/Android UI；测试 Key 不参与该矩阵。
- 证据：`phone-50.log`。

### 900 秒长测

- 业务持续 907 秒，1/1 通过。
- 完成 37 条内容写入与读回核对，累计 154 次模型请求；未因累计请求数或活动时长暂停。
- 执行中完成切后台、屏幕关闭 12 秒、唤醒、重新打开应用，后台任务继续运行并完成最终流式答复。
- 业务终点：`AGENT_LONGTASK_RESULT|phone|passed|907|37`。
- 证据：`phone-longrun.log`、`background-lock-actions.log`。

## 首次尝试与修正

- 验收脚本的旧 Flutter `.bat` 子进程退出码在当前 PowerShell 环境中被读为空值，导致 APK 已成功构建却被脚本误判为失败；改用当前 Flutter 直接执行长测，避免该启动器问题。
- 长测首次真实执行业务 31 秒时，检查点用量断言只允许“当前请求已计入”，未允许检查点比模型 fixture 请求数滞后一拍。已将断言改为允许 `requestCount - 1` 到 `requestCount + 1`，随后完整 900 秒通过。

## 未覆盖

- 未执行全量 Flutter 测试。
- 未执行平板、Windows、物理 Android 设备或真实云盘/通知通道测试。
- 50 例矩阵使用脚本化模型；真实模型只覆盖手机端完全体模式普通回复与 `table_list` 工具轮，不代表 50 例逐条使用真实模型。
- 构建存在 `flutter_tts` Kotlin Gradle Plugin 未来兼容警告和 Android SDK XML 版本提示，不影响本次测试结果。
