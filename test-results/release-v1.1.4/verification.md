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

- 待执行：工作区扫描、提交和推送。
- 待执行：GitHub Actions Release workflow、四项资产下载/摘要核对及发布状态。
- 兼容限制：GitHub v1.1.1 资产签名指纹与新证书不一致；未找到旧私钥，不能直接覆盖旧安装。手机数据迁移另行评估。
