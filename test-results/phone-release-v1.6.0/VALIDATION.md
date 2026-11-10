# Android 手机 v1.6.0 发布验证

日期：2026-11-10  
设备：`aitext_agent_c_phone` / Android 15 / API 35 / `emulator-5620`  
隔离 ADB：`127.0.0.1:5041`  
结论：本地发布门禁通过；荣耀 90 真机与 API 24–30 按计划未执行。

## 版本与构建

- 候选版本：`1.6.0+14`。
- Debug 候选：`app/build/app/outputs/flutter-apk/app-debug.apk`，241,453,479 字节，SHA-256 `5fc70664d8c03fdf416a3239f880a8fcfacb88b0a13ac80cd515e55a05f00ab7`。
- APK 元数据：包名 `com.yuanfang.aitext.personal_ai_inbox`，minSdk 24，targetSdk 36。
- Debug 证书 SHA-256：`f473f1dcc6aa4242d2738fae9f9770fa3e089d0b109b614dfd14c1d71f65bbdf`。
- `flutter build apk --debug --no-pub` 通过，仅有既有 `flutter_tts` KGP 与 Android SDK XML 提示。
- `flutter analyze --no-pub`：0 issue；Dart formatter：289 文件，0 change。
- PDF 依赖升级到 `pdfrx 2.12.0` / `pdfium_dart 0.4.1`，并以保留许可证的本地依赖副本修正 GitHub 对 `%2F` 下载路径返回 404 的问题；`file_input_service_test.dart` 9/9 通过。

## 手机 50 例

命令：

```powershell
flutter test --no-pub -d emulator-5620 --reporter expanded `
  --dart-define=E2E_PLATFORM=phone `
  integration_test/secretary_100_android_test.dart
```

结果：

- `50/50` 通过，50 个唯一 `SEC-*` 用例 ID，首项 `SEC-001`、末项 `SEC-100`。
- 总用时约 4 分 06 秒；日志包含 `All tests passed!`，测试进程退出码 `0`。
- 日志：[phone-50.log](evidence/phone-50.log)。

## 900 秒长测

命令由
`scripts/run-secretary-agent-android-acceptance.ps1 -DeviceProfile phone -DeviceSerial emulator-5620 -Scenario longrun -DurationSeconds 900`
执行；本地 fixture 提供模型响应。

结果：

- 业务实际持续 `921` 秒，超过 900 秒门禁。
- 完成 47 条唯一写入与读回，累计 219 次模型请求。
- 从界面切到桌面、真实关屏 12 秒、确认目标 App 暂停，再唤醒并重新打开 App；后台任务继续并完成最终流式答复。
- `AGENT_LONGTASK_RESULT|phone|passed|921|47`，测试进程输出 `All tests passed!`，宿主最终退出码 `0`，清理失败为 `none`。
- 关键日志：[phone-longrun.stdout.log](evidence/phone-longrun.stdout.log)、[phone-longrun-orchestration.log](evidence/phone-longrun-orchestration.log)、[phone-longrun.stderr.log](evidence/phone-longrun.stderr.log)；摘要：[phone-50-longrun-summary.txt](evidence/phone-50-longrun-summary.txt)。

长测过程中修复了验收脚本对 Windows PowerShell 原生 stderr 和空 `.bat` 退出码的误判；修复后重新执行完整的 900 秒轮次。

## 小组件主机回归

命令：

```powershell
flutter test --no-pub --reporter expanded `
  test/home_widgets test/home_widget_bridge_test.dart `
  test/widget_tools_test.dart test/agent_tool_executor_test.dart
```

结果：`33/33` 通过。覆盖配置合同、确定性投影、日期筛选、隐私、原子存储、CAS/幂等、撤销、权限复核、刷新、桥接、秘书读写工具和工具执行链。最终依赖后的日志：[widget-host-tests-final.log](evidence/widget-host-tests-final.log)。

## Android 桌面验收

- 多表卡片：同一卡片显示“作业验收表”和“考试验收表”，包含类型筛选、未完成筛选、未来日期范围、业务时间排序和自定义字段。
- 尺寸：
  - 2×2 摘要：[widget-2x2.png](evidence/widget-2x2.png)
  - 4×2 短列表：[widget-4x2-fixed.png](evidence/widget-4x2-fixed.png)
  - 4×4 滚动：[collection-resized-final2.png](evidence/collection-resized-final2.png)、[collection-scrolled-final.png](evidence/collection-scrolled-final.png)
- 深色：`考试速览` 使用 Dark 主题，桌面标题、计数和条目可辨。
- 多实例：同一逻辑卡片的两个实例一起进入隐藏占位并一起恢复，见 [widget-hidden-both.png](evidence/widget-hidden-both.png) 与 [widget-restored-both.png](evidence/widget-restored-both.png)。
- 独立绑定：[appwidget-three-instances.txt](evidence/appwidget-three-instances.txt) 显示 3 个本应用实例；[widget-bindings-final.json](evidence/widget-bindings-final.json) 将其中两张实例绑定到 `学习总览`，另一张绑定到 `考试速览`。
- 取消固定：系统“Add to home screen”对话框选择取消后，实例数保持 3，未写入新绑定。
- 归档恢复：归档后同一卡片所有实例显示“已归档”；恢复后快照重新变为 `ready`，行数为 18 和 6：[widget-archived-snapshot.json](evidence/widget-archived-snapshot.json)、[widget-restored-after-archive.json](evidence/widget-restored-after-archive.json)。
- 点击：标题进入当前表，条目进入对应现有编辑页。
- 冷进程集合点击：先确认 App PID 消失，再点击 4×4 集合中的 `考试条目 1`；系统启动 `HomeWidgetClickReceiver` 和新进程，最终进入“编辑日程”。证据：[collection-cold-final.png](evidence/collection-cold-final.png)、[collection-cold-final.xml](evidence/collection-cold-final.xml)、[collection-cold-final.log](evidence/collection-cold-final.log)。

## 秘书权限

- 普通模式下 `widget_manage` 不在可执行工具体中，`widget_list`/`widget_get` 仍受 `appSettingsRead` 和表读取范围限制。
- 有效完全权限且允许 `appSettingsUpdate` 时允许创建、替换、归档和恢复逻辑卡片。
- 执行、恢复和实际提交前都会重新校验权限与表范围；`all_tables` 需要全表读取范围。
- AI 不操作桌面实例，也不修改卡片可见性等人工隐私设置。

## 覆盖升级

1. 使用同一 Debug 证书构建 `phone-v1.5.1` 对应提交 `9db8d2b`，APK 版本 `1.5.1+13`，SHA-256 `0dd706f808209cc7ed34e2c9906ef2cc2c491640e2e07777e5ba10cd0aa15e95a`。
2. 同签名覆盖安装后，合成数据保持 5 张表、17 条条目、1 个会话和 2 条消息。
3. 覆盖安装 `1.6.0+14` 后再次核对，仍为 5 张表、17 条条目、1 个会话和 2 条消息；界面显示“5 张表 · 17 条内容”，秘书历史仍含“请保留这条合成验收会话。”与“合成升级会话已保留。”。
4. 证据：[upgrade-old-home.png](evidence/upgrade-old-home.png)、[upgrade-old-history.png](evidence/upgrade-old-history.png)、[upgrade-new-history.png](evidence/upgrade-new-history.png)、[upgrade-new-tables3.png](evidence/upgrade-new-tables3.png)。

## 未覆盖

- 荣耀 90 / MagicOS 真机未执行，用户明确选择设备验收延后。
- 本机没有对应 API 24–30 AVD，固定行仅通过构建和既有 Android 实现检查，未做对应系统镜像实测。
- 未运行全量 Flutter 测试。
- 未验证 Windows、Android 平板专项、锁屏、负一屏、YOYO、桌面勾选待办或跨设备小组件同步。
- 所有表、条目、会话和桌面数据均为合成资料。
