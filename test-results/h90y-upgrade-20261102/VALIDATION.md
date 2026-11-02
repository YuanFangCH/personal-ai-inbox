# H90y 升级调试 2026-11-02

- ADB 无线连接成功，REA-AN00，已装 v1.2.0+8。UI 复现旧资料只读预检：69 条可读旧资料、拟建立 1 张表和 51 条内容；多条旧日历项被未来时间检查阻断。
- run-as 被发布包拒绝；没有清除数据/卸载/修改旧文件，没有执行真实迁移。凭据不写入记录。
- 修复前：flutter test test/table_migration_service_test.dart --plain-name 'dated legacy schedules remain migratable after their start time' 失败（canApply=false，旧日历时间阻断）。
- 修复后：flutter test --no-pub test/table_migration_service_test.dart test/table_migration_gate_test.dart test/table_migration_io_test.dart：10/10 通过。
- flutter analyze --no-pub lib/data/table_migration_service.dart test/table_migration_service_test.dart：无诊断。
- 回归覆盖：过去安排保留类型/原时间/正文、不设 occurredAt、旧源未改，时间推进后可读回完成 receipt；无日期/冲突/删除/草稿仍阻断，门控确认与 I/O。
- 过程中修正测试中 UTC/local DateTime 比较及旧 outputs 为空预期；上述最终命令已通过。
- 未执行全量测试。真实资料完整性及真机修复待覆盖安装后验证。

## 本机构建过程

- 首轮签名 release 构建失败：jni-1.1.0 的旧 `.cxx` 文件无法删除。已核实路径位于该插件 android 目录，移动到同目录 `.cxx-h90y-20261102-backup`，未删除源代码或用户资料。
- 第二轮失败：GeneratedPluginRegistrant.java 引用了 release 未包含的 integration_test 插件；使用带 pub 步骤的 release 构建重新生成插件注册。
- 长期证书已经 keytool 核验 SHA-256 为 51b5e2f3f44ce9374cb680a0173c6498a4e13c718c602a355a8b6a50523f4816。签名凭据只在构建进程使用，未写入仓库或日志。
- 初次文档写入脚本因 python 不存在未执行；已使用 PowerShell 和 apply_patch 写入。无应用行为影响。

## 修复包

- 第三轮 `flutter build apk --release` 成功。`apksigner verify --print-certs` 通过，长期证书指纹一致。
- 本地修复 APK SHA-256：f8d9bc0178cb95112b673c89a0f9c4e8b4b1fc8db36ee0144d2cdf243a98d811。
- APK 复制到 `tests/agent-temp/h90y-upgrade-20261102/h90y-upgrade-fix.apk`；构建生成的未跟踪 `app/android/.kotlin` 移入同任务临时目录。
- 首次 `adb install -r` 返回 device offline，尚未覆盖安装；正在重连。

- 重连原端口失败，adb devices 显示 offline，mDNS 未发现服务。已请求当前无线调试地址；真机修复验证明确未执行。
- dart format --output=none --set-exit-if-changed 两个改动 Dart 文件通过（此前第一次格式检查提示测试排版，已格式化）；git diff --check 通过。
