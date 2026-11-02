# H90y 迁移旧源清理

用户明确要求迁移完成后清理老数据。策略见 ADR 0023：清理活动旧源，保留校验备份、数据库/会话/设置快照及独立完成凭据；全局知识保留。

## 定向验证

- 修改 gate 确认迁移后旧源应消失的断言，修复前失败（旧源仍存在）。
- 清理采用先整批核验源/备份/hash、再写 prepared 清单、逐源删除、最后写 complete。新表内容不参与删除。
- service/gate/I/O 初步 14/14 通过；最终加入真实文件清理/重开，以及 runtime 启动与旧链接/同步门控后，共 19 个相关用例通过（14 个迁移用例及 app_runtime 5 个用例分别复用）。
- 对应命令：flutter test --no-pub test/table_migration_service_test.dart test/table_migration_gate_test.dart test/table_migration_io_test.dart test/app_runtime_test.dart（中间状态 18/18）；补充旧链接用例后 flutter test --no-pub test/app_runtime_test.dart 5/5。
- 清理用例覆盖：完成前拒绝删除、非全局普通源/删除记录清理、全局保留、新条目后续修改保留、备份损坏/旧源改变时整批不删除、删除中断后新服务续跑、重启仍识别迁移完成、清理后拒绝直接 rollback。
- 发现旧详情页先找旧源再转新表，清理后旧会话链接失效；新增 UI 回归修复前失败，调整为先按 ID 找新表/条目后通过。旧同步仍关闭，旧源横幅不再出现。
- 7 个最初改动文件 dart analyze 无诊断，格式通过；补充详情页/运行测试的 analyzer 进行中。
- 未执行全量测试。第一份清理构建成功（62.1 秒）但未安装，补齐链接修复后正在构建最终包。
- 私有截图/设备资料不提交；ADB 只用于覆盖安装和实际页面验证。

## 最终真机结果：通过

- 最终包 flutter build apk --release 成功（67.1 秒），apksigner verify --print-certs 通过，长期证书指纹一致。
- APK SHA-256 dca541ca21b16185d58b7a432a378903e756c518d5fce02b87df8a25f405f259；副本 tests/agent-temp/h90y-legacy-cleanup-20261102/h90y-cleanup.apk。
- adb install -r Success 后启动进入首页，旧源“查看旧资料”横幅已消失（gate 清理完成后重新预检，hasLegacyContent=false）。此手机原先 69 个旧格式源记录均为非全局资料；清理备份与完成记录由应用保留，不清理现有表和后续修改。
- 清理后连续两次 am force-stop + am start，UI 断言首页 Tab/今日安排存在，旧资料只读预检/查看旧资料/Bad state 均不存在：PASS / PASS。
- 表管理核对仍为 4 张表 / 66 条内容（26 日程、40 待办、事件 0）。未在真机另改真实条目。
- 定向 flutter/AndroidRuntime logcat 无错误输出。一次导航时 uiautomator 未等到 idle，重启后重新获取并完成数量核对；不使用该次旧 XML 作结论。
- analyzer 7 个迁移改动文件及补充详情页/运行测试 2 文件均无诊断；格式与 git diff --check 通过。
- 发布包不允许 run-as，未通过 ADB 独立读取私有目录、逐文件数残留或导出备份。实际删除与备份校验由应用服务执行（其成功后重新扫描活动旧源，横幅不再显示）；I/O 和故障回归验证备份可读及中断恢复。不得将此写成独立磁盘取证。
- 本地清理包仍为 1.2.0+8；未向 GitHub 推送或发布。上述结论取代前文进行中状态。
