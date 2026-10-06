---
status: accepted
---

# GitHub Release 作为首发渠道，并按标签自动构建

项目以 GitHub Release 作为 Windows 和 Android 的主要分发渠道。发布标签使用 `v<major>.<minor>.<patch>`，且必须与 `app/pubspec.yaml` 的版本一致；缺少对应的 `docs/releases/<tag>.md` 中文发行说明时，发布流程必须失败。

首发 `v1.0.0` 标记为 prerelease，同时提供通用 Android APK、Windows 11 x64 安装包、Windows 11 x64 便携 ZIP 和 `SHA256SUMS.txt`。Android 仍使用 Debug 证书，Windows 安装包仍未进行代码签名，因此不能宣称为稳定生产版本。正式稳定版需要先配置独立 Android 签名，并视需要在后续版本加入 Windows 代码签名。

自动发布由 `.github/workflows/release.yml` 在推送 `v*` 标签时触发。工作流重新执行格式、分析、测试、Android/Windows release 构建、APK 证书检查、安装与便携包冒烟验证，然后创建或更新 GitHub Release。安装器使用固定 AppId 和按用户安装目录，确保同一渠道的后续版本可以升级；便携 ZIP 保留完整运行目录，不依赖安装器。
