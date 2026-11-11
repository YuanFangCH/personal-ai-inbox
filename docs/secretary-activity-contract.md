# 秘书运行活动与蓝色主题合同

## 运行活动

`app/lib/core/chat_activity.dart` 定义仅在进程内传递的运行状态和已完成工具调用投影。运行事件由 `ChatService.streamReply` 可选参数 `ChatActivitySink? onActivity` 同步发出；每次模型请求开始、首次推理、首次可见正文、真实重试等待和实际工具派发分别使用 `ChatActivityPhaseChanged` 或 `ChatActivityToolDispatched`。事件不含推理正文、工具参数、目标身份或工具结果。

工具活动由 `(round, callId)` 标识。工具轮次按 transcript 中 assistant 消息的顺序从 0 计数。只读工具在进入执行回调时派发活动，写入工具在既有意图落盘并通过取消检查、准备进入写执行器后派发。未派发调用不会显示。`completedChatActivityTools` 只投影拥有相同轮次工具回执的调用，不读取回执内容或声称工具操作成功。

`ConversationWorkspace.liveActivityFor(assistantMessageId)` 仅为本次仍在运行且未取消的 assistant 消息提供不可变快照。Workspace 校验生成取消令牌，按 `(round, callId)` 去重，并用 transcript 回执结算活动行。模型进入下一阶段时清空已结算的活动；完成、取消和失败时移除内存快照。历史活动直接从现有 `ChatMessage.toolTranscript` 重建，不添加持久化字段或数据库迁移。

聊天气泡通过 `_ChatActivityPanel(message, live)` 展示活动。运行时最多显示最近 6 条工具行；历史使用默认折叠的展开面板，按最近 20 条分页，提供工具名称中文标签和通用回退名。成功、失败、待确认和撤销状态仍由原操作卡片表达。

## 主题颜色

浅色强调色 `#216EAA / #FFFFFF`，选中容器 `#DCEFFF / #0D2C4B`；深色强调色 `#8FCAFF / #002A46`，选中容器 `#103B59 / #CDE8FF`。亮蓝按钮使用两种主题共用的 `primaryFixed=#80C5F6` 与 `onPrimaryFixed=#0D2C4B`。其余正文和页面背景保持原主题 token。

## 验证

定向活动投影、ChatService 活动时序、秘书 UI/大历史回归及相关 Dart analyze 命令与结果记录于 `test-results/secretary-activity-light-blue/VALIDATION.md`。
