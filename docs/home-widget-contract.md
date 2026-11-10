# Android 桌面小组件 v1 合同

状态：v1 实现合同。2026-11-10 已完成 Android 15 / API 35 手机模拟器桌面验收；荣耀 90 真机仍延后，属于后续发布复核项。

逻辑卡片、渲染快照和启动器实例是三个对象。Flutter 持有逻辑卡片，从 TableLibrary 投影快照；Kotlin 只保存快照及本机绑定，使用标准 RemoteViews。表内内容继续以 Markdown 为权威。卡片与快照不参与成果同步、设置导出或系统备份。

## Dart

在 `modules/home_widgets` 分离合同、投影、持久化及 workspace：

```dart
WidgetSnapshot projectCard(CardDefinition card, {
  required TableContentSnapshot source,
  required DateTime localNow,
});
Future<List<CardSummary>> listCards({bool includeArchived = false});
Future<CardDefinition?> getCard(String cardId);
Future<CardPreview> previewCard(CardSpec spec, {String? cardId});
Future<CardWriteReceipt> applyCardCommand(CardCommand command, {
  required String operationId,
  required Future<bool> Function() authorize,
});
Future<WidgetPublishResult> refreshWidgets();
```

- CardDefinition：`schema_version=1, card_id, revision, archived, spec`。ID 本地生成，版本从 1 递增。人工可见性另存 `hidden|titles|fields`，默认 titles；hidden 显示通用占位，AI 不得改变可见性。
- CardSpec：`title, source_mode, sections, excluded_table_ids, hide_empty_sections, theme`。selected_tables 按 sections 顺序；all_tables 先显示显式配置，再按表名和 ID 追加未排除的表。theme 为 system/light/dark。
- SectionSpec：`table_id, label?, types, todo_state, days_ahead?, sort, limit, fields`。类型默认全选 note/todo/schedule/event；todo_state 为 any/open/done，后两项仅匹配待办；days_ahead 是以本地今日为起点、右端不含的 N 个自然日。业务时间为待办截止、日程开始、事件发生时间；普通笔记无业务时间。sort 为 `{key:updated_at|business_time|title,direction:asc|desc}`，默认更新时间倒序，空值末尾，条目 ID 破平局。limit 默认 4，范围 1–10。标题固定，可选最多三项 builtin:time、builtin:type、builtin:status、custom:<fieldId>。
- 已删除表不投影，恢复后重新显示。失效字段省略且预览告警。写入允许保留旧失效引用，拒绝新增失效引用。预览不持久化，返回样本、匹配数与告警。
- 命令为 create(spec)、replace(cardId, expectedRevision, spec)、archive/restore(cardId, expectedRevision)、人工 setVisibility(cardId, expectedRevision, visibility)、人工 undo(cardId, expectedRevision, targetOperationId)。replace 不改 ID、可见性或归档状态。撤销限最近一次写入、版本匹配且 10 分钟内；撤销创建即归档。
- 回执包含 operationId/status/cardId/revision/publishStatus，错误为 invalid_argument/not_found/revision_conflict/forbidden/operation_conflict/storage_error。相同操作 ID 和规范化命令读回原回执；异参冲突。配置、撤销材料和回执由单写者原子提交至 noBackupFilesDir/home_widgets；提交前重查权限。发布失败不回滚配置，回执标记 pending。
- TableLibrary 提交后约 300 ms 合并刷新，整轮共用一次 contentSnapshot()；启动、恢复前台、迁移成功和配置提交也刷新。串行发布，运行期间的新通知补跑一轮。迁移门阻断时清空原生快照，禁止写入、投影与导航。

## Android

通道 `com.yuanfang.aitext.personal_ai_inbox/home_widgets`：

| 调用 | 入参 | 返回 |
|---|---|---|
| getStoreDirectory | 无 | 私有目录路径 |
| publishSnapshots | {snapshot_json} | {submitted_count, failed_count}，仅表示向系统提交 |
| clearSnapshots | 无 | null |
| requestPin | {card_id} | requested / unsupported / failed |
| takeOpenTarget | 无 | null 或一次性 {kind:settings\|table\|entry, table_id?, entry_id?} |

openTargetAvailable 为原生发出的拉取提示，冷启动首帧也主动拉取。入口与现有分享通道分开。快照示例见 `app/test/fixtures/widget_snapshot_v1.json`。每卡至多 48 行，优先保留表头后填条目；整包最多 512 KiB，逆卡片顺序裁剪条目、再裁表头，设置 has_more。只传显示用短文本与 ID。

Kotlin 的 bind(widgetId, cardId) 和 render(widgetId) 返回 Boolean；校验本 Provider 实例及有效卡片。取消配置不写绑定；固定请求只由用户发起，收到系统成功回调后绑定。移除实例只清绑定；系统恢复的实例重新选卡。归档实例显示占位。标题使用直接 Activity PendingIntent；API 31+ 滚动集合使用可变 PendingIntent 模板与 fill-in Intent，经非导出 `HomeWidgetClickReceiver` 校验实例、卡片版本、快照行及哈希后再启动现有 Flutter 导航。冷进程点击会启动 App 并由 Flutter 查当前归属；已移动打开现位置，已删除回表列表并提示。API 31+ 大尺寸用单一滚动列表，4×2 使用短列表，2×2 使用摘要；API 24–30 固定行。日期筛选总是显示数据日期，App 重开或回前台重算。

## 秘书

widget_list({}) 返回 cards 摘要；widget_get({card_id}) 返回 card 或 not_found。都需 appSettingsRead，并过滤超出表读取范围的卡片。widget_manage 接受 operation=create/replace/archive/restore：create 只要 spec；replace 要 card_id、expected_revision 和 spec；archive/restore 只要 ID 与版本。返回 ChatWriteToolReceipt，data 含 card_id、revision、publish_status。仅有效完全权限且允许 appSettingsUpdate 时展示，执行、恢复和提交重查权限及表范围。all_tables 需要全表读取范围。沿用现有串行写链，用持久助手消息 ID 与工具调用标识构造幂等 ID。工具不返回原生实例 ID 或内容行。
