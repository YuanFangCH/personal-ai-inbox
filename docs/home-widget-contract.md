# Android 桌面小组件 v2 合同

状态：2026-11-19 实施合同。逻辑卡片、Flutter 快照和启动器实例仍是三个独立对象；原生渲染由单一可滚动 `ListView` 承担，不再使用 `StackView`、页号、翻页按钮或卡片套卡片。

## 目标与不变量

- 首页表模块和桌面小组件只显示未完成待办，以及笔记、日程和事件；待办完成后从下一次数据通知中自动消失。
- 业务时间取待办 `due`、日程 `start`、事件 `occurredAt`。有时间条目按升序，无时间条目最后；同时间按 ID，无时间同组按更新时间倒序。
- 卡片默认 `titles`，只投影标题。选择 `title_time` 时，时间作为标题下一行的小字；不生成右侧时间栏。
- Android 使用一个连续时间轴，超过可视高度的内容由 `ListView` 滚动。快捷来源、ID 去重、每卡 48 条和整包 512 KiB 上限保持。
- 配置、快照和绑定留在本机，不进入成果同步、可移植设置或系统备份。表变更由现有 Flutter 监听去抖刷新。

## 文件结构

| 层次 | 文件 | 职责 |
|---|---|---|
| 共享排序 | `app/lib/core/table_entry_order.dart` | 业务时间、统一比较器、首页/桌面可见条目 |
| 首页 | `app/lib/ui/pages/home_page.dart` | 表模块调用共享可见条目规则 |
| Dart 合同 | `app/lib/modules/home_widgets/home_widget_contract.dart` | 卡片、分区、可见性、快照 JSON 和兼容解析 |
| Dart 投影 | `app/lib/modules/home_widgets/home_widget_projection.dart` | 来源筛选、完成待办排除、统一时间排序和隐私投影 |
| Dart 工作区 | `app/lib/modules/home_widgets/widget_workspace.dart` | 配置提交、快照限制、数据变更后发布 |
| 配置 UI | `app/lib/ui/pages/widget_settings_page.dart` | 新建/编辑卡片和显示方式 |
| Android 渲染 | `app/android/app/src/main/kotlin/com/yuanfang/aitext/personal_ai_inbox/HomeWidgetRenderer.kt` | RemoteViews 外壳、空态、占位和集合项 |
| Android 集合 | `app/android/app/src/main/kotlin/com/yuanfang/aitext/personal_ai_inbox/HomeWidgetListService.kt` | 只读行数据源与滚动列表 |
| Android 实例 | `app/android/app/src/main/kotlin/com/yuanfang/aitext/personal_ai_inbox/HomeWidgetProvider.kt` | 绑定、更新、重建和发布后通知 |
| Android 点击 | `app/android/app/src/main/kotlin/com/yuanfang/aitext/personal_ai_inbox/HomeWidgetOpenActivity.kt` | 校验快照版本并把目标送入 Flutter |
| Android 布局 | `app/android/app/src/main/res/layout/home_widget_scroll.xml`、`home_widget_entry_item.xml` | 外壳、连续行和标题下一行时间 |

`home_widget_page.xml`、`home_widget_entry_item_wide.xml`、固定行/紧凑布局、`HomeWidgetPager.kt` 和 `HomeWidgetClickReceiver.kt` 不再属于 v2 运行链。

## Dart API

```dart
DateTime? businessTimeOf(TableEntryDocument entry);
int compareTableEntriesByBusinessTime(
  TableEntryDocument left,
  TableEntryDocument right,
);
List<TableEntryDocument> visibleTableEntriesByBusinessTime(
  Iterable<TableEntryDocument> entries,
);

WidgetSnapshot projectCard(CardDefinition card, {
  required TableContentSnapshot source,
  required DateTime localNow,
});
WidgetProjection projectCardDetails(CardDefinition card, {
  required TableContentSnapshot source,
  required DateTime localNow,
});
WidgetSnapshotEnvelope constrainWidgetSnapshots(List<WidgetSnapshot> snapshots);
Future<WidgetPublishResult> refreshWidgets();
```

`visibleTableEntriesByBusinessTime` 返回不可变列表，过滤已完成待办后排序；首页表模块和投影直接使用同一结果语义。`projectCardDetails` 返回 `WidgetProjection(snapshot, matchingCount, warnings)`，其中 `matchingCount` 是完成过滤、业务时间筛选和 ID 去重后、48 条上限前的数量。`constrainWidgetSnapshots` 返回满足 v1 schema 和 512 KiB 上限的 envelope。

`SectionSpec.todoState` 与 `sort` 保留用于读取旧配置和秘书兼容；新 UI 固定提交 `todo_state=open`、`sort=business_time/asc`。投影始终排除完成待办，并以统一业务时间轴排序，因此旧卡片保存的 `any | done | updated_at | desc` 不会把完成项重新带回桌面。

显示模式：

| 值 | 快照内容 | Android 表现 |
|---|---|---|
| `hidden` | 无条目 | 通用隐私占位 |
| `titles` | 标题 | 单行标题 |
| `title_time` | 标题 + 业务时间 | 标题一行，时间小字下一行 |
| `fields` | 旧版标题 + 字段 | 标题一行，字段小字下一行；保留兼容 |

## Android API

```kotlin
internal object HomeWidgetRenderer {
    fun render(context: Context, manager: AppWidgetManager, widgetId: Int): Boolean
    fun entryItem(
        context: Context,
        widgetId: Int,
        card: HomeWidgetCard,
        row: HomeWidgetRow,
    ): RemoteViews
}

class HomeWidgetListService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory
}
```

`render` 返回实例是否写回系统。成功写回后调用 `notifyAppWidgetViewDataChanged(widgetId, R.id.widget_list)`，让新增、排序和完成待办排除立即反映到集合列表。`entryItem` 返回透明背景行，只设置标题、第二行详情和一次性点击填充意图。

`HomeWidgetListService` 的工厂 API：

| 函数 | 返回 | 说明 |
|---|---|---|
| `onCreate()` / `onDataSetChanged()` | `Unit` | 重新读取绑定卡片和快照 |
| `getCount()` | `Int` | 当前卡片 `entry` 行数 |
| `getViewAt(position)` | `RemoteViews` | 标题 + 可选第二行详情 |
| `getItemId(position)` | `Long` | 卡片、修订、表 ID 和条目 ID 的稳定哈希 |
| `getViewTypeCount()` | `Int` | 固定为 1 |
| `hasStableIds()` | `Boolean` | `true` |
| `getLoadingView()` | `RemoteViews?` | `null` |

通道仍为 `com.yuanfang.aitext.personal_ai_inbox/home_widgets`。`publishSnapshots({snapshot_json}) -> {submitted_count, failed_count}`、`clearSnapshots`、`requestPin` 和 `takeOpenTarget` 的返回形式不变。

## 刷新与失败

1. `TableLibrary` 提交完成状态后通知。
2. `WidgetWorkspace` 约 300 ms 去抖，重新读取一次 `contentSnapshot()`。
3. 投影排除完成待办，生成新 envelope。
4. Flutter 调用 `publishSnapshots`。
5. Provider 重绘外壳并通知 `ListView` 数据集变化。
6. 发布失败不回滚已保存卡片配置，回执标记 `pending`，下一次启动、回前台或内容更新重试。

迁移门阻断时清空原生快照并禁止投影。快照损坏或绑定失效时显示占位，不显示旧缓存内容。行点击按卡片 revision 和行哈希校验，过期点击只提示已过期，不打开错误条目。

## 执行与验证步骤

1. 在共享排序层实现完成待办过滤和不可见列表返回值。
2. 首页表模块改用共享列表，保持默认五行与展开。
3. 小组件合同默认业务时间升序，配置 UI 移除状态/排序选择并显示自动刷新说明。
4. 投影在类型筛选前排除完成待办，统一排序后应用快照上限。
5. Android 外壳改为 `ListView`，删除 `StackView` 页数据、翻页广播和页索引持久化。
6. 行布局始终使用标题加第二行详情，删除宽屏右侧时间变体。
7. Provider 写回后通知集合数据变化，覆盖待办完成后的自动消除。
8. 运行首页、投影、合同和工作区定向测试。
9. 运行目标 `dart analyze`、格式检查与 Android Debug APK 构建。
10. 更新 README、交接和 `test-results/home-flat-timeline-20261119/VALIDATION.md`，提交原子变更。
