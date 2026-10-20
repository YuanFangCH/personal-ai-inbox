# S12 首轮设备矩阵（历史候选）

- 代码 SHA：`310b51e50bccfa04f146eea751ab730d6e163a82`；运行开始时工作树干净。
- 命令：`powershell -ExecutionPolicy Bypass -File .\scripts\verify-secretary-e2e.ps1 -Platforms all -ResultRoot .\test-results\secretary-100-final -SkipVersionCheck`
- 结果：SEC-001–100 共 100/100 passed，failed 0、not executed 0。phone 50、tablet 25、Windows 25。phone AVD Android 15 1080×2400 @420dpi（411.4dp）；tablet AVD Android 15 2560×1600 @320dpi（1280dp）；Windows 11 10.0.26200，Flutter 集成 Runner 1440×900 测试视口。逐例状态、耗时、检索/请求指标和日志见同目录 `summary.json`、`cases/` 与三个平台日志。
- 矩阵使用实际 Flutter UI、隔离 SQLite/成果目录和确定性模型/同步/语音端口。设备模拟未测试真实 API Key、OneDrive/OAuth、麦克风采集或扬声器出声。
- **本结果是首轮候选的历史证据。**之后根据逐项审查继续加强 SEC 场景，修复 SEC-003 重命名控制器生命周期，并将 SEC-053 的不完整响应状态与模块契约对齐；这些修改改变了 Runner 和一项生产 UI 文件。最终验收必须在新提交 SHA 上重新执行完整 50/25/25，不能将本次 100/100 作为最终代码证明。
