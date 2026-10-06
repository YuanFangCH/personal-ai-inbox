# 荣耀手机与 Galaxy Tab 虚拟设备验收报告

> 日期：2026-10-04
> 范围：Android 15 / API 35 / x86_64 虚拟设备
> 用例：`app/test/fixtures/device_acceptance_100_cases.json`

## 虚拟设备

| 配置 | AVD | 模板 | 分辨率 | 密度 | 端口 |
|---|---|---|---|---|---|
| `honor-phone` | `aitext_honor_phone` | Pixel 6 | 1080x2400 | 420dpi | 5560 |
| `galaxy-tab` | `aitext_galaxy_tab` | Medium Tablet | 2560x1600 | 320dpi | 5562 |

两个 AVD 使用同一 Android 15 Google APIs x86_64 系统镜像。脚本在 AVD 缺失时自动创建，已存在时直接复用。

## 执行入口

完整虚拟验收：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\verify-virtual-device.ps1
```

保留模拟器供人工查看：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\verify-virtual-device.ps1 -KeepRunning
```

该入口依次执行：

1. 主机 100 条用例。
2. 构建 release APK。
3. 启动荣耀手机 AVD，执行 50 条 UI 用例。
4. 执行 `ACTION_SEND`、`ACTION_PROCESS_TEXT`、系统 chooser 和强停恢复探针。
5. 关闭荣耀手机 AVD。
6. 启动 Galaxy Tab AVD，重复 50 条 UI 和系统探针。
7. 关闭 Galaxy Tab AVD。

## 结果

| 层级 | 结果 |
|---|---|
| 主机 100 条 | 100/100 通过 |
| 荣耀 AVD UI | 50/50 通过 |
| 荣耀 AVD 系统入口 | 3/3 通过 |
| 荣耀 AVD 强停恢复 | 3/3 通过 |
| Galaxy Tab AVD UI | 50/50 通过 |
| Galaxy Tab AVD 系统入口 | 3/3 通过 |
| Galaxy Tab AVD 强停恢复 | 3/3 通过 |
| AVD 启动与自动关闭 | 通过 |

每个系统入口探针生成两张截图：

```text
app/build/device-acceptance/<profile>/<system_share|process_text|system_chooser>/
  after-share.png
  after-restart.png
```

本次共生成 12 张截图。

## 边界

虚拟设备只能验证应用布局、真实 Android 视口、Intent 分发、系统 chooser、markdown 落盘和进程重启恢复。它不能证明：

- HONOR MagicOS 与 Samsung One UI 的真实厂商 ROM 行为。
- 厂商电池优化、自启动、后台冻结和通知折叠。
- 真实分享面板的系统文案和布局差异。
- 物理屏幕、触控和长期锁屏行为。

物理设备接入后仍需运行 `scripts/verify-device-acceptance.ps1`。
