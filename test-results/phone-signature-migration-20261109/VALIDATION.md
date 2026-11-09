# 物理手机 Debug 到正式签名迁移

日期：2026-11-09

结论：通过。物理手机已从 `1.4.0+11` Debug 包迁移到公开 `v1.5.0+12` 长期签名包，应用私有数据保留。

## 设备与原因

- 设备：`HONOR REA-AN00`，Android 15 / API 35。
- 无线 ADB：`10.61.165.251:37905`。
- 原安装：`1.4.0+11`，包属性含 `DEBUGGABLE`。
- 原安装证书：`f026fcff0c43fb75287ba91a64cea8cf0aaba071aa07f532a12dd26f3b775aff`，`CN=Android Debug`。
- 正式长期证书：`51b5e2f3f44ce9374cb680a0173c6498a4e13c718c602a355a8b6a50523f4816`。
- `v1.1.4`、`v1.4.0`、`v1.5.0` 正式 APK 均使用同一长期证书；本次发布没有改变正式签名。

## 数据快照

- 备份目录：`D:\Dsk\aitext-backups\phone-signature-migration-20261109`。
- 最终完整快照：`app-private-final-20261109.tar`。
- 快照大小：`133,471,744` 字节。
- 快照 SHA-256：`0bd72320ed10a686a7f4c14037b71c029f13bf03ae60980e8c1fbfcc2c43d2d8`。
- 快照文件数：179，与设备归档时逐文件清单差集 0，缺失 0。
- 原安装 APK：`installed-base.apk`，SHA-256 `9092072da04becc1f2e266374b3756c8a4c8ecab9eb866ba7a28fe7a7cc888fe`。

## 迁移过程

- 从最终快照制作安全恢复包 `migration-restore-safe-v1.5.0.tar`，大小 `133,362,688` 字节，SHA-256 `b9f1db7f426b54432b6c6568ca776bec35396a2930932cd7ef025a3854e49bd3`。
- 恢复包保留 176 个文件，排除 3 个 `shared_prefs/FlutterSecure*` 文件；旧包的 Android Keystore 密钥随卸载失效，不能复用该加密凭据。
- 使用长期发布密钥构建临时迁移 APK `migration-release-signed-debug-v1.5.0.apk`：`1.5.0+12`、Debuggable、正式证书；大小 `202,435,833` 字节，SHA-256 `4539134fdec02a02fb4d9d92ded9550aa0501ec11ab8b1c8ce2f031faa6c75d5`。该 APK 仅用于本机迁移，不发布。
- 卸载 Debug 包、安装迁移包、设备内解包恢复数据并收紧私有文件权限。
- 迁移包冷启动成功，首页显示恢复后的待办；无迁移只读门。
- 覆盖安装公开 `personal-ai-inbox-v1.5.0-android.apk` 成功。

## 最终状态

- 正式包版本：`1.5.0+12`，minSdk 24，targetSdk 36。
- 正式包非 Debuggable。
- 设备端已安装 APK 大小：`90,977,347` 字节。
- 设备端已安装 APK SHA-256：`e4bd3d65e3b02a05258670e9d8fc6e545dbc758456102f18d0030788c578a71b`，与 GitHub Release 资产完全一致。
- 已安装证书：`51b5e2f3f44ce9374cb680a0173c6498a4e13c718c602a355a8b6a50523f4816`。
- 通知权限已恢复；旧包中录音权限原本未授予，保持未授予。
- 正式包冷启动 2.6 秒成功，首页显示原待办“数据结构·第4章作业-串（希冀平台）”等数据；无迁移只读门。
- 冷启动后最近 500 行日志未发现 `FATAL EXCEPTION`、`Unhandled Exception`、`PlatformException`、`E/flutter` 或 `SQLiteException`。
- 截图：`migration-home.png`、`official-home.png`。

## 未覆盖与后续

- API Key 保存在 Android Keystore 加密存储中，旧包卸载后无法恢复，需要在设置页重新输入。
- 尚未执行真实 API Key 连接、真实 AI 工具调用及新增内容后的多次重启持久化验证。
- 迁移 APK 含本机长期签名和可调试标志，只保存在本机备份目录，不得上传 Release。
