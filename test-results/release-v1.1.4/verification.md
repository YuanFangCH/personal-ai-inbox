# v1.1.4 固定签名与预览发布验证

## 本机验证

- 通过：`flutter build apk --release`，构建 `app/build/app/outputs/flutter-apk/app-release.apk`，版本 `1.1.4+6`。
- 通过：`apksigner verify --print-certs`；APK 指纹为 `51b5e2f3f44ce9374cb680a0173c6498a4e13c718c602a355a8b6a50523f4816`，与固定发布证书一致。
- 通过：模拟器 `emulator-5560` 首次安装 v1.1.4 及 `adb install -r` 同签名覆盖安装。
- 通过：未配置签名环境变量运行 `gradlew :app:assembleRelease --dry-run`，构建按预期失败并提示必须配置发布密钥。
- 通过：`flutter build windows --release`。
- 通过：`git diff --check`。
- 未执行：独立 YAML 解析器检查（本机未安装可用 YAML PowerShell 模块/Python）；推送后由 GitHub Actions 解析并执行工作流。
- 未验证：升级前应用用户数据的实际持久性；本次安装前模拟器没有该应用，未连接用户手机。
- APK SHA-256：`9f094e62562f222d9e58d5726dee3f1568bf23ab1adf12c5f6a08e16e710df9c`。
- Windows EXE SHA-256：`7c456d15709f82dd0e6c7982e3e57dd635d97433563ed93b9b5fa7fc6cecf41f`。

## 发布验证

- 通过：`scripts/scan-public-release.ps1 -CurrentTreeOnly`；GitHub Actions Release workflow [39444396527](https://github.com/YuanFangCH/personal-ai-inbox/actions/runs/39444396527) 全部成功，包括格式、静态分析、完整主机测试、Android/Windows Release 构建、APK 指纹校验、安装/卸载和便携包冒烟。
- 通过：预览版 [GitHub Release v1.1.4](https://github.com/YuanFangCH/personal-ai-inbox/releases/tag/v1.1.4) 已发布，`draft=false`、`prerelease=true`，包含 APK、Windows 安装包、便携 ZIP 和 `SHA256SUMS.txt`。
- 通过：从 GitHub 下载四项资产；三个二进制 SHA-256 与校验文件一致：
  - APK：`a67276d9178ccfff6242f63261dca97d6cdb7e7697c2ee52ca44d071a72f3686`
  - Windows 安装包：`5b9fc896b8d8399b56c8670bacbb0b71d40a97bbe3b8a89b5d3bb8d94be0878d`
  - Windows 便携包：`ec8f98b6d05d617eff61068ef3fa2b842058b0bbf203876cc471b87d6c7f2646`
- 通过：下载的 GitHub APK 证书指纹为 `51b5e2f3f44ce9374cb680a0173c6498a4e13c718c602a355a8b6a50523f4816`；模拟器对下载的发布 APK 再次执行 `adb install -r` 成功，版本 `1.1.4+6`。
- 兼容限制：GitHub v1.1.1 资产签名指纹与新证书不一致；未找到旧私钥，不能直接覆盖旧安装。手机数据迁移另行评估。
