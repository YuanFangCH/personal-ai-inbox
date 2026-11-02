# H90y 迁移后修改导致重启阻断

## 复现与根因

- 用户反馈“无法正常打开”。无线连接后，UI accessibility 暂无文本；本地 screenshot 确认旧资料只读预检报 `Bad state: 迁移完成目标与预检不一致：vault/items/<todo-id>.md`。
- 截图仅存 tests/agent-temp/h90y-upgrade-followup-20261102/current.png，不提交私有内容。
- 原因：completedReceipt 每次启动都把当前目标与迁移时旧快照比较；正常编辑后的 hash 必然变化，导致完成状态被拒绝。此前真机只覆盖迁移后立即重启，未覆盖后续修改后重启，故上次通过不能证明本场景通过。
- 回归通过真实 TableRepository 更新迁移条目正文，修复前同名测试失败于相同 completedReceipt 报错。

## 修复和主机验证

- 已完成 journal 是一次性复制完成凭据；启动读取不再把当前表内容与旧快照做相等比较。完成 journal 记录的路径允许正常编辑；prepared/promoting 仍要求内容 hash 一致。
- apply 的完成重放校验和 rollback 的 hash 防覆盖保留；不重跑迁移、不恢复旧快照、不改用户后续内容。
- flutter test --no-pub test/table_migration_service_test.dart test/table_migration_gate_test.dart test/table_migration_io_test.dart：10/10 通过。
- 测试中的重启门控初次失败于 fixture 未配置 availableSpaceProbe（非业务问题），补齐确定性 fixture 后通过。
- 补充 apply/rollback 拒绝覆盖已编辑内容的断言后，仅重跑该回归：1/1 通过。
- flutter analyze 显示 No issues found 后遥测 TLS HandshakeException 导致进程退出 1；改用关闭遥测的 dart analyze 两个改动文件：无诊断、退出 0。
- dart format --output=none --set-exit-if-changed 两文件：通过。
- 未运行全量测试。签名包构建和真机后续验证进行中。

## 最终真机验证：通过

- flutter build apk --release 成功（77.8 秒），apksigner verify --print-certs 通过，长期证书 SHA-256 51b5e2f3f44ce9374cb680a0173c6498a4e13c718c602a355a8b6a50523f4816。
- 修复 APK SHA-256 ea682e4f32cabb8d3028b15594924c9b83a5edf4148ae07b525e5a97f12490e0，保存 tests/agent-temp/h90y-upgrade-followup-20261102/h90y-restart-fix.apk。
- adb install -r Success，启动恢复首页；未卸载/清数据/重迁移/回滚或手工修改用户条目。
- 覆盖安装后的截图与 UI 确认首页及原安排/待办可见，截图私有内容仅存任务临时目录。
- 在用户原有已修改数据上，循环两次 am force-stop + am start；uiautomator dump 断言首页 Tab 与今日安排均出现，且无 Bad state/迁移完成目标与预检不一致。结果 Cold start 1 PASS / Cold start 2 PASS。
- 定向 flutter/AndroidRuntime logcat 无错误输出。发布包不可 run-as，未独立导出私有数据库逐项对比后续修改；“不覆盖修改”同时由真实 repository 回归及本次未执行重迁移/回滚支持。
- 本次仅检查当前用户已修改的数据，不在真机额外编辑真实条目；主机回归覆盖迁移后正常编辑再初始化 gate，及重复 apply/rollback 仍拒绝覆盖修改。
- 此记录取代前文“真机验证进行中”的临时状态；修复仅本地安装，未推送或发布。
