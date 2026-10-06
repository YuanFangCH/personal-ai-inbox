# 三星平板与荣耀手机设备验收体系

> 日期：2026-10-04
> 适用范围：荣耀 Android 手机、三星 Galaxy Tab S7 FE
> 与现有测试的关系：本体系补充物理设备门禁和导航包验证，不替代 200 条跨端矩阵或原有 Android 100 条 UI 矩阵。

## 1. 目标

把“能在模拟器运行”提升为“在指定 Android 设备上可重复验收”：

- 先按厂商、型号和屏幕等级确认设备身份，避免把模拟器或其他 Android 设备误报成目标机。
- 同一套 100 条用例既能在主机按目标尺寸回归，也能在真机使用实际分辨率、密度和显示参数运行。
- 目标设备各执行 50 条，合计 100 条；用例编号、预期动作和证据固定，失败可按编号定位。
- 主机验证与真机验证分开记录，不把模拟器结果写成物理设备结果。

## 2. 设备配置

| 配置 | 厂商门禁 | 型号或屏幕门禁 | 用例 |
|---|---|---|---:|
| `honor-phone` | `ro.product.manufacturer=HONOR` | 逻辑宽度小于 600dp | 50 |
| `galaxy-tab` | `ro.product.manufacturer=samsung` | `SM-T73*` 且逻辑宽度至少 600dp | 50 |

设备配置由 `scripts/verify-device-acceptance.ps1` 读取：

```text
ro.product.manufacturer
ro.product.model
ro.build.version.release
wm size
wm density
```

如果设备身份不符合配置，脚本在任何测试 APK 安装前失败。

## 3. 100 条用例

生成器：

```powershell
cd app
dart run tool/generate_device_acceptance_cases.dart
```

每个目标固定 50 条：

| 类别 | 数量 | 覆盖 |
|---|---:|---|
| 页面导航 | 9 | 首页、收件箱、日历、待办、事项、知识、同步、设置，并补一项收件箱深色合并确认检查 |
| 字体缩放 | 12 | 1.15x、1.3x、1.5x，重点页面检查 |
| 上下滑动 | 6 | 六个主要滚动页面 |
| 横向滑动 | 5 | 分段控件和横向滚动区域 |
| 待办筛选 | 4 | 全部、今天、即将到期、已完成 |
| 详情进入 | 3 | 事项和知识详情 |
| 捕获提交 | 3 | 浅色、深色和 1.5x 字体 |
| 主题切换 | 3 | 设置、同步和首页 |
| 滚动到底 | 2 | 长内容和设置页 |
| 主要按钮 | 3 | 首页、日历、待办主操作 |

固定文件：

- `app/test/fixtures/device_acceptance_100_cases.json`
- `app/test/device_acceptance_100_cases.g.dart`

## 4. 执行层级

### 4.1 主机矩阵

在主机上按荣耀 390x844 和 Galaxy Tab 1280x800 执行全部 100 条：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\verify-device-acceptance.ps1 -SkipPhysical
```

这一层用于防止用例定义、导航路径、控件定位和渲染回归。

### 4.2 虚拟设备矩阵

使用两个独立 AVD 先做可重复的虚拟验收：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\verify-virtual-device.ps1
```

脚本会自动创建或复用：

| 配置 | AVD | 模板 |
|---|---|---|
| `honor-phone` | `aitext_honor_phone` | Pixel 6 |
| `galaxy-tab` | `aitext_galaxy_tab` | Medium Tablet |

虚拟验收执行主机 100 条、两个 AVD 各 50 条 UI 用例，以及每台 AVD 的系统分享、文本处理和强停恢复探针。模拟器使用固定端口 5560 / 5562，验证结束后默认关闭；`-KeepRunning` 可保留设备。

本轮结果见 [虚拟设备验收报告](test-reports/2026-10-04-virtual-device-acceptance.md)。

### 4.3 物理设备矩阵

连接设备后分别执行 50 条：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\verify-device-acceptance.ps1 `
  -HonorSerial <荣耀设备序列号> `
  -GalaxySerial <三星设备序列号>
```

单设备执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\verify-device-acceptance.ps1 `
  -HonorSerial <荣耀设备序列号>
```

不执行系统入口探针时加 `-SkipSystemProbes`；不重新构建 release APK 时加 `-SkipReleaseBuild`。主验收不传这两个开关，确保使用当前源码构建并执行完整探针。

真机层不覆盖 Flutter 的物理分辨率和设备像素比，只设置用例要求的字体缩放；因此布局结果反映设备真实显示参数。

### 4.4 系统入口与持久化探针

主验收脚本在设备通过厂商门禁、完成 50 条 UI 用例后，会自动构建或复用 release APK，并执行以下探针：

1. 用 `cmd package query-activities` 确认本应用能解析 `ACTION_SEND text/plain`。
2. 用 `cmd package query-activities` 确认本应用能解析 `ACTION_PROCESS_TEXT text/plain`。
3. 用唯一短标记显式投递 `ACTION_SEND`，通过 UI 层验证成果已出现。
4. 强制停止进程并重新启动，确认同一标记仍可见，验证 Markdown 与索引恢复。
5. 对 `ACTION_PROCESS_TEXT` 重复投递、强停和恢复检查。
6. 不指定组件发起 `ACTION_SEND`，等待系统 chooser 出现，通过 UI 自动化点击本应用或“仅此一次”，再执行强停和恢复检查。
7. 每个“投递后”和“强停恢复后”状态都保存截图。

冷启动现在直接进入首页且不会创建空白会话。重启恢复探针从首页进入收件箱，验证分享内容所在会话和成果仍存在；系统分享携带内容时仍会按内容创建并打开会话。

证据目录：

```text
app/build/device-acceptance/<profile>/<system_share|process_text|system_chooser>/
  after-share.png
  after-restart.png
```

以下能力仍需要人工真机证据：

1. MagicOS 和 One UI 的电池优化、自启动、后台冻结对定时任务的实际影响。
2. 本地通知权限、锁屏展示、勿扰和重启后的提醒恢复。
3. 在物理设备屏幕上检查厂商 ROM 的实际分享面板布局和系统文案。

这些人工探针完成后，才能把对应设备标记为“完成实机验收”；不能以 100 条 UI 用例替代。

## 5. 通过标准

一次设备验收通过必须同时满足：

1. 主机 100 条全部通过。
2. 荣耀真机 50 条全部通过，且设备门禁输出为 `HONOR`。
3. Galaxy Tab 真机 50 条全部通过，且设备型号匹配 `SM-T73*`。
4. 执行日志包含设备序列号、Android 版本、分辨率、密度和最终测试计数。
5. 每个设备至少保存一张浅色截图、一张深色截图和一张 1.5x 字体截图。
6. 第 4.4 节的自动探针在两个设备上均通过，并已生成投递后与强停恢复后截图。
7. 第 4.4 节的人工探针有明确结果；未执行的项目必须标记为未验证，不能留空。

## 6. 代码入口

| 入口 | 用途 |
|---|---|
| `app/tool/generate_device_acceptance_cases.dart` | 生成固定 100 条用例 |
| `app/test/device_acceptance_100_cases_test.dart` | 主机 100 条矩阵 |
| `app/integration_test/device_acceptance_physical_test.dart` | 按 `DEVICE_UNDER_TEST` 在设备上执行 50 条 |
| `app/test/device_acceptance_case_runner.dart` | 加载和过滤目标设备用例 |
| `app/test/android_ui_case_runner.dart` | 执行导航、滚动、滑动、筛选、详情、捕获和主题动作 |
| `scripts/verify-virtual-device.ps1` | 自动创建、启动和回收双 AVD，执行虚拟设备全矩阵 |
| `scripts/verify-device-acceptance.ps1` | 设备身份门禁、主机回归、真机 UI 矩阵和系统入口探针编排 |
