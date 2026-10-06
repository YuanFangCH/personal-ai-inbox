# 三星平板与荣耀手机 100 条验收报告

> 日期：2026-10-04
> 用例：`app/test/fixtures/device_acceptance_100_cases.json`
> 设备配置：荣耀手机 50 条、三星 Galaxy Tab 50 条

## 结果总览

| 层级 | 环境 | 结果 |
|---|---|---|
| 主机 100 条 | Flutter widget 测试，荣耀 390x844、平板 1280x800 | 100/100 通过 |
| 荣耀设备入口 50 条 | `aitext_honor_phone` AVD，`1080x2400 / 420dpi` | 50/50 通过 |
| Galaxy Tab 入口 50 条 | `aitext_galaxy_tab` AVD，`2560x1600 / 320dpi` | 50/50 通过 |
| 系统入口探针 | 两个专用 AVD 的 release APK | 6/6 通过 |
| 强停恢复探针 | 三种系统入口投递后强停并重启 | 6/6 通过 |
| 厂商身份负向门禁 | 模拟器误报为 HONOR | 正确拒绝：`manufacturer=google` |
| 荣耀物理设备 50 条 | 当前未连接 | 未执行 |
| Galaxy Tab 物理设备 50 条 | 当前未连接 | 未执行 |

模拟器结果只证明“同一测试入口可在设备侧实际分辨率运行”，不替代荣耀手机和 Galaxy Tab 的物理设备结论。双 AVD 的完整可重建流程见 [虚拟设备验收报告](2026-10-04-virtual-device-acceptance.md)。

## 执行命令

主机 100 条：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\verify-device-acceptance.ps1 -SkipPhysical
```

荣耀配置设备入口：

```powershell
flutter test integration_test/device_acceptance_physical_test.dart `
  -d emulator-5554 `
  --dart-define=DEVICE_UNDER_TEST=honor-phone `
  --reporter expanded
```

Galaxy Tab 配置设备入口：

```powershell
flutter test integration_test/device_acceptance_physical_test.dart `
  -d emulator-5554 `
  --dart-define=DEVICE_UNDER_TEST=galaxy-tab `
  --reporter expanded
```

## 统计

```text
Device acceptance matrix contains 100 independent cases: passed
100 host device acceptance cases: passed
50 honor-phone device-side cases: passed
50 galaxy-tab device-side cases: passed
honor-phone system_share: delivered and persisted after force-stop
honor-phone process_text: delivered and persisted after force-stop
honor-phone system_chooser: share panel selection delivered and persisted after force-stop
galaxy-tab system_share: delivered and persisted after force-stop
galaxy-tab process_text: delivered and persisted after force-stop
galaxy-tab system_chooser: share panel selection delivered and persisted after force-stop
```

用例分布：

| 操作 | 每台设备 |
|---|---:|
| 页面导航 | 9 |
| 字体缩放 | 12 |
| 上下滑动 | 6 |
| 横向滑动 | 5 |
| 待办筛选 | 4 |
| 详情进入 | 3 |
| 捕获提交 | 3 |
| 主题切换 | 3 |
| 滚动到底 | 2 |
| 主要按钮 | 3 |
| 合计 | 50 |

## 未覆盖

- 尚未在连接的真实 HONOR 手机和 Galaxy Tab S7 FE 上执行 100 条。
- 已自动验证分发包解析、`ACTION_SEND` / `ACTION_PROCESS_TEXT` 显式投递、系统 chooser 选择应用和强停恢复；物理机仍需检查厂商 ROM 的实际分享面板布局与文案。
- MagicOS/One UI 后台策略和本地通知仍需独立物理机探针。
- 当前应用未实现本地提醒通知，不能把本轮 UI 验收写成通知验收通过。
