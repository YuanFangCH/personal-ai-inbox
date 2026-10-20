# S11 三端 SEC 矩阵 Runner 验证

- 状态：S11 数据、完整性门禁、宿主 Runner、Android/Windows 集成入口和 PowerShell 执行脚本已接入；三端完整 100 例仍待 S12。
- 宿主完整矩阵：`cd app; E:\DevTools\Flutter\bin\flutter.bat test test/e2e/secretary_matrix_integrity_test.dart test/e2e/secretary_100_host_test.dart --reporter compact`，104/104 通过（4 项完整性 + SEC-001–100）。矩阵含 100 个连续唯一 ID，phone/tablet/windows 为 50/25/25，9 类总数与计划一致；每例有 6 步、干净状态起点和持久状态断言。宿主使用实际 Widget/AppRuntime 和业务模块，使用内存适配器并模拟布局，不能替代设备矩阵。
- Android phone AVD 设备试跑 8/8：SEC-001、011、023、041、055、073、083、091；最终版 SEC-023 复测为 1 个模型请求、0 个 tool 消息、0 次本地检索。
- Android tablet AVD 设备试跑 1/1：SEC-098 转写可编辑后发送。
- Windows 桌面设备试跑 1/1：SEC-099 回复朗读和停止；Flutter Debug Windows 集成 Runner 编译通过。
- 执行脚本：`scripts/verify-secretary-e2e.ps1` 通过 PowerShell AST 语法解析；phone 50 / tablet 25 / Windows 25 和 CaseIds 定向入口通过真实设备试跑。结果按 run ID 归档到 `test-results/secretary-s11-runner-smoke/`，包括 manifest、设备尺寸、逐例 JSON 和日志；探索期修正 plain-name 过滤和 PowerShell Native stderr 处理的运行记录保留在其中，不计入通过数。
- 指标：每例记录执行耗时；检索用例记录 tool 搜索调用数、详情调用数和检索字符数；文件、模型场景记录文字量/请求数。模型、同步和语音使用确定性替身；设备用例使用真实 Flutter UI、隔离成果目录、SQLite 索引/会话库。
- 静态检查：SEC Runner/数据/三个集成入口定向 Dart analysis 无问题；PowerShell AST 解析和 `git diff --check` 通过。
- 尚未执行：phone 余下 42 例、tablet 余下 24 例、Windows 余下 24 例；三端完整 100/100；真实模型 Key、OneDrive、麦克风采集和扬声器出声。设备试跑发生在 S11 提交前的脏工作树上，只用于验证设备入口，最终验收须在干净提交 SHA 上进行。
