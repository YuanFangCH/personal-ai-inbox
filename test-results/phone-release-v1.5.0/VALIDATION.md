# Android 手机 v1.5.0 发布验证

日期：2026-11-09

状态：本地发布准备通过；GitHub main CI、Android Release 和公开资产核验待标签流水线完成。

## 本地检查

- `app/pubspec.yaml`：`1.5.0+12`。
- 标签：`phone-v1.5.0`。
- 发行说明：`docs/releases/v1.5.0.md`。
- `dart format --output=none --set-exit-if-changed lib test integration_test tool`：271 文件，0 change。
- `flutter analyze --no-pub`：0 issue。
- `scripts/scan-public-release.ps1 -CurrentTreeOnly`：通过。
- `git diff --check`：通过。
- 扩展发布门禁：292/292，通过；日志见 `local-release-gate-final.log`。
- 首次门禁发现并修正两个完全体测试文件的格式问题，以及一个仍把默认权限写死为自定义模式的过期断言；修正后完整门禁通过。失败日志保留在 `local-release-gate.log`。

## 复用验收

- 完全体模式主机定向：179/179，见 `../full-agent-mode-20261109/VALIDATION.md`。
- Android AVD 完全体开关与策略恢复：1/1。
- 真实 DeepSeek Android AVD：普通答复与 `table_list` 工具往返 1/1。
- 手机适用秘书矩阵：50/50，4 分 08 秒。
- 900 秒长测：实际 907 秒、37 条写入与读回、154 次模型请求；后台、锁屏、唤醒、重开和最终流式答复通过。
- 详见 `../phone-50-longrun-20261109/VALIDATION.md`。

## 待流水线核验

- main Flutter CI 成功。
- Android Release 成功，签名密钥恢复和长期证书指纹校验通过。
- 公开 APK 的 `versionName=1.5.0`、`versionCode=12`、minSdk 24、targetSdk 36 和必要权限正确。
- APK 为 v2 签名，证书 SHA-256 为 `51b5e2f3f44ce9374cb680a0173c6498a4e13c718c602a355a8b6a50523f4816`。
- GitHub Release `phone-v1.5.0` 为 pre-release，资产为通用 APK 与 `SHA256SUMS.txt`，公开哈希一致。
- 下载 APK 后复核大小、SHA-256、版本、权限和签名。

## 未覆盖

- 未执行全量 Flutter 测试。
- 未执行平板、Windows、物理 Android 设备、真实云盘同步或通知通道测试。
- 50 例矩阵和 900 秒长测使用本地脚本化模型；真实模型只覆盖普通答复和一次 `table_list` 工具往返。
