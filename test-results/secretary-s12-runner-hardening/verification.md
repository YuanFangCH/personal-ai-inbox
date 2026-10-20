# S12 首轮后 SEC 用例补强与重命名问题验证

- 状态：S12 首轮矩阵 100/100 通过，但后续对照逐条验收任务继续补强 Runner，并修复了重命名弹窗生命周期问题；最终设备验收仍待以更新提交 SHA 重新执行。
- 完整宿主用例：`cd app; E:\DevTools\Flutter\bin\flutter.bat test test/e2e/secretary_matrix_integrity_test.dart test/e2e/secretary_100_host_test.dart --reporter compact`，104/104 通过（4 项矩阵完整性 + 100 个 SEC 场景）。`dart analyze` 覆盖 ConversationWorkspace、对话页面动作、场景执行器、机器数据、矩阵检查和三端入口，无问题。
- 新增覆盖：SEC-001–010 逐项操作会话/历史重命名/待处理/权限/宽屏/图片；SEC-029–040 按范围检查全局知识、日期/类型、历史消息、详情、缓存、更新后索引、空结果、歧义、预算与 CAS；SEC-041–054 分成果类型、幂等、关联、版本冲突、撤销期限和工具完整性；SEC-055–072 覆盖候选待确认、拒绝、更新/陈旧目标、删除和用途保护；SEC-083–090 覆盖停止/重试、thinking 工具、联网禁用、离开页面取消与秘书角色；SEC-091–100 使用 TXT/PDF/DOCX/CSV、损坏/取消、图片和语音端口。
- 发现并修复：SEC-003 通过 UI 重命名会话时，弹窗动画期间过早 dispose 控制器会触发 `TextEditingController was used after being disposed`；改用 `TextFormField.initialValue/onChanged`。SEC-010 发现页面绕过注入的 `ImageInputService`，现由 `ConversationWorkspace` 暴露图库/相机选择命令，页面通过应用模块调用。SEC-089 现在验证离开对话页面会取消生成并停留在日历页；页面销毁时会取消尚未结束的生成。
- 定向宿主用例：SEC-001–010、SEC-040–049、SEC-050–059、SEC-060–069、SEC-080–089、SEC-090–099 均通过；SEC-095 损坏文件后仍可发送普通文本；SEC-053 按当前模块语义验证 `failed` 状态、没有写入且可以手动重试。
- 诊断运行 `test-results/secretary-100-final/20261020-103327-b721fb73/`：97 passed、3 failed。该脚本运行过程中源文件发生修改，phone APK 与后续 tablet/Windows 构建并非同一代码状态，**整轮作废，不计入任何最终矩阵结果**；失败暴露的 SEC-010/083/089 已修复。
- 未执行：本次补强提交对应的三端设备 100/100。必须先冻结新 SHA，再完整运行，结果全部通过后才能完成 S12。

## S12 二次设备诊断补记

最近一次全矩阵脚本记录在 `test-results/secretary-100-final/20261020-104657-97368b88/`：99 passed、1 failed（SEC-083）、0 not executed。该进程仍运行时调整过源文件，后续设备腿无法关联到相同源码，整轮作废。SEC-083 停止后续问的场景经修复，最终宿主矩阵 104/104 已过；需在修复提交后完整复跑设备矩阵。

## SEC-083 Phone 输入焦点诊断补记

最终矩阵第二次诊断在 `3947edf` 的 phone leg 已到 SEC-083：停止请求后输入框未聚焦，后续问句没有进入请求。Runner 增加聚焦和 pump 后，SEC-083 phone 单例 1/1 通过（模型请求 2 次，耗时 6819ms），但这只是脏工作树上的定向探针；完整矩阵被停止，需在包含该修复的新 SHA 上重跑。
