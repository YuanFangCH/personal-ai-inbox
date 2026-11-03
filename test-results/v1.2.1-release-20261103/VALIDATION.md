# v1.2.1 预览发布验证

日期：2026-11-03（Asia/Singapore）。版本：1.2.1+9。

- 通过：初始工作区干净，main 领先 origin/main 7 个提交；hooksPath 指向本仓库 .githooks。
- 通过：powershell -ExecutionPolicy Bypass -File scripts/scan-public-release.ps1 -AllRefs，全部本地 Git 引用未命中内置秘密规则及禁止路径。
- 复用：test-results/secretary-ai-emulator-20261102/VALIDATION.md 的 Android 手机 50/50、平板 25/25、真实 DeepSeek 冒烟；仅版本/文档/CI 变化，不重复模拟器矩阵。
- 复用：迁移清理、迁移后编辑和工具名修复的既有定向测试，见对应 20261102 验证目录。
- 通过：暂存树秘密扫描（scan-public-release.ps1 -CurrentTreeOnly）、git diff --cached --check、版本 1.2.1+9 与 v1.2.1 发行说明/标签契约核对。
- 待执行：GitHub CI/Release、新构建资产哈希/版本/签名核验。
- 未执行：全量测试、Windows 启动/25 场景、用户真实手机工具修复覆盖安装、真实云盘/通知验证。

CI 测试明确选择 8 个相关测试文件；不再通过无参数 flutter test 间接触发全量测试。发布流水线增加源码秘密扫描，并仅从干净 checkout 构建，无本机安全存储或临时凭据。

## 首次发布失败与修复

Release 41585739440：源码秘密扫描输出通过，但 git grep 无匹配的退出码 1 被 pwsh wrapper 继承。主机 pwsh -NoProfile -Command 调用已复现相同退出码 1；脚本在成功路径清零 LASTEXITCODE，不改变匹配时报错行为。首次未生成资产/Release，v1.2.1 标签将以限定旧值的 lease 更新到修复提交。

## 发布与独立资产验收（完成）

- 2026-11-03 14:02:34（Asia/Singapore）发布 v1.2.1，isPrerelease=true，资产 4/4；发布标签提交 cda8bc7a26595ea21737d646eaec636418bb1b30。
- Release 41585883431、main CI 41585877060 均 success。格式/analyzer 与 8 个指定文件的 36 项回归通过；Android/Windows 构建、APK 签名、安装卸载/便携包完整性检查通过。
- gh release download v1.2.1 --dir tests/agent-temp/v1.2.1-release-20261103/assets：四项资产已下载。Get-FileHash SHA256 全部与 GitHub API digest 一致，三个分发包与 SHA256SUMS.txt 一致，见 asset-hashes.txt/release.json。
- aapt2 dump badging：versionName=1.2.1、versionCode=9、minSdk=24、targetSdk=36；apksigner verify --verbose --print-certs：v2=true，证书 SHA-256=51b5e2f3f44ce9374cb680a0173c6498a4e13c718c602a355a8b6a50523f4816。见 apk-version.txt/apk-signature.txt。
- Windows 便携包提取 EXE 读取元数据，不启动程序：FileVersion/ProductVersion=1.2.1+9，归档 26 条目，见 windows-version.txt/windows-archive.txt。
- pwsh -NoProfile -File tests/agent-temp/v1.2.1-release-20261103/scan-assets.ps1 -AssetRoot tests/agent-temp/v1.2.1-release-20261103/assets：408 个文件/解压条目，以 Latin1 与 UTF-16LE 扫描常见 API Key、GitHub/Google/Slack/AWS token、私钥和 Bearer 格式，APK/便携包另查禁止凭据路径，未命中。安装器仅扫描外层二进制；内部 payload 以同次构建的便携包扫描及 CI 安装检查补充，不宣称独立解包扫描。见 asset-secret-scan.txt。
- 补充 git grep 全部本地引用的 github_pat/glpat 模式通过，未输出秘密值。
- 规则扫描未发现泄露，不等于可证明绝对不存在任何格式的秘密；未读取或上传本机安全存储、用户数据、临时代理或 AVD。

本次仅追加发布交接文档，不改变已构建代码；复用上述通过结果。全量测试、Windows 应用启动、用户真实手机工具修复覆盖安装仍未执行。
