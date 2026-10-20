# S12 首轮后 SEC 用例补强与重命名问题验证

- 状态：S12 首轮矩阵 100/100 通过，但后续对照逐条验收任务继续补强 Runner，并修复了重命名弹窗生命周期问题；下次最终设备验收必须绑定更新提交 SHA。首轮结果仍保留在 `test-results/secretary-100-final/20261020-100149-310b51e5/`，它只证明 SHA `310b51e`。
- 完整宿主用例：`cd app; E:\DevTools\Flutter\bin\flutter.bat test test/e2e/secretary_matrix_integrity_test.dart test/e2e/secretary_100_host_test.dart --reporter compact`，最近代码状态 104/104 通过（4 项矩阵完整性 + 100 个 SEC 场景）。`dart analyze` 覆盖 ConversationWorkspace、对话页面动作、场景执行器、机器数据、矩阵检查和三端入口，无问题。
- 新增覆盖：SEC-001–010 逐项操作会话/历史/待处理/权限/宽屏/图片；SEC-029–040 按范围检查全局知识、日期/类型、历史消息、详情、缓存、更新后索引、空结果、歧义、预算与 CAS；SEC-041–054 分成果类型、幂等、关联、版本冲突、撤销期限和工具完整性；SEC-055–072 覆盖候选待确认、拒绝、更新/陈旧目标、删除和用途保护；SEC-083–090 覆盖停止/重试、thinking 工具、联网禁用与秘书角色；SEC-091–100 使用 TXT/PDF/DOCX/CSV、损坏/取消和图片/语音端口。
- 发现并修复：SEC-003 通过 UI 重命名会话时，弹窗动画期间过早 dispose 控制器会触发 `TextEditingController was used after being disposed`；改用 `TextFormField.initialValue/onChanged`。SEC-010 发现页面绕过已注入的 `ImageInputService`，现由 `ConversationWorkspace` 暴露图库/相机选择命令，页面走应用模块。
- 定向验收：SEC-001–010 host 子集在最新状态通过；SEC-040–049、SEC-050–059、SEC-060–069、SEC-080–089、SEC-090–099 host 子集通过。损坏文件后继续普通文本的 SEC-095 与会话重命名 SEC-003 单例也已通过。
- SEC-053 非完整模型流依据现有模块语义标记为 `failed`，不写入成果并保留重试入口；计划断言已从“interrupted”校正为“failed/retryable”。
- 未执行：修正后代码的三端设备 100/100；必须先提交此批补强，再冻结干净 SHA 执行完整矩阵。真实云盘、模型 Key 和物理语音探针不在本轮模拟器替身范围。
