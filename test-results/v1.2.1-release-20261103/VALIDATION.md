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
