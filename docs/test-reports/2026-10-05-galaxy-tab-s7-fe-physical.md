# Galaxy Tab S7 FE 物理设备验收报告

> 日期：2026-10-05
> 设备：Samsung Galaxy Tab S7 FE
> 序列号：已脱敏
> 用途说明：借来的测试设备，只安装本项目 APK，不清除系统数据、不恢复出厂、不卸载其他应用。

## 设备识别

| 项目 | 值 |
|---|---|
| 厂商 | `samsung` |
| 型号 | `SM-T736B` |
| 产品名 | `gts7xllitexeea` |
| Android | 14 / API 34 |
| 构建 | `UP1A.231005.007.T736BXXS9DYF1` |
| 屏幕 | 1600x2560 / 340dpi / 约 753dp 宽 |
| 存储 | `/data` 剩余约 49GB |
| 电源 | USB 供电，电量 100% |

设备通过 `galaxy-tab` 门禁：厂商为 Samsung，型号匹配 `SM-T73*`，逻辑宽度大于 600dp。

## 测试操作边界

- 未执行恢复出厂、数据清除、系统设置变更或设备重启。
- 安装的是本项目 APK；未卸载其他应用。
- 测试 Key 仅通过应用设置写入系统安全存储，验证完成后已通过设置界面清除，界面确认“模型未配置”。
- 平板上的应用和测试成果暂时保留，便于用户检查；未自动卸载。

## 执行结果

| 层级 | 结果 |
|---|---|
| 主机 100 条矩阵 | 100/100 通过 |
| Galaxy Tab 物理设备 UI | 50/50 通过 |
| `ACTION_SEND` 投递与强停恢复 | 通过 |
| `ACTION_PROCESS_TEXT` 投递与强停恢复 | 通过 |
| 系统 chooser 选择与强停恢复 | 通过 |
| 真实模型 SSE 与自动创建 | 通过 |

物理设备 UI 用例使用设备实际分辨率、密度和显示参数，只由测试控制字体缩放。

## 真机发现与修复

### 1. 重启恢复探针假设过时

新版应用分享后会打开 AI 会话，冷启动也会自动打开一个空白会话。旧探针只在首页查找分享文本，会把真实存在的持久化会话误判为失败。

修复后探针会在重启后：

1. 唤醒设备并关闭非安全锁屏遮罩。
2. 退出一层会话路由。
3. 进入“收件箱”会话列表。
4. 查找原分享文本。

### 2. Release APK 缺少 INTERNET 权限

`app/android/app/src/main/AndroidManifest.xml` 缺少 `android.permission.INTERNET`。Debug/profile manifest 自带该权限，因此之前的开发构建没有暴露问题，但 release APK 在真机上报错：

```text
Failed host lookup: 'api.deepseek.com'
```

修复后重新构建 release APK：

| 产物 | SHA-256 |
|---|---|
| Android release APK | `CAF39E61B1A4583EF0767FA5C1A7A9811F1B94041D74AC9B90A8317FC1265100` |

`aapt2 dump permissions` 已确认 release APK 包含：

```text
uses-permission: name='android.permission.INTERNET'
```

## 真实模型端到端

输入：

```text
明天下午三点和客户开会
```

结果：

- 模型流式请求成功。
- 自动记录卡片显示“与客户开会 / 已自动创建”。
- 打开成果后类型为“事件”。
- 开始时间为 `2026-10-06 15:00`。
- 标签为“会议、客户”。

截图：

- `app/build/device-acceptance/galaxy-tab/model-e2e/after-model-fixed.png`
- `app/build/device-acceptance/galaxy-tab/model-e2e/result-detail.png`

## 未完成

- 尚未连接荣耀手机，因此荣耀实机 50 条和厂商 ROM 验证仍待执行。
- 厂商电池优化、自启动、后台冻结和通知仍需在荣耀手机与 Samsung 真机上分别验证。
