# Android 桌面小组件 v1 合同

状态：v1 实现合同。2026-11-10 已随 Android 手机 `v1.6.0+14` 发布；已完成 Android 15 / API 35 手机模拟器桌面验收。荣耀 90 真机仍延后，属于后续复核项。

逻辑卡片、渲染快照和启动器实例是三个对象。Flutter 持有逻辑卡片，从 TableLibrary 投影快照；Kotlin 只保存快照及本机绑定，使用标准 RemoteViews。表内内容继续以 Markdown 为权威。卡片与快照不参与成果同步、设置导出或系统备份。

## Dart

在 `modules/home_widgets` 分离合同、投影、持久化及 workspace：

```dart
WidgetSnapshot projectCard(CardDefinition card, {
  required TableContentSnapshot source,
  required DateTime localNow,
});
WidgetProjection projectCardDetails(CardDefinition card, {
  required TableContentSnapshot source,
  required DateTime localNow,
});
WidgetSnapshotEnvelope constrainWidgetSnapshots(List<WidgetSnapshot> snapshots);
Future<List<CardSummary>> listCards({bool includeArchived = false});
Future<CardDefinition?> getCard(String cardId);
Future<CardPreview> previewCard(CardSpec spec, {String? cardId});
Future<CardWriteReceipt> applyCardCommand(CardCommand command, {
  required String operationId,
  required Future<bool> Function() authorize,
});
Future<WidgetPublishResult> refreshWidgets();
```

`WidgetProjection` 与 `CardPreview` 均返回 `snapshot`、`matchingCount`、`warnings`；匹配数在过滤、ID 去重后且应用 48 条卡片上限前统计。`projectCard` 只返回快照。无效旧表和旧字段以 warnings 表示。`constrainWidgetSnapshots` 返回满足 schema v1、512 KiB 总字节上限的 envelope，并从末尾卡片末尾条目开始裁剪，保留卡片记录及绑定语义。

- CardDefinition：`schema_version=1, card_id, revision, archived, spec`。ID 本地生成，版本从 1 递增。人工可见性另存 `hidden|titles|title_time|fields`；新卡默认为 titles。hidden 显示通用占位，AI 不得改变可见性；旧 fields 授权保持原行为，直到人工切换。
- CardSpec：`title, source_mode, sections, excluded_table_ids, hide_empty_sections, theme, include_open_todos?, include_recent_events?`。新增来源开关默认 false；JSON 缺省兼容旧配置，显式值必须是布尔值，false 在 JSON 中省略以保持旧命令签名。selected_tables 按 sections 顺序，all_tables 保留显式表配置再扩展未排除表；快捷来源跨表，遵循排除表。theme 为 system/light/dark。新建或编辑至少保留一张表或启用一个快捷来源；所选表不能同时排除。
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

openTargetAvailable 为原生发出的拉取提示，冷启动首帧也主动拉取。入口与现有分享通道分开。快照示例见 `app/test/fixtures/widget_snapshot_v1.json`。新快照每卡至多 48 条 entry 行；整包最多 512 KiB，从末尾卡片的末尾条目裁剪并设置 has_more，保留卡片和桌面绑定。只传显示用短文本与 ID。

Kotlin 的 bind(widgetId, cardId) 和 render(widgetId) 返回 Boolean；校验本 Provider 实例及有效卡片。取消配置不写绑定；固定请求只由用户发起，收到系统成功回调后绑定。移除实例只清绑定；系统恢复的实例重新选卡。归档实例显示占位。API 31+ 使用 `StackView` 和 RemoteCollectionItems 按条目分页，原生广播翻页；API 24–30 使用固定行与同 receiver 的按钮翻页。新快照只含条目行，原生仍读旧缓存中的 section 并跳过。条目点击沿用卡片 revision 与行 hash 校验后导航。日期筛选显示数据日期；数据在 App 启动、恢复前台和内容提交后刷新。

## 时间轴与首页排序

共享排序位于 `app/lib/core/table_entry_order.dart`：

```dart
DateTime? businessTimeOf(TableEntryDocument entry);
int compareTableEntriesByBusinessTime(
  TableEntryDocument left,
  TableEntryDocument right,
);
```

待办取截止时间，日程取开始时间，事件取发生时间，笔记无业务时间。有时间的条目升序、同时间按 ID 升序；无时间的条目放最后，按更新时间降序、再按 ID 排序。首页表模块、待办与表详情复用该比较器；今日安排仍只筛选当天，最近笔记仍按更新时间。

快捷来源匹配：

- `include_open_todos=true` 加入所有未完成待办，包括逾期和无截止时间的待办。
- `include_recent_events=true` 加入日程和有发生时间的事件，按本地时间筛选 `[today 00:00, today+7 days 00:00)`，不展开重复日程。
- 表来源保留原有 SectionSpec 类型、状态、日期窗和 limit，先按统一顺序排序再应用 limit。快捷来源跨表，所有来源遵循排除表。
- 多来源按 entry ID 去重并统一排序。preview `matchingCount` 是去重后、48 条全局上限之前的数量。仍沿用每卡 48 行和整包 512 KiB 上限。

`titles` 快照只含标题；`title_time` 只含标题与业务时间；`fields` 保留旧版自定义字段行为；`hidden` 不含条目或日期。时间格式 `M月d日 HH:mm`；全天只有日期，无业务时间时不生成 detail，跨年补年份。简洁快照不包含字段、状态或时间。

## Android 分页 Kotlin API

`HomeWidgetPager.kt` 提供纯分页，`HomeWidgetRenderer.kt` 提供原生渲染及目标页提交，翻页沿用 `HomeWidgetNavigation.kt` 与非导出 `HomeWidgetClickReceiver.kt`。

```kotlin
internal data class HomeWidgetPage(val index: Int, val rows: List<HomeWidgetRow>)
internal data class HomeWidgetPageRequest(
    val widgetId: Int, val cardId: String, val revision: Long,
    val generatedAtMs: Long, val pageIndex: Int,
)
internal object HomeWidgetPager {
    fun paginate(rows: List<HomeWidgetRow>, rowsPerPage: Int): List<HomeWidgetPage>
}
internal object HomeWidgetRenderer {
    fun render(context: Context, manager: AppWidgetManager, widgetId: Int): Boolean
    fun showPage(context: Context, manager: AppWidgetManager,
        request: HomeWidgetPageRequest): Boolean
}
```

`paginate` 保持输入顺序、只分页 entry 行；`rowsPerPage` 必须为正，空列表返回空页。容量按桌面高度和系统字体倍率估算，至少一行，API 24–30 另受六行布局上限约束。全量投影或尺寸变化回首页。`showPage` 校验 Provider、当前绑定、卡片版本、快照时间和页索引；无效请求返回 false，不导航。跨页只更新原生视图。桌面不显示卡片标题、表标题、条数或滑动提示；使用 App 浅蓝强调色及浅/深表面。

## 代码文件结构

- 排序：`app/lib/core/table_entry_order.dart`；调用者为 `ui/pages/home_page.dart`、`ui/pages/table_detail_page.dart`。
- 配置与投影：`modules/home_widgets/home_widget_contract.dart`、`home_widget_projection.dart`、`widget_workspace.dart`；设置 UI 为 `ui/pages/widget_settings_page.dart`；秘书适配为 `services/widget_tools.dart`，工具 Schema 在 `services/chat_service.dart`。
- Android：`HomeWidgetPager.kt`、`HomeWidgetRenderer.kt`、`HomeWidgetNavigation.kt`、`HomeWidgetClickReceiver.kt`；布局和颜色在 `res/layout`、`res/values/home_widget_colors.xml`。
- 不新增 MethodChannel 方法。`publishSnapshots({snapshot_json})` 仍返回 `{submitted_count, failed_count}`；`takeOpenTarget()` 仍只返回 null 或 Flutter 导航目标。翻页广播只在 Android 内部处理。

## 秘书

widget_list({}) 返回 cards 摘要；widget_get({card_id}) 返回 card 或 not_found。都需 appSettingsRead，并过滤超出表读取范围的卡片。widget_manage 接受 operation=create/replace/archive/restore：create 只要 spec；replace 要 card_id、expected_revision 和 spec；archive/restore 只要 ID 与版本。spec 可选 include_open_todos、include_recent_events；启用任一快捷来源必须有全表读取范围，显示模式仍由用户在设置页控制。返回 ChatWriteToolReceipt，data 含 card_id、revision、publish_status。仅有效完全权限且允许 appSettingsUpdate 时展示，执行、恢复和提交重查权限及表范围。all_tables 需要全表读取范围。沿用现有串行写链，用持久助手消息 ID 与工具调用标识构造幂等 ID。工具不返回原生实例 ID 或内容行。
